import { recordGameRequestMilestones } from "@/server/user-events";
import { NextRequest } from "next/server";
import { GameRequestStatus, GameSearchResponseStatus, GameSearchStatus, GameSearchType, Prisma } from "@prisma/client";

import { sendPushToUser } from "@/lib/push";
import { formatLocalDateTime } from "@/lib/timezone";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { isRouteSport } from "@/lib/sport-semantics";
import { updateGameSearchResponseSchema } from "@/lib/validators";
import { ensureMatchForUsers } from "@/server/matching";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";
import { assertActiveCourtIds } from "@/server/court-status";

type RouteSearchSource = {
  sport: string;
  runningRoute: string | null;
  runningRoutePoints: Prisma.JsonValue | null;
};

function gameRequestRouteData(search: RouteSearchSource) {
  if (!isRouteSport(search.sport)) {
    return {
      runningRoute: null,
      runningRoutePoints: Prisma.JsonNull
    };
  }

  return {
    runningRoute: search.runningRoute?.trim() || null,
    runningRoutePoints: Array.isArray(search.runningRoutePoints)
      ? (search.runningRoutePoints as Prisma.InputJsonValue)
      : Prisma.JsonNull
  };
}

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = updateGameSearchResponseSchema.parse(await request.json());

    const response = await prisma.gameSearchResponse.findUnique({
      where: { id: params.id },
      include: {
        gameSearch: true,
        responderUser: true
      }
    });

    if (!response) {
      return fail("Отклик не найден", 404);
    }

    const shouldRetryApprovedFinalization =
      body.status === GameSearchResponseStatus.approved && response.gameSearch.status !== GameSearchStatus.matched;

    if (body.status === response.status && !shouldRetryApprovedFinalization) {
      const { gameSearch, ...responseData } = response;
      const playersNeeded = Math.max(gameSearch.playersNeeded ?? 1, 1);
      let matchId: string | null = null;
      let gameRequestId: string | null = null;
      let regularPairId: string | null = null;

      if (body.status === GameSearchResponseStatus.approved) {
        const match = await prisma.match.findFirst({
          where: {
            OR: [
              {
                user1Id: gameSearch.createdByUserId,
                user2Id: response.responderUserId
              },
              {
                user1Id: response.responderUserId,
                user2Id: gameSearch.createdByUserId
              }
            ]
          },
          select: {
            id: true
          }
        });

        matchId = match?.id ?? null;

        if (gameSearch.searchType === GameSearchType.regular && playersNeeded === 1) {
          const regularPair = await prisma.regularPair.findUnique({
            where: {
              gameSearchId: gameSearch.id
            },
            select: {
              id: true
            }
          });

          regularPairId = regularPair?.id ?? null;
        }

        if (
          matchId &&
          gameSearch.searchType === GameSearchType.hot &&
          gameSearch.hotStartsAt
        ) {
          const gameRequest = await prisma.gameRequest.findFirst({
            where: {
              matchId,
              status: GameRequestStatus.accepted,
              createdByUserId: gameSearch.createdByUserId,
              matchedUserId: response.responderUserId,
              proposedCourtId: gameSearch.preferredCourtId ?? null,
              proposedDatetime: gameSearch.hotStartsAt
            },
            select: {
              id: true
            }
          });

          gameRequestId = gameRequest?.id ?? null;
        }
      }

      return ok({
        response: {
          ...responseData,
          responderUser: response.responderUser,
          createdAt: response.createdAt.toISOString(),
          updatedAt: response.updatedAt.toISOString()
        },
        matchId,
        gameRequestId,
        regularPairId,
        gameSearch: {
          id: response.gameSearchId,
          status: gameSearch.status,
          isActive: gameSearch.isActive
        }
      });
    }

    const isCreator = response.gameSearch.createdByUserId === user.id;
    const isResponder = response.responderUserId === user.id;

    if (!isCreator && !isResponder) {
      return fail("Нет доступа", 403);
    }

    if (body.status === GameSearchResponseStatus.approved || body.status === GameSearchResponseStatus.rejected) {
      if (!isCreator) {
        return fail("Подтвердить или отклонить отклик может только автор поиска", 403);
      }
    }

    if (body.status === GameSearchResponseStatus.withdrawn && !isResponder) {
      return fail("Отозвать отклик может только тот, кто его отправил", 403);
    }

    const playersNeeded = Math.max(response.gameSearch.playersNeeded ?? 1, 1);

    if (body.status === GameSearchResponseStatus.approved && response.status !== GameSearchResponseStatus.approved) {
      const approvedCount = await prisma.gameSearchResponse.count({
        where: {
          gameSearchId: response.gameSearchId,
          status: GameSearchResponseStatus.approved
        }
      });

      if (approvedCount >= playersNeeded) {
        return fail("Лобби уже собрано", 409);
      }
    }

    const acceptedRequestIds: string[] = [];
    const result = await prisma.$transaction(async (tx) => {
      if (body.status === GameSearchResponseStatus.approved) {
        await assertActiveCourtIds(tx, [response.gameSearch.preferredCourtId]);
      }
      const updated = await tx.gameSearchResponse.update({
        where: { id: response.id },
        data: {
          status: body.status
        },
        include: {
          responderUser: true
        }
      });

      let matchId: string | null = null;
      let gameRequestId: string | null = null;
      let regularPairId: string | null = null;
      let gameSearchStatus: GameSearchStatus | null = null;
      let gameSearchIsActive: boolean | null = null;

      if (body.status === GameSearchResponseStatus.approved) {
        const approvedCount = await tx.gameSearchResponse.count({
          where: {
            gameSearchId: response.gameSearchId,
            status: GameSearchResponseStatus.approved
          }
        });

        const match = await ensureMatchForUsers(tx, response.gameSearch.createdByUserId, response.responderUserId);
        matchId = match.id;
        const isFilled = approvedCount >= playersNeeded;
        const shouldCreateRegularPair =
          response.gameSearch.searchType === GameSearchType.regular && playersNeeded === 1;
        const shouldAutoFinalizeHotSearch =
          isFilled &&
          response.gameSearch.searchType === GameSearchType.hot &&
          playersNeeded === 1 &&
          Boolean(response.gameSearch.hotStartsAt);

        gameSearchStatus = shouldAutoFinalizeHotSearch ? GameSearchStatus.matched : GameSearchStatus.in_review;
        gameSearchIsActive = !isFilled;

        await tx.gameSearch.update({
          where: { id: response.gameSearchId },
          data: {
            status: gameSearchStatus,
            isActive: gameSearchIsActive,
            ...(shouldAutoFinalizeHotSearch
              ? {
                  scheduledCourtId: response.gameSearch.preferredCourtId,
                  scheduledAt: response.gameSearch.hotStartsAt,
                  scheduledDurationMinutes: response.gameSearch.durationMinutes
                }
            : {})
          }
        });

        if (shouldAutoFinalizeHotSearch && !shouldCreateRegularPair && response.gameSearch.hotStartsAt) {
          const proposedCourtId = response.gameSearch.preferredCourtId ?? null;
          const approvedResponses = await tx.gameSearchResponse.findMany({
            where: {
              gameSearchId: response.gameSearchId,
              status: GameSearchResponseStatus.approved
            },
            orderBy: {
              updatedAt: "asc"
            }
          });
          const scheduleText = `${formatLocalDateTime(user.timezone, response.gameSearch.hotStartsAt, { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", year: "numeric" })} · ${
            response.gameSearch.format
          }${response.gameSearch.durationMinutes ? ` · ${response.gameSearch.durationMinutes} мин` : ""}`;
          const venueText =
            response.gameSearch.customVenueAddress ??
            response.gameSearch.customVenueTitle ??
            response.gameSearch.runningRoute ??
            "Место уточняется";
          let rootRequestId: string | null = null;

          for (const approvedResponse of approvedResponses) {
            const approvedMatch =
              approvedResponse.responderUserId === response.responderUserId
                ? match
                : await ensureMatchForUsers(tx, response.gameSearch.createdByUserId, approvedResponse.responderUserId);
            const existingGameRequest = await tx.gameRequest.findFirst({
              where: {
                matchId: approvedMatch.id,
                status: GameRequestStatus.accepted,
                createdByUserId: response.gameSearch.createdByUserId,
                matchedUserId: approvedResponse.responderUserId,
                proposedCourtId,
                proposedDatetime: response.gameSearch.hotStartsAt,
                sport: response.gameSearch.sport,
                format: response.gameSearch.format
              },
              select: {
                id: true,
                sharedRootId: true
              }
            });

            const gameRequest: { id: string; sharedRootId: string | null } =
              existingGameRequest ??
              (await tx.gameRequest.create({
                data: {
                  matchId: approvedMatch.id,
                  sharedRootId: rootRequestId,
                  createdByUserId: response.gameSearch.createdByUserId,
                  matchedUserId: approvedResponse.responderUserId,
                  proposedCourtId,
                  proposedDatetime: response.gameSearch.hotStartsAt,
                  durationMinutes: response.gameSearch.durationMinutes ?? null,
                  sport: response.gameSearch.sport,
                  format: response.gameSearch.format,
                  ...gameRequestRouteData(response.gameSearch),
                  comment: response.gameSearch.comment?.trim() || "Игра из поиска подтверждена.",
                  status: GameRequestStatus.accepted
                },
                select: {
                  id: true,
                  sharedRootId: true
                }
              }));

            if (!existingGameRequest) acceptedRequestIds.push(gameRequest.id);

            if (!rootRequestId) {
              rootRequestId = gameRequest.sharedRootId ?? gameRequest.id;
            }
            if (approvedResponse.id === response.id) {
              gameRequestId = gameRequest.id;
            }

            if (!existingGameRequest) {
              await tx.chatMessage.create({
                data: {
                  matchId: approvedMatch.id,
                  gameRequestId: gameRequest.id,
                  senderUserId: response.gameSearch.createdByUserId,
                  text: `Отклик подтвержден: игра добавлена в ближайшие по параметрам поиска (${scheduleText} · ${venueText}).`
                }
              });

              await tx.chatMessage.create({
                data: {
                  matchId: approvedMatch.id,
                  gameRequestId: gameRequest.id,
                  senderUserId: response.gameSearch.createdByUserId,
                  text: "Организатор подтвердил(а) отклик. Договоренность сохранена в ближайших играх."
                }
              });
            }
          }

          gameSearchStatus = GameSearchStatus.matched;
          gameSearchIsActive = false;

          await tx.gameSearch.update({
            where: { id: response.gameSearchId },
            data: {
              status: GameSearchStatus.matched,
              isActive: false,
              scheduledCourtId: proposedCourtId,
              scheduledAt: response.gameSearch.hotStartsAt,
              scheduledDurationMinutes: response.gameSearch.durationMinutes ?? null
            }
          });

          await tx.gameSearchResponse.updateMany({
            where: {
              gameSearchId: response.gameSearchId,
              status: GameSearchResponseStatus.pending
            },
            data: {
              status: GameSearchResponseStatus.rejected
            }
          });

          await tx.gameSearchSlotProposal.updateMany({
            where: {
              gameSearchId: response.gameSearchId,
              status: "open"
            },
            data: {
              status: "closed"
            }
          });
        }

        if (shouldCreateRegularPair) {
          const preferredDays = (response.gameSearch.preferredDays ?? []) as Prisma.InputJsonValue;
          const preferredTimeRanges = (response.gameSearch.preferredTimeRanges ?? []) as Prisma.InputJsonValue;
          const regularPair = await tx.regularPair.upsert({
            where: {
              gameSearchId: response.gameSearch.id
            },
            update: {
              matchId: match.id,
              partnerUserId: response.responderUserId,
              preferredCourtId: response.gameSearch.preferredCourtId,
              sport: response.gameSearch.sport,
              format: response.gameSearch.format,
              preferredDays,
              preferredTimeRanges,
              comment: response.gameSearch.comment,
              status: "active"
            },
            create: {
              gameSearchId: response.gameSearch.id,
              matchId: match.id,
              createdByUserId: response.gameSearch.createdByUserId,
              partnerUserId: response.responderUserId,
              preferredCourtId: response.gameSearch.preferredCourtId,
              sport: response.gameSearch.sport,
              format: response.gameSearch.format,
              preferredDays,
              preferredTimeRanges,
              comment: response.gameSearch.comment,
              status: "active"
            }
          });

          regularPairId = regularPair.id;
          await syncRegularPairOccurrences(tx, regularPair.id);

          await tx.gameSearchResponse.updateMany({
            where: {
              gameSearchId: response.gameSearchId,
              id: {
                not: response.id
              },
              status: GameSearchResponseStatus.pending
            },
            data: {
              status: GameSearchResponseStatus.rejected
            }
          });
        }

        if (isFilled && !shouldCreateRegularPair) {
          await tx.gameSearchResponse.updateMany({
            where: {
              gameSearchId: response.gameSearchId,
              id: {
                not: response.id
              },
              status: GameSearchResponseStatus.pending
            },
            data: {
              status: GameSearchResponseStatus.rejected
            }
          });
        }

        if (
          isFilled &&
          response.gameSearch.searchType === GameSearchType.hot &&
          response.gameSearch.hotStartsAt
        ) {
          const proposedCourtId = response.gameSearch.preferredCourtId ?? null;
          const approvedResponses = await tx.gameSearchResponse.findMany({
            where: {
              gameSearchId: response.gameSearchId,
              status: GameSearchResponseStatus.approved
            },
            include: {
              responderUser: true
            },
            orderBy: {
              createdAt: "asc"
            }
          });
          const scheduleText = `${formatLocalDateTime(user.timezone, response.gameSearch.hotStartsAt, { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", year: "numeric" })} · ${
            response.gameSearch.format
          }${response.gameSearch.durationMinutes ? ` · ${response.gameSearch.durationMinutes} мин` : ""}`;
          const baseComment = response.gameSearch.comment?.trim() || "Игра из срочного поиска подтверждена.";

          await tx.gameSearch.update({
            where: { id: response.gameSearchId },
            data: {
              status: GameSearchStatus.matched,
              isActive: false,
              scheduledCourtId: proposedCourtId,
              scheduledAt: response.gameSearch.hotStartsAt,
              scheduledDurationMinutes: response.gameSearch.durationMinutes ?? null
            }
          });

          gameSearchStatus = GameSearchStatus.matched;
          gameSearchIsActive = false;

          if (playersNeeded === 1) {
            const existingGameRequest = await tx.gameRequest.findFirst({
              where: {
                matchId: match.id,
                createdByUserId: response.gameSearch.createdByUserId,
                matchedUserId: response.responderUserId,
                proposedCourtId,
                proposedDatetime: response.gameSearch.hotStartsAt,
                sport: response.gameSearch.sport,
                format: response.gameSearch.format
              },
              include: {
                proposedCourt: true
              }
            });
            let createdGame = existingGameRequest;

            if (createdGame && createdGame.status !== GameRequestStatus.accepted) {
              createdGame = await tx.gameRequest.update({
                where: { id: createdGame.id },
                data: { status: GameRequestStatus.accepted },
                include: {
                  proposedCourt: true
                }
              });
            }

            if (!createdGame) {
              createdGame = await tx.gameRequest.create({
                data: {
                  matchId: match.id,
                  createdByUserId: response.gameSearch.createdByUserId,
                  matchedUserId: response.responderUserId,
                  proposedCourtId,
                  proposedDatetime: response.gameSearch.hotStartsAt,
                  durationMinutes: response.gameSearch.durationMinutes ?? null,
                  sport: response.gameSearch.sport,
                  format: response.gameSearch.format,
                  ...gameRequestRouteData(response.gameSearch),
                  comment: response.gameSearch.comment,
                  status: GameRequestStatus.accepted
                },
                include: {
                  proposedCourt: true
                }
              });
            }

            if (existingGameRequest?.status !== GameRequestStatus.accepted) acceptedRequestIds.push(createdGame.id);
            gameRequestId = createdGame.id;

            if (!existingGameRequest) {
              const summaryText = `Горячий поиск подтвержден: ${scheduleText}. ${
                createdGame.comment?.trim() ? createdGame.comment : "Открой детали, чтобы обсудить игру отдельно."
              }`;

              await tx.chatMessage.create({
                data: {
                  matchId: match.id,
                  senderUserId: response.gameSearch.createdByUserId,
                  text: summaryText
                }
              });

              await tx.chatMessage.create({
                data: {
                  matchId: match.id,
                  gameRequestId: createdGame.id,
                  senderUserId: response.gameSearch.createdByUserId,
                  text: "Подтвердил(а) отклик на горячий поиск. Игра сразу зафиксирована, можно обсуждать детали здесь."
                }
              });
            }
          } else {
            let rootRequestId: string | null = null;
            let selectedRequestId: string | null = null;

            for (const approvedResponse of approvedResponses) {
              const participantMatch =
                approvedResponse.responderUserId === response.responderUserId
                  ? match
                  : await ensureMatchForUsers(tx, response.gameSearch.createdByUserId, approvedResponse.responderUserId);
              const existingGameRequest = await tx.gameRequest.findFirst({
                where: {
                  matchId: participantMatch.id,
                  createdByUserId: response.gameSearch.createdByUserId,
                  matchedUserId: approvedResponse.responderUserId,
                  proposedCourtId,
                  proposedDatetime: response.gameSearch.hotStartsAt,
                  sport: response.gameSearch.sport,
                  format: response.gameSearch.format
                }
              });
              let createdGame = existingGameRequest;

              if (!createdGame) {
                createdGame = await tx.gameRequest.create({
                  data: {
                    matchId: participantMatch.id,
                    sharedRootId: rootRequestId,
                    createdByUserId: response.gameSearch.createdByUserId,
                    matchedUserId: approvedResponse.responderUserId,
                    proposedCourtId,
                    proposedDatetime: response.gameSearch.hotStartsAt,
                    durationMinutes: response.gameSearch.durationMinutes ?? null,
                    sport: response.gameSearch.sport,
                    format: response.gameSearch.format,
                    ...gameRequestRouteData(response.gameSearch),
                    comment: baseComment,
                    status: GameRequestStatus.accepted
                  },
                  include: {
                    proposedCourt: true
                  }
                });
              }

              if (!existingGameRequest) acceptedRequestIds.push(createdGame.id);
              rootRequestId = rootRequestId ?? createdGame.sharedRootId ?? createdGame.id;

              if (createdGame.id !== rootRequestId && createdGame.sharedRootId !== rootRequestId) {
                await tx.gameRequest.update({
                  where: { id: createdGame.id },
                  data: { sharedRootId: rootRequestId }
                });
              }

              if (approvedResponse.responderUserId === response.responderUserId) {
                selectedRequestId = createdGame.id;
              }

              if (!existingGameRequest) {
                await tx.chatMessage.create({
                  data: {
                    matchId: participantMatch.id,
                    senderUserId: response.gameSearch.createdByUserId,
                    text: `Срочный поиск собран: ${scheduleText}. ${baseComment}`
                  }
                });

                await tx.chatMessage.create({
                  data: {
                    matchId: participantMatch.id,
                    gameRequestId: createdGame.id,
                    senderUserId: response.gameSearch.createdByUserId,
                    text: "Отклик подтвержден, состав собран. Игра добавлена в ближайшие."
                  }
                });

                await tx.match.update({
                  where: { id: participantMatch.id },
                  data: { updatedAt: new Date() }
                });
              }
            }

            gameRequestId = selectedRequestId ?? rootRequestId;
          }
        } else {
          await tx.chatMessage.create({
            data: {
              matchId: match.id,
              senderUserId: response.gameSearch.createdByUserId,
              text: shouldCreateRegularPair
                ? `Я подтвердил(а) твой отклик. Дальше у нас есть регулярная пара, можно быстро договориться о ближайшей игре. Открыть поиск: /play/searches/${response.gameSearch.id}.`
                : isFilled
                  ? `Я подтвердил(а) твой отклик. Состав собран, дальше можно согласовать детали. Открыть поиск: /play/searches/${response.gameSearch.id}.`
                  : `Я подтвердил(а) твой отклик. Уже собрано ${approvedCount} из ${playersNeeded} игроков. Открыть поиск: /play/searches/${response.gameSearch.id}.`
            }
          });
        }

        await tx.gameSearchMessage.create({
          data: {
            gameSearchId: response.gameSearch.id,
            senderUserId: user.id,
            text: shouldCreateRegularPair
              ? `${response.responderUser.name ?? "Игрок"} выбран(а) в регулярную пару. Остальные ожидающие отклики автоматически отклонены, чтобы сфокусироваться на паре.`
              : isFilled
                ? `${response.responderUser.name ?? "Игрок"} подтвержден(а). Состав собран, можно закрывать набор и назначать игру.`
                : `${response.responderUser.name ?? "Игрок"} подтвержден(а) в состав.`
          }
        });

        await tx.match.update({
          where: { id: match.id },
          data: { updatedAt: new Date() }
        });
      } else {
        const approvedCount = await tx.gameSearchResponse.count({
          where: {
            gameSearchId: response.gameSearchId,
            status: GameSearchResponseStatus.approved
          }
        });
        const remainingPending = await tx.gameSearchResponse.count({
          where: {
            gameSearchId: response.gameSearchId,
            status: GameSearchResponseStatus.pending
          }
        });

        const nextStatus =
          approvedCount >= playersNeeded
            ? "matched"
            : remainingPending > 0 || approvedCount > 0
              ? "in_review"
              : "active";
        const nextIsActive = nextStatus !== "matched";

        const existingRegularPair = await tx.regularPair.findUnique({
          where: {
            gameSearchId: response.gameSearchId
          }
        });

        if (existingRegularPair && existingRegularPair.partnerUserId === response.responderUserId) {
          await tx.regularPair.delete({
            where: {
              gameSearchId: response.gameSearchId
            }
          });
        }

        await tx.gameSearchMessage.create({
          data: {
            gameSearchId: response.gameSearch.id,
            senderUserId: user.id,
            text:
              body.status === GameSearchResponseStatus.withdrawn
                ? `${response.responderUser.name ?? "Игрок"} отозвал(а) отклик.`
                : `${response.responderUser.name ?? "Игрок"} убран(а) из откликов.`
          }
        });

        await tx.gameSearch.update({
          where: { id: response.gameSearchId },
          data: {
            status: nextStatus,
            isActive: nextIsActive
          }
        });

        gameSearchStatus = nextStatus;
        gameSearchIsActive = nextIsActive;
      }

      return { updated, matchId, gameRequestId, regularPairId, gameSearchStatus, gameSearchIsActive };
    });

    await recordGameRequestMilestones(acceptedRequestIds, "request_accepted", "search");

    if (
      (body.status === GameSearchResponseStatus.approved || body.status === GameSearchResponseStatus.rejected) &&
      response.responderUser.notificationGames
    ) {
      await sendPushToUser({
        userId: response.responderUserId,
        title:
          body.status === GameSearchResponseStatus.approved
            ? `${user.name ?? "Организатор"} одобрил твой отклик`
            : `${user.name ?? "Организатор"} отклонил твой отклик`,
        body:
          body.status === GameSearchResponseStatus.approved
            ? "Открой чат или поиск, чтобы продолжить договоренность."
            : "Можно вернуться в ленту и выбрать другой поиск.",
        href: result.gameRequestId
          ? `/play/games/${result.gameRequestId}`
          : result.matchId
            ? `/inbox/${result.matchId}`
            : `/play/searches/${response.gameSearchId}`,
        sound: response.responderUser.notificationSound ?? true
      });
    }

    return ok({
      response: {
        ...result.updated,
        createdAt: result.updated.createdAt.toISOString(),
        updatedAt: result.updated.updatedAt.toISOString()
      },
      matchId: result.matchId,
      gameRequestId: result.gameRequestId,
      regularPairId: result.regularPairId,
      gameSearch: result.gameSearchStatus
        ? {
            id: response.gameSearchId,
            status: result.gameSearchStatus,
            isActive: result.gameSearchIsActive ?? null
          }
        : null
    });
  } catch (error) {
    if (getErrorMessage(error) === "COURT_UNAVAILABLE") {
      return fail("Клуб временно недоступен", 409);
    }
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
