import { NextRequest } from "next/server";
import { GameSearchResponseStatus, GameSearchStatus, GameSearchType, Prisma } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updateGameSearchResponseSchema } from "@/lib/validators";
import { ensureMatchForUsers } from "@/server/matching";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";

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

    if (body.status === response.status) {
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
          playersNeeded === 1 &&
          gameSearch.preferredCourtId &&
          gameSearch.hotStartsAt
        ) {
          const gameRequest = await prisma.gameRequest.findFirst({
            where: {
              matchId,
              status: "accepted",
              createdByUserId: gameSearch.createdByUserId,
              matchedUserId: response.responderUserId,
              proposedCourtId: gameSearch.preferredCourtId,
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

    const result = await prisma.$transaction(async (tx) => {
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

        gameSearchStatus = isFilled ? GameSearchStatus.matched : GameSearchStatus.in_review;
        gameSearchIsActive = !isFilled;

        await tx.gameSearch.update({
          where: { id: response.gameSearchId },
          data: {
            status: gameSearchStatus,
            isActive: gameSearchIsActive,
            ...(isFilled && response.gameSearch.searchType === GameSearchType.hot
              ? {
                  scheduledCourtId: response.gameSearch.preferredCourtId,
                  scheduledAt: response.gameSearch.hotStartsAt,
                  scheduledDurationMinutes: response.gameSearch.durationMinutes
                }
              : {})
          }
        });

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
          playersNeeded === 1 &&
          response.gameSearch.searchType === "hot" &&
          response.gameSearch.preferredCourtId &&
          response.gameSearch.hotStartsAt
        ) {
          const createdGame = await tx.gameRequest.create({
            data: {
              matchId: match.id,
              createdByUserId: response.gameSearch.createdByUserId,
              matchedUserId: response.responderUserId,
              proposedCourtId: response.gameSearch.preferredCourtId,
              proposedDatetime: response.gameSearch.hotStartsAt,
              durationMinutes: response.gameSearch.durationMinutes ?? null,
              sport: response.gameSearch.sport,
              format: response.gameSearch.format,
              comment: response.gameSearch.comment,
              status: "accepted"
            },
            include: {
              proposedCourt: true
            }
          });

          gameRequestId = createdGame.id;

          const summaryText = `Горячий поиск подтвержден: ${createdGame.proposedDatetime.toLocaleString("ru-RU")} · ${
            createdGame.format
          }${createdGame.durationMinutes ? ` · ${createdGame.durationMinutes} мин` : ""}. ${
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
        } else {
          await tx.chatMessage.create({
            data: {
              matchId: match.id,
              senderUserId: response.gameSearch.createdByUserId,
              text: shouldCreateRegularPair
                ? "Я подтвердил(а) твой отклик. Дальше у нас есть регулярная пара, можно быстро договориться о ближайшей игре."
                : isFilled
                  ? "Я подтвердил(а) твой отклик. Состав собран, дальше можно согласовать детали."
                  : `Я подтвердил(а) твой отклик. Уже собрано ${approvedCount} из ${playersNeeded} игроков.`
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
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
