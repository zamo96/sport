import { NextRequest } from "next/server";
import { GameRequestStatus, GameSearchResponseStatus, GameSearchStatus, Prisma } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { resolveHotSearchStartAt, resolveSearchDays } from "@/lib/game-search";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { isFormatAllowedForSport } from "@/lib/sport-playbook";
import { hasExplicitSportProfile } from "@/lib/sport-levels";
import { isRouteSport } from "@/lib/sport-semantics";
import { updateGameSearchSchema } from "@/lib/validators";
import { ensureMatchForUsers } from "@/server/matching";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";

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
    const body = updateGameSearchSchema.parse(await request.json());

    const gameSearch = await prisma.gameSearch.findFirst({
      where: {
        id: params.id,
        createdByUserId: user.id
      }
    });

    if (!gameSearch) {
      return fail("Поиск игры не найден", 404);
    }

    if (gameSearch.status === GameSearchStatus.matched || gameSearch.scheduledAt) {
      return fail("Поиск уже перешёл в игру. Изменения вносите в карточке игры.", 409);
    }

    const nextScheduledAt =
      body.scheduledAt !== undefined ? (body.scheduledAt ? new Date(body.scheduledAt) : null) : gameSearch.scheduledAt;

    if (body.scheduledAt && nextScheduledAt) {
      const approvedCount = await prisma.gameSearchResponse.count({
        where: {
          gameSearchId: gameSearch.id,
          status: GameSearchResponseStatus.approved
        }
      });

      if (approvedCount === 0) {
        return fail("Сначала нужно подтвердить хотя бы один отклик, чтобы назначить игру", 409);
      }
    }

    const nextSearchType = body.searchType ?? gameSearch.searchType;
    const nextSport = body.sport ?? gameSearch.sport;
    const nextFormat = body.format ?? gameSearch.format;

    if (nextFormat != null && !isFormatAllowedForSport(nextSport, nextFormat)) {
      return fail("Этот формат недоступен для выбранного вида спорта");
    }

    const nextDesiredLevelMin = body.desiredLevelMin ?? gameSearch.desiredLevelMin ?? 1;
    const nextDesiredLevelMax = body.desiredLevelMax ?? gameSearch.desiredLevelMax ?? 10;
    if (nextDesiredLevelMin > nextDesiredLevelMax) {
      return fail("Минимальный уровень не может быть выше максимального");
    }

    const hasSportProfile = hasExplicitSportProfile(user.preferredSports, user.sportLevels, nextSport);
    const preferredDaysInput =
      body.preferredDays ??
      (Array.isArray(gameSearch.preferredDays)
        ? gameSearch.preferredDays.filter((item): item is string => typeof item === "string")
        : []);
    const preferredTimeRangesInput =
      body.preferredTimeRanges ??
      (Array.isArray(gameSearch.preferredTimeRanges)
        ? gameSearch.preferredTimeRanges.filter((item): item is string => typeof item === "string")
        : []);
    const preferredDistrictsInput =
      body.preferredDistricts ??
      (Array.isArray(gameSearch.preferredDistricts)
        ? gameSearch.preferredDistricts.filter((item): item is string => typeof item === "string")
        : []);
    const explicitHotStartsAt = body.hotStartsAt !== undefined ? (body.hotStartsAt ? new Date(body.hotStartsAt) : null) : undefined;
    const hotWindow = body.hotWindow !== undefined ? body.hotWindow : explicitHotStartsAt !== undefined ? null : gameSearch.hotWindow;
    const hotStartTime = body.hotStartTime ?? (gameSearch.hotStartsAt ? gameSearch.hotStartsAt.toISOString().slice(11, 16) : null);
    const hotStartsAt =
      nextSearchType === "hot"
        ? explicitHotStartsAt !== undefined
          ? explicitHotStartsAt
          : hotWindow && hotStartTime
            ? resolveHotSearchStartAt(hotWindow, hotStartTime)
            : gameSearch.hotStartsAt
        : null;
    const preferredDays = resolveSearchDays(nextSearchType, preferredDaysInput, hotWindow ?? undefined, hotStartsAt);

    if (nextSearchType === "hot" && !hotStartsAt) {
      return fail("Не удалось определить время начала горячего поиска");
    }

    if (nextSearchType === "hot" && hotStartsAt && hotStartsAt.getTime() <= Date.now()) {
      return fail("Для горячего поиска выбери время позже текущего");
    }

    const nextSelfLevelUnknown = body.selfLevelUnknown ?? gameSearch.selfLevelUnknown;
    const nextSelfLevel = body.selfLevel ?? gameSearch.selfLevel;
    if (!hasSportProfile && !nextSelfLevelUnknown && nextSelfLevel == null) {
      return fail("Укажи свой уровень по этому виду спорта или выбери «Не знаю»");
    }

    const scheduleRequested =
      body.scheduledAt !== undefined || body.scheduledCourtId !== undefined || body.scheduledDurationMinutes !== undefined;
    const shouldCloseBySchedule = scheduleRequested && Boolean(nextScheduledAt);
    const nextPreferredCourtId = body.preferredCourtId !== undefined ? body.preferredCourtId : gameSearch.preferredCourtId;
    const shouldClearCustomVenue = body.preferredCourtId !== undefined && body.preferredCourtId !== null;
    const customVenueTitle =
      body.customVenueTitle !== undefined ? normalizeOptionalText(body.customVenueTitle) : gameSearch.customVenueTitle;
    const customVenueAddress =
      body.customVenueAddress !== undefined ? normalizeOptionalText(body.customVenueAddress) : gameSearch.customVenueAddress;
    const runningRoute =
      body.runningRoute !== undefined ? normalizeOptionalText(body.runningRoute) : gameSearch.runningRoute;
    const runningRoutePoints =
      body.runningRoutePoints !== undefined
        ? body.runningRoutePoints
        : Array.isArray(gameSearch.runningRoutePoints)
          ? gameSearch.runningRoutePoints
          : null;

    const { updated, confirmedGameRequestId } = await prisma.$transaction(async (tx) => {
      const updated = await tx.gameSearch.update({
        where: { id: gameSearch.id },
        data: {
          ...(body.inviteSlug !== undefined ? { inviteSlug: body.inviteSlug } : {}),
          ...(body.isActive !== undefined
            ? {
                isActive: body.isActive,
                status: body.isActive ? "active" : "closed"
              }
            : {}),
          ...(body.scheduledCourtId !== undefined ? { scheduledCourtId: body.scheduledCourtId } : {}),
          ...(body.scheduledAt !== undefined
            ? {
                scheduledAt: body.scheduledAt ? new Date(body.scheduledAt) : null
              }
            : {}),
          ...(body.scheduledDurationMinutes !== undefined
            ? { scheduledDurationMinutes: body.scheduledDurationMinutes }
            : {}),
          ...(body.preferredCourtId !== undefined ? { preferredCourtId: body.preferredCourtId } : {}),
          ...(body.preferredCourtId !== undefined || body.customVenueTitle !== undefined
            ? { customVenueTitle: shouldClearCustomVenue ? null : customVenueTitle }
            : {}),
          ...(body.preferredCourtId !== undefined || body.customVenueAddress !== undefined
            ? { customVenueAddress: shouldClearCustomVenue ? null : customVenueAddress }
            : {}),
          ...(body.runningRoute !== undefined || body.sport !== undefined ? { runningRoute: isRouteSport(nextSport) ? runningRoute : null } : {}),
          ...(body.runningRoutePoints !== undefined || body.sport !== undefined
            ? {
                runningRoutePoints:
                  isRouteSport(nextSport) && Array.isArray(runningRoutePoints)
                    ? (runningRoutePoints as Prisma.InputJsonValue)
                    : Prisma.JsonNull
              }
            : {}),
          ...(body.preferredDistricts !== undefined ? { preferredDistricts: preferredDistrictsInput } : {}),
          ...(body.preferredDays !== undefined || body.searchType !== undefined || body.hotWindow !== undefined || body.hotStartsAt !== undefined
            ? { preferredDays }
            : {}),
          ...(body.preferredTimeRanges !== undefined ? { preferredTimeRanges: preferredTimeRangesInput } : {}),
          ...(body.searchType !== undefined ? { searchType: nextSearchType } : {}),
          ...(body.hotWindow !== undefined || body.searchType !== undefined || body.hotStartsAt !== undefined
            ? { hotWindow: nextSearchType === "hot" ? hotWindow ?? null : null }
            : {}),
          ...(body.hotWindow !== undefined || body.hotStartTime !== undefined || body.searchType !== undefined || body.hotStartsAt !== undefined
            ? { hotStartsAt }
            : {}),
          ...(body.durationMinutes !== undefined || body.searchType !== undefined
            ? { durationMinutes: nextSearchType === "hot" ? body.durationMinutes ?? gameSearch.durationMinutes ?? null : null }
            : {}),
          ...(body.hasCourtBooked !== undefined ? { hasCourtBooked: body.hasCourtBooked } : {}),
          ...(body.sport !== undefined ? { sport: nextSport } : {}),
          ...(body.selfLevel !== undefined || body.selfLevelUnknown !== undefined || body.sport !== undefined
            ? {
                selfLevel: hasSportProfile ? null : nextSelfLevel ?? null,
                selfLevelUnknown: hasSportProfile ? false : nextSelfLevelUnknown
              }
            : {}),
          ...(body.desiredLevelMin !== undefined ? { desiredLevelMin: body.desiredLevelMin } : {}),
          ...(body.desiredLevelMax !== undefined ? { desiredLevelMax: body.desiredLevelMax } : {}),
          ...(body.format !== undefined ? { format: body.format } : {}),
          ...(body.playersNeeded !== undefined ? { playersNeeded: body.playersNeeded } : {}),
          ...(body.comment !== undefined ? { comment: body.comment } : {}),
          ...(shouldCloseBySchedule
            ? {
                isActive: false,
                status: "matched"
              }
            : {})
        },
        include: {
          preferredCourt: true,
          scheduledCourt: true,
          slotProposals: {
            where: {
              status: "open"
            },
            orderBy: {
              createdAt: "desc"
            },
            take: 1,
            include: {
              options: {
                include: {
                  proposedCourt: true,
                  votes: true
                },
                orderBy: {
                  scheduledAt: "asc"
                }
              }
            }
          },
          regularPair: {
            include: {
              partnerUser: true,
              preferredCourt: true,
              occurrences: {
                include: {
                  proposedCourt: true,
                  confirmations: {
                    include: {
                      user: true
                    }
                  }
                },
                orderBy: {
                  scheduledAt: "asc"
                }
              }
            }
          },
          responses: {
            include: {
              responderUser: true
            }
          }
        }
      });

      let confirmedGameRequestId: string | null = null;
      const playersNeeded = Math.max(updated.playersNeeded ?? 1, 1);
      const approvedResponses = updated.responses.filter((response) => response.status === GameSearchResponseStatus.approved);
      const shouldFinalizeFilledHotSearch =
        !shouldCloseBySchedule &&
        updated.searchType === "hot" &&
        playersNeeded === 1 &&
        approvedResponses.length === 1 &&
        Boolean(updated.hotStartsAt) &&
        (body.playersNeeded !== undefined ||
          body.preferredCourtId !== undefined ||
          body.hotStartsAt !== undefined ||
          body.hotWindow !== undefined ||
          body.hotStartTime !== undefined ||
          body.durationMinutes !== undefined);
      const shouldFinalizeFilledGroupHotSearch =
        !shouldCloseBySchedule &&
        updated.searchType === "hot" &&
        playersNeeded > 1 &&
        approvedResponses.length >= playersNeeded &&
        Boolean(updated.hotStartsAt) &&
        (body.playersNeeded !== undefined ||
          body.preferredCourtId !== undefined ||
          body.hotStartsAt !== undefined ||
          body.hotWindow !== undefined ||
          body.hotStartTime !== undefined ||
          body.durationMinutes !== undefined);

      if (shouldFinalizeFilledGroupHotSearch && updated.hotStartsAt) {
        const proposedCourtId = nextPreferredCourtId ?? updated.preferredCourtId ?? null;
        const scheduledAt = updated.hotStartsAt;
        const scheduleText = `${scheduledAt.toLocaleString("ru-RU", {
          day: "2-digit",
          month: "2-digit",
          hour: "2-digit",
          minute: "2-digit"
        })} · ${updated.format}${updated.durationMinutes ? ` · ${updated.durationMinutes} мин` : ""}`;
        const courtLabel =
          updated.preferredCourt?.name ??
          updated.customVenueAddress ??
          updated.customVenueTitle ??
          updated.runningRoute ??
          "Место уточняется";

        await tx.gameSearchSlotProposal.updateMany({
          where: {
            gameSearchId: updated.id,
            status: "open"
          },
          data: {
            status: "closed"
          }
        });

        await tx.gameSearchResponse.updateMany({
          where: {
            gameSearchId: updated.id,
            status: GameSearchResponseStatus.pending
          },
          data: {
            status: GameSearchResponseStatus.rejected
          }
        });

        await tx.gameSearch.update({
          where: { id: updated.id },
          data: {
            status: GameSearchStatus.matched,
            isActive: false,
            scheduledCourtId: proposedCourtId,
            scheduledAt,
            scheduledDurationMinutes: updated.durationMinutes ?? null
          }
        });

        updated.status = GameSearchStatus.matched;
        updated.isActive = false;
        updated.scheduledCourtId = proposedCourtId;
        updated.scheduledAt = scheduledAt;
        updated.scheduledDurationMinutes = updated.durationMinutes ?? null;

        let rootRequestId: string | null = null;

        for (const approved of approvedResponses) {
          const match = await ensureMatchForUsers(tx, updated.createdByUserId, approved.responderUserId);
          const existingGameRequest = await tx.gameRequest.findFirst({
            where: {
              matchId: match.id,
              createdByUserId: updated.createdByUserId,
              matchedUserId: approved.responderUserId,
              proposedCourtId,
              proposedDatetime: scheduledAt,
              sport: updated.sport,
              format: updated.format,
              status: {
                in: [GameRequestStatus.pending, GameRequestStatus.accepted]
              }
            }
          });

          let gameRequest = existingGameRequest;
          const shouldAnnounceGame = !existingGameRequest || existingGameRequest.status !== GameRequestStatus.accepted;
          if (gameRequest) {
            gameRequest = await tx.gameRequest.update({
              where: { id: gameRequest.id },
              data: {
                status: GameRequestStatus.accepted,
                durationMinutes: updated.durationMinutes ?? 90,
                comment: updated.comment?.trim() || "Игра из поиска подтверждена.",
                sharedRootId: rootRequestId ?? gameRequest.sharedRootId
              }
            });
          } else {
            gameRequest = await tx.gameRequest.create({
              data: {
                matchId: match.id,
                sharedRootId: rootRequestId,
                createdByUserId: updated.createdByUserId,
                matchedUserId: approved.responderUserId,
                proposedCourtId,
                proposedDatetime: scheduledAt,
                durationMinutes: updated.durationMinutes ?? 90,
                sport: updated.sport,
                format: updated.format,
                ...gameRequestRouteData(updated),
                comment: updated.comment?.trim() || "Игра из поиска подтверждена.",
                status: GameRequestStatus.accepted
              }
            });
          }

          if (rootRequestId == null) {
            rootRequestId = gameRequest.id;
            confirmedGameRequestId = gameRequest.id;
          } else if (gameRequest.sharedRootId !== rootRequestId) {
            gameRequest = await tx.gameRequest.update({
              where: { id: gameRequest.id },
              data: { sharedRootId: rootRequestId }
            });
          }

          if (shouldAnnounceGame) {
            await tx.chatMessage.create({
              data: {
                matchId: match.id,
                senderUserId: updated.createdByUserId,
                text: `Игра подтверждена по поиску: ${scheduleText} · ${courtLabel}.`
              }
            });

            await tx.chatMessage.create({
              data: {
                matchId: match.id,
                gameRequestId: gameRequest.id,
                senderUserId: updated.createdByUserId,
                text: "Организатор изменил(а) состав и зафиксировал(а) игру по поиску."
              }
            });

            await tx.match.update({
              where: { id: match.id },
              data: { updatedAt: new Date() }
            });
          }
        }

        await tx.gameSearchMessage.create({
          data: {
            gameSearchId: updated.id,
            senderUserId: updated.createdByUserId,
            text: "Состав собран, игра добавлена в ближайшие."
          }
        });
      }

      if (shouldFinalizeFilledHotSearch && updated.hotStartsAt) {
        const approved = approvedResponses[0];
        const proposedCourtId = nextPreferredCourtId ?? updated.preferredCourtId ?? null;
        const scheduledAt = updated.hotStartsAt;
        const match = await ensureMatchForUsers(tx, updated.createdByUserId, approved.responderUserId);

        await tx.gameSearchSlotProposal.updateMany({
          where: {
            gameSearchId: updated.id,
            status: "open"
          },
          data: {
            status: "closed"
          }
        });

        await tx.gameSearchResponse.updateMany({
          where: {
            gameSearchId: updated.id,
            status: GameSearchResponseStatus.pending
          },
          data: {
            status: GameSearchResponseStatus.rejected
          }
        });

        await tx.gameSearch.update({
          where: { id: updated.id },
          data: {
            status: GameSearchStatus.matched,
            isActive: false,
            scheduledCourtId: proposedCourtId,
            scheduledAt,
            scheduledDurationMinutes: updated.durationMinutes ?? null
          }
        });

        updated.status = GameSearchStatus.matched;
        updated.isActive = false;
        updated.scheduledCourtId = proposedCourtId;
        updated.scheduledAt = scheduledAt;
        updated.scheduledDurationMinutes = updated.durationMinutes ?? null;

        const existingConfirmed = await tx.gameRequest.findFirst({
          where: {
            matchId: match.id,
            status: GameRequestStatus.accepted,
            createdByUserId: updated.createdByUserId,
            matchedUserId: approved.responderUserId,
            proposedCourtId,
            proposedDatetime: scheduledAt
          }
        });

        const gameRequest =
          existingConfirmed ??
          (await tx.gameRequest.create({
            data: {
              matchId: match.id,
              createdByUserId: updated.createdByUserId,
              matchedUserId: approved.responderUserId,
              proposedCourtId,
              proposedDatetime: scheduledAt,
              durationMinutes: updated.durationMinutes ?? 90,
              sport: updated.sport,
              format: updated.format,
              ...gameRequestRouteData(updated),
              comment: updated.comment?.trim() || "Игра из поиска подтверждена.",
              status: GameRequestStatus.accepted
            }
          }));

        confirmedGameRequestId = gameRequest.id;

        if (!existingConfirmed) {
          const scheduleText = `${scheduledAt.toLocaleString("ru-RU", {
            day: "2-digit",
            month: "2-digit",
            hour: "2-digit",
            minute: "2-digit"
          })} · ${updated.format}${updated.durationMinutes ? ` · ${updated.durationMinutes} мин` : ""}`;
          const courtLabel =
            updated.preferredCourt?.name ??
            updated.customVenueAddress ??
            updated.customVenueTitle ??
            updated.runningRoute ??
            "Место уточняется";

          await tx.chatMessage.create({
            data: {
              matchId: match.id,
              senderUserId: updated.createdByUserId,
              text: `Игра подтверждена по поиску: ${scheduleText} · ${courtLabel}.`
            }
          });

          await tx.chatMessage.create({
            data: {
              matchId: match.id,
              gameRequestId: gameRequest.id,
              senderUserId: updated.createdByUserId,
              text: "Организатор изменил(а) состав и зафиксировал(а) игру по поиску."
            }
          });

          await tx.gameSearchMessage.create({
            data: {
              gameSearchId: updated.id,
              senderUserId: updated.createdByUserId,
              text: `${approved.responderUser.name ?? "Игрок"} подтвержден(а). Состав собран, игра добавлена в ближайшие.`
            }
          });

          await tx.match.update({
            where: { id: match.id },
            data: { updatedAt: new Date() }
          });
        }
      }

      if (shouldCloseBySchedule && nextScheduledAt) {
        await tx.gameSearchSlotProposal.updateMany({
          where: {
            gameSearchId: updated.id,
            status: "open"
          },
          data: {
            status: "closed"
          }
        });

        await tx.gameSearchResponse.updateMany({
          where: {
            gameSearchId: updated.id,
            status: GameSearchResponseStatus.pending
          },
          data: {
            status: GameSearchResponseStatus.rejected
          }
        });

        if (approvedResponses.length > 0) {
          const proposedCourtId = updated.scheduledCourtId ?? updated.preferredCourtId ?? null;

          {
            const scheduleText = `${nextScheduledAt.toLocaleString("ru-RU", {
              day: "2-digit",
              month: "2-digit",
              hour: "2-digit",
              minute: "2-digit"
            })} · ${updated.format}${updated.scheduledDurationMinutes ? ` · ${updated.scheduledDurationMinutes} мин` : ""}`;
            const courtLabel =
              updated.scheduledCourt?.name ??
              updated.preferredCourt?.name ??
              updated.customVenueAddress ??
              updated.customVenueTitle ??
              updated.runningRoute ??
              "Место уточняется";

            if (playersNeeded === 1 && approvedResponses.length === 1) {
              const approved = approvedResponses[0];
              const match = await ensureMatchForUsers(tx, updated.createdByUserId, approved.responderUserId);

              const scheduleChanged =
                Boolean(gameSearch.scheduledAt) &&
                (gameSearch.scheduledAt?.getTime() !== nextScheduledAt.getTime() ||
                  (gameSearch.scheduledCourtId ?? gameSearch.preferredCourtId ?? null) !== proposedCourtId);

              if (scheduleChanged) {
                const previousProposedCourtId = gameSearch.scheduledCourtId ?? gameSearch.preferredCourtId ?? null;
                if (gameSearch.scheduledAt) {
                  await tx.gameRequest.updateMany({
                    where: {
                      matchId: match.id,
                      status: GameRequestStatus.accepted,
                      createdByUserId: updated.createdByUserId,
                      matchedUserId: approved.responderUserId,
                      proposedCourtId: previousProposedCourtId,
                      proposedDatetime: gameSearch.scheduledAt
                    },
                    data: {
                      status: GameRequestStatus.canceled
                    }
                  });
                }
              }

              const existingConfirmed = await tx.gameRequest.findFirst({
                where: {
                  matchId: match.id,
                  status: GameRequestStatus.accepted,
                  createdByUserId: updated.createdByUserId,
                  matchedUserId: approved.responderUserId,
                  proposedCourtId,
                  proposedDatetime: nextScheduledAt
                }
              });

              const gameRequest =
                existingConfirmed ??
                (await tx.gameRequest.create({
                  data: {
                    matchId: match.id,
                    createdByUserId: updated.createdByUserId,
                    matchedUserId: approved.responderUserId,
                    proposedCourtId,
                    proposedDatetime: nextScheduledAt,
                    durationMinutes: updated.scheduledDurationMinutes ?? 90,
                    sport: updated.sport,
                    format: updated.format,
                    ...gameRequestRouteData(updated),
                    comment: updated.comment?.trim() || "Игра из поиска подтверждена.",
                    status: GameRequestStatus.accepted
                  },
                  include: {
                    proposedCourt: true
                  }
                }));

              confirmedGameRequestId = gameRequest.id;

              if (!existingConfirmed) {
                await tx.chatMessage.create({
                  data: {
                    matchId: match.id,
                    senderUserId: updated.createdByUserId,
                    text: `Игра подтверждена по поиску: ${scheduleText} · ${courtLabel}.`
                  }
                });

                await tx.chatMessage.create({
                  data: {
                    matchId: match.id,
                    gameRequestId: gameRequest.id,
                    senderUserId: updated.createdByUserId,
                    text: "Организатор зафиксировал(а) игру и подтвердил(а) состав. Здесь можно обсудить только детали этой договоренности."
                  }
                });

                await tx.match.update({
                  where: { id: match.id },
                  data: { updatedAt: new Date() }
                });
              }
            } else {
              const approvedWithMatches = [];

              for (const approved of approvedResponses) {
                const match = await ensureMatchForUsers(tx, updated.createdByUserId, approved.responderUserId);
                approvedWithMatches.push({ approved, match });
              }

              let rootRequestId: string | null = null;

              for (const entry of approvedWithMatches) {
                const existingPending = await tx.gameRequest.findFirst({
                  where: {
                    matchId: entry.match.id,
                    createdByUserId: updated.createdByUserId,
                    matchedUserId: entry.approved.responderUserId,
                    proposedCourtId,
                    proposedDatetime: nextScheduledAt,
                    sport: updated.sport,
                    format: updated.format,
                    status: {
                      in: [GameRequestStatus.pending, GameRequestStatus.accepted]
                    }
                  }
                });

                let scheduledRequest = existingPending;
                if (scheduledRequest && scheduledRequest.status !== GameRequestStatus.accepted) {
                  scheduledRequest = await tx.gameRequest.update({
                    where: { id: scheduledRequest.id },
                    data: {
                      status: GameRequestStatus.accepted,
                      durationMinutes: updated.scheduledDurationMinutes ?? 90,
                      comment: updated.comment?.trim() || "Игра из поиска подтверждена.",
                      sharedRootId: rootRequestId ?? scheduledRequest.sharedRootId
                    }
                  });
                }

                if (!scheduledRequest) {
                  scheduledRequest = await tx.gameRequest.create({
                    data: {
                      matchId: entry.match.id,
                      sharedRootId: rootRequestId,
                      createdByUserId: updated.createdByUserId,
                      matchedUserId: entry.approved.responderUserId,
                      proposedCourtId,
                      proposedDatetime: nextScheduledAt,
                      durationMinutes: updated.scheduledDurationMinutes ?? 90,
                      sport: updated.sport,
                      format: updated.format,
                      ...gameRequestRouteData(updated),
                      comment: updated.comment?.trim() || "Игра из поиска подтверждена.",
                      status: GameRequestStatus.accepted
                    }
                  });
                }

                if (rootRequestId == null) {
                  rootRequestId = scheduledRequest.id;
                  if (scheduledRequest.sharedRootId == null) {
                    await tx.gameRequest.update({
                      where: { id: scheduledRequest.id },
                      data: { sharedRootId: null }
                    });
                  }
                  confirmedGameRequestId = scheduledRequest.id;
                } else if (scheduledRequest.sharedRootId !== rootRequestId) {
                  scheduledRequest = await tx.gameRequest.update({
                    where: { id: scheduledRequest.id },
                    data: { sharedRootId: rootRequestId }
                  });
                }

                if (!existingPending) {
                  await tx.chatMessage.create({
                    data: {
                      matchId: entry.match.id,
                      senderUserId: updated.createdByUserId,
                      text: `Игра подтверждена по поиску: ${scheduleText} · ${courtLabel}.`
                    }
                  });

                  await tx.chatMessage.create({
                    data: {
                      matchId: entry.match.id,
                      gameRequestId: scheduledRequest.id,
                      senderUserId: updated.createdByUserId,
                      text: "Организатор зафиксировал(а) игру и подтвердил(а) состав. Игра добавлена в ближайшие."
                    }
                  });

                  await tx.match.update({
                    where: { id: entry.match.id },
                    data: { updatedAt: new Date() }
                  });
                }
              }

              await tx.gameSearchMessage.create({
                data: {
                  gameSearchId: updated.id,
                  senderUserId: updated.createdByUserId,
                  text: `Организатор зафиксировал(а) игру: ${scheduleText} · ${courtLabel}. Состав подтвержден.`
                }
              });
            }
          }
        }
      }

      return { updated, confirmedGameRequestId };
    });

    if (updated.regularPair?.id) {
      await syncRegularPairOccurrences(prisma, updated.regularPair.id);
    }

    return ok({
      gameSearch: {
        ...updated,
        preferredDistricts: stringArray(updated.preferredDistricts),
        preferredDays: stringArray(updated.preferredDays),
        preferredTimeRanges: stringArray(updated.preferredTimeRanges),
        createdAt: updated.createdAt.toISOString(),
        updatedAt: updated.updatedAt.toISOString(),
        hotStartsAt: updated.hotStartsAt?.toISOString() ?? null,
        scheduledAt: updated.scheduledAt?.toISOString() ?? null
      },
      gameRequestId: confirmedGameRequestId
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();

    const gameSearch = await prisma.gameSearch.findFirst({
      where: {
        id: params.id,
        OR: [
          { createdByUserId: user.id },
          {
            responses: {
              some: {
                responderUserId: user.id,
              status: GameSearchResponseStatus.approved
              }
            }
          }
        ]
      },
      include: {
        preferredCourt: true,
        scheduledCourt: true,
        slotProposals: {
          where: {
            status: "open"
          },
          orderBy: {
            createdAt: "desc"
          },
          take: 1,
          include: {
            options: {
              include: {
                proposedCourt: true,
                votes: true
              },
              orderBy: {
                scheduledAt: "asc"
              }
            }
          }
        },
        createdByUser: true,
        messages: {
          include: {
            senderUser: true
          },
          orderBy: {
            createdAt: "asc"
          }
        },
        responses: {
          include: {
            responderUser: true
          },
          orderBy: [
            { status: "asc" },
            { createdAt: "asc" }
          ]
        }
      }
    });

    if (!gameSearch) {
      return fail("Поиск игры не найден", 404);
    }

    return ok({
      gameSearch: {
        ...gameSearch,
        preferredDistricts: stringArray(gameSearch.preferredDistricts),
        preferredDays: stringArray(gameSearch.preferredDays),
        preferredTimeRanges: stringArray(gameSearch.preferredTimeRanges),
        activeSlotProposal: gameSearch.slotProposals[0] ?? null,
        createdAt: gameSearch.createdAt.toISOString(),
        updatedAt: gameSearch.updatedAt.toISOString(),
        hotStartsAt: gameSearch.hotStartsAt?.toISOString() ?? null,
        scheduledAt: gameSearch.scheduledAt?.toISOString() ?? null
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function normalizeOptionalText(value: string | null | undefined) {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}
