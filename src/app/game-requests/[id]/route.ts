import { recordGameRequestMilestones } from "@/server/user-events";
import { NextRequest } from "next/server";
import { GameRequestOutcome, GameRequestStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { SPORT_LABELS } from "@/lib/constants";
import { isFormatAllowedForSport } from "@/lib/sport-playbook";
import { updateGameRequestSchema } from "@/lib/validators";
import { ensureGroupSearchLobby } from "@/server/game-request-lobbies";
import { canTransitionGameRequest, canUpdateGameRequestOutcome } from "@/server/matching";
import { publishRealtimeEventToUsers } from "@/server/realtime";
import { serializeGameRequest } from "@/server/serializers";
import { assertActiveCourtIds } from "@/server/court-status";

const gameRequestInclude = {
  proposedCourt: true,
  report: {
    include: {
      createdByUser: true,
      photos: {
        orderBy: {
          position: "asc" as const
        }
      },
      confirmations: {
        include: {
          user: true
        }
      }
    }
  }
};

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = updateGameRequestSchema.parse(await request.json());
    const gameRequest = await prisma.gameRequest.findUnique({
      where: { id: params.id }
    });

    if (!gameRequest) {
      return fail("Предложение игры не найдено", 404);
    }

    const isCreator = gameRequest.createdByUserId === user.id;
    const isRecipient = gameRequest.matchedUserId === user.id;

    if (!isCreator && !isRecipient) {
      return fail("Нет доступа", 403);
    }

    const editableRequested =
      body.proposedCourtId !== undefined ||
      body.proposedDatetime !== undefined ||
      body.durationMinutes !== undefined ||
      body.levelRangeMin !== undefined ||
      body.levelRangeMax !== undefined ||
      body.sport !== undefined ||
      body.format !== undefined ||
      body.comment !== undefined;

    const statusRequested = body.status !== undefined;
    const outcomeRequested = body.outcome !== undefined;
    const nextStatus = body.status;
    const nextOutcome = body.outcome;
    const effectiveSport = body.sport ?? gameRequest.sport;
    const effectiveFormat = body.format ?? gameRequest.format;
    const statusNoOp = statusRequested && body.status === gameRequest.status;
    const outcomeNoOp = outcomeRequested && body.outcome === gameRequest.outcome;
    const editableNoOp =
      editableRequested &&
      (body.proposedCourtId === undefined || body.proposedCourtId === gameRequest.proposedCourtId) &&
      (body.proposedDatetime === undefined || new Date(body.proposedDatetime).getTime() === gameRequest.proposedDatetime.getTime()) &&
      (body.durationMinutes === undefined || (body.durationMinutes ?? null) === (gameRequest.durationMinutes ?? null)) &&
      (body.levelRangeMin === undefined || (body.levelRangeMin ?? null) === (gameRequest.levelRangeMin ?? null)) &&
      (body.levelRangeMax === undefined || (body.levelRangeMax ?? null) === (gameRequest.levelRangeMax ?? null)) &&
      (body.sport === undefined || body.sport === gameRequest.sport) &&
      (body.format === undefined || body.format === gameRequest.format) &&
      (body.comment === undefined || body.comment === (gameRequest.comment ?? ""));
    const editableChanged = editableRequested && !editableNoOp;

    if (
      (!editableRequested && statusRequested && !outcomeRequested && statusNoOp) ||
      (!editableRequested && !statusRequested && outcomeRequested && outcomeNoOp) ||
      (!editableRequested && statusRequested && outcomeRequested && statusNoOp && outcomeNoOp) ||
      (editableRequested && !statusRequested && !outcomeRequested && editableNoOp) ||
      (editableRequested && statusRequested && !outcomeRequested && editableNoOp && statusNoOp) ||
      (editableRequested && !statusRequested && outcomeRequested && editableNoOp && outcomeNoOp) ||
      (editableRequested && statusRequested && outcomeRequested && editableNoOp && statusNoOp && outcomeNoOp)
    ) {
      const existing = await prisma.gameRequest.findUnique({
        where: { id: params.id },
        include: gameRequestInclude
      });

      if (!existing) {
        return fail("Предложение игры не найдено", 404);
      }

      return ok({
        gameRequest: serializeGameRequest(existing)
      });
    }

    if (statusRequested && !statusNoOp) {
      if (nextStatus === undefined) {
        return fail("Некорректный запрос");
      }

      if (
        (nextStatus === GameRequestStatus.accepted || nextStatus === GameRequestStatus.declined) &&
        !isRecipient
      ) {
        return fail("Подтвердить или отклонить предложение может только получатель", 403);
      }

      if (nextStatus === GameRequestStatus.canceled && !isCreator && !isRecipient) {
        return fail("Отменить предложение могут только участники мэтча", 403);
      }

      if (!canTransitionGameRequest(gameRequest.status, nextStatus)) {
        return fail("Некорректная смена статуса");
      }
    }

    if (editableRequested) {
      if (
        gameRequest.status === GameRequestStatus.canceled ||
        gameRequest.status === GameRequestStatus.declined
      ) {
        return fail("Неактивное предложение нельзя изменить");
      }

      if (!isFormatAllowedForSport(effectiveSport, effectiveFormat)) {
        return fail("Этот формат недоступен для выбранного вида спорта");
      }
    }

    if (outcomeRequested && !outcomeNoOp) {
      if (!canUpdateGameRequestOutcome(gameRequest.status)) {
        return fail("Результат можно отметить только у принятой игры");
      }

      if (!isCreator && !isRecipient) {
        return fail("Нет доступа", 403);
      }
    }

    const notificationTargets: Array<{ requestId: string; recipientUserId: string; matchId?: string }> = [];
    let touchedSearchLobbyId: string | null = null;
    let searchLobbyRealtimeUserIds: string[] = [];

    const updated = await prisma.$transaction(async (tx) => {
      if (body.proposedCourtId !== undefined && body.proposedCourtId !== gameRequest.proposedCourtId) {
        await assertActiveCourtIds(tx, [body.proposedCourtId]);
      }
      const shouldCascadeGroupCancellation =
        statusRequested &&
        !statusNoOp &&
        nextStatus === GameRequestStatus.canceled;
      const shouldCascadeGroupEdit = editableChanged && isCreator;

      const rootRequestId = gameRequest.sharedRootId ?? gameRequest.id;
      const relatedRequests = shouldCascadeGroupCancellation || shouldCascadeGroupEdit
        ? await tx.gameRequest.findMany({
            where: {
              OR: [{ id: rootRequestId }, { sharedRootId: rootRequestId }]
            },
            include: {
              ...gameRequestInclude
            }
          })
        : [];
      const cascadeRequests = relatedRequests.length > 1 ? relatedRequests : [];
      const resolvedNextStatus =
        statusRequested && !statusNoOp && nextStatus !== undefined
          ? nextStatus
          : editableChanged
            ? GameRequestStatus.pending
          : undefined;
      const nextConfirmationRecipientId =
        editableChanged && gameRequest.createdByUserId !== user.id
          ? gameRequest.createdByUserId
          : gameRequest.matchedUserId;
      let preferredExistingLobbyId: string | null = null;

      let result: typeof relatedRequests[number] | (typeof gameRequest & { proposedCourt?: null });

      if (cascadeRequests.length > 0 && shouldCascadeGroupCancellation) {
        const activeRequestIds = cascadeRequests
          .filter((requestItem) => requestItem.status !== GameRequestStatus.canceled)
          .map((requestItem) => requestItem.id);

        if (activeRequestIds.length > 0) {
          await tx.gameRequest.updateMany({
            where: {
              id: {
                in: activeRequestIds
              }
            },
            data: {
              status: GameRequestStatus.canceled
            }
          });
        }

        const statusMessage = getStatusChangeMessage(GameRequestStatus.canceled, { isGrouped: true });
        if (statusMessage) {
          await tx.chatMessage.createMany({
            data: cascadeRequests.flatMap((requestItem) => [
              {
                matchId: requestItem.matchId,
                gameRequestId: null,
                senderUserId: user.id,
                text: statusMessage
              },
              {
                matchId: requestItem.matchId,
                gameRequestId: requestItem.id,
                senderUserId: user.id,
                text: statusMessage
              }
            ])
          });
        }

        const touchedMatchIds = Array.from(new Set(cascadeRequests.map((requestItem) => requestItem.matchId)));
        await Promise.all(
          touchedMatchIds.map((matchId) =>
            tx.match.update({
              where: { id: matchId },
              data: { updatedAt: new Date() }
            })
          )
        );

        for (const requestItem of cascadeRequests) {
          const recipientUserId = requestItem.createdByUserId === user.id ? requestItem.matchedUserId : requestItem.createdByUserId;
          if (recipientUserId && recipientUserId !== user.id) {
            notificationTargets.push({
              requestId: requestItem.id,
              recipientUserId,
              matchId: requestItem.matchId
            });
          }
        }

        const refreshed = await tx.gameRequest.findUnique({
          where: { id: params.id },
          include: gameRequestInclude
        });

        if (!refreshed) {
          throw new Error("Предложение игры не найдено");
        }

        result = refreshed;
      } else if (cascadeRequests.length > 0 && shouldCascadeGroupEdit) {
        const activeRequests = cascadeRequests.filter(
          (requestItem) =>
            requestItem.status !== GameRequestStatus.canceled &&
            requestItem.status !== GameRequestStatus.declined
        );
        const activeRequestIds = activeRequests.map((requestItem) => requestItem.id);
        const primaryGroupRequest = cascadeRequests.find((requestItem) => !requestItem.sharedRootId) ?? cascadeRequests[0];
        const existingLobby = primaryGroupRequest
          ? await tx.gameSearch.findFirst({
              where: {
                createdByUserId: primaryGroupRequest.createdByUserId,
                scheduledAt: primaryGroupRequest.proposedDatetime,
                scheduledCourtId: primaryGroupRequest.proposedCourtId,
                sport: primaryGroupRequest.sport,
                format: primaryGroupRequest.format,
                playersNeeded: {
                  gt: 1
                }
              },
              select: {
                id: true
              },
              orderBy: {
                updatedAt: "desc"
              }
            })
          : null;
        preferredExistingLobbyId = existingLobby?.id ?? null;

        if (activeRequestIds.length > 0) {
          await tx.gameRequest.updateMany({
            where: {
              id: {
                in: activeRequestIds
              }
            },
            data: {
              status: GameRequestStatus.pending,
              proposedCourtId: body.proposedCourtId !== undefined ? body.proposedCourtId : gameRequest.proposedCourtId,
              proposedDatetime: body.proposedDatetime ? new Date(body.proposedDatetime) : gameRequest.proposedDatetime,
              durationMinutes: body.durationMinutes !== undefined ? body.durationMinutes : gameRequest.durationMinutes,
              levelRangeMin: body.levelRangeMin !== undefined ? body.levelRangeMin : gameRequest.levelRangeMin,
              levelRangeMax: body.levelRangeMax !== undefined ? body.levelRangeMax : gameRequest.levelRangeMax,
              sport: effectiveSport,
              format: effectiveFormat,
              comment: body.comment !== undefined ? body.comment : (gameRequest.comment ?? ""),
              createdByUserId: user.id,
              outcome: null,
              outcomeUpdatedAt: null
            }
          });
        }

        const refreshed = await tx.gameRequest.findUnique({
          where: { id: params.id },
          include: gameRequestInclude
        });

        if (!refreshed) {
          throw new Error("Предложение игры не найдено");
        }

        const touchedMatchIds = Array.from(new Set(activeRequests.map((requestItem) => requestItem.matchId)));
        if (touchedMatchIds.length > 0) {
          await Promise.all(
            touchedMatchIds.map((matchId) =>
              tx.match.update({
                where: { id: matchId },
                data: { updatedAt: new Date() }
              })
            )
          );
        }

        const nextForMessages = {
          proposedCourtId: refreshed.proposedCourtId,
          proposedDatetime: refreshed.proposedDatetime,
          durationMinutes: refreshed.durationMinutes,
          sport: refreshed.sport,
          format: refreshed.format,
          proposedCourt: refreshed.proposedCourt
        };

        if (activeRequests.length > 0) {
          await tx.chatMessage.createMany({
            data: activeRequests.flatMap((requestItem) => {
              const editMessage = getEditChangeMessage(requestItem, nextForMessages, {
                resetConfirmation: true
              });

              return [
                {
                  matchId: requestItem.matchId,
                  gameRequestId: null,
                  senderUserId: user.id,
                  text: editMessage
                },
                {
                  matchId: requestItem.matchId,
                  gameRequestId: requestItem.id,
                  senderUserId: user.id,
                  text: editMessage
                }
              ];
            })
          });
        }

        for (const requestItem of activeRequests) {
          if (requestItem.matchedUserId && requestItem.matchedUserId !== user.id) {
            notificationTargets.push({
              requestId: requestItem.id,
              recipientUserId: requestItem.matchedUserId,
              matchId: requestItem.matchId
            });
          }
        }

        result = refreshed;
      } else {
        result = await tx.gameRequest.update({
          where: { id: params.id },
          data: {
            ...(resolvedNextStatus !== undefined ? { status: resolvedNextStatus } : {}),
            ...(outcomeRequested && !outcomeNoOp && nextOutcome !== undefined
              ? {
                  outcome: nextOutcome as GameRequestOutcome | null,
                  outcomeUpdatedAt: nextOutcome ? new Date() : null
                }
              : {}),
            ...(editableRequested && !editableNoOp
              ? {
                  proposedCourtId: body.proposedCourtId !== undefined ? body.proposedCourtId : gameRequest.proposedCourtId,
                  proposedDatetime: body.proposedDatetime ? new Date(body.proposedDatetime) : gameRequest.proposedDatetime,
                  durationMinutes: body.durationMinutes !== undefined ? body.durationMinutes : gameRequest.durationMinutes,
                  levelRangeMin: body.levelRangeMin !== undefined ? body.levelRangeMin : gameRequest.levelRangeMin,
                  levelRangeMax: body.levelRangeMax !== undefined ? body.levelRangeMax : gameRequest.levelRangeMax,
                  sport: effectiveSport,
                  format: effectiveFormat,
                  comment: body.comment !== undefined ? body.comment : (gameRequest.comment ?? ""),
                  createdByUserId: user.id,
                  matchedUserId: nextConfirmationRecipientId,
                  outcome: null,
                  outcomeUpdatedAt: null
                }
              : {})
          },
          include: {
            ...gameRequestInclude
          }
        });

        if (resolvedNextStatus !== undefined) {
          const statusMessage = getStatusChangeMessage(resolvedNextStatus);

          if (statusMessage) {
            await tx.chatMessage.createMany({
              data: [
                {
                  matchId: gameRequest.matchId,
                  gameRequestId: null,
                  senderUserId: user.id,
                  text: statusMessage
                },
                {
                  matchId: gameRequest.matchId,
                  gameRequestId: gameRequest.id,
                  senderUserId: user.id,
                  text: statusMessage
                }
              ]
            });
          }
        }

        if (editableRequested && !editableNoOp) {
          const editMessage = getEditChangeMessage(gameRequest, result, {
            resetConfirmation: true
          });

          await tx.chatMessage.createMany({
            data: [
              {
                matchId: gameRequest.matchId,
                gameRequestId: null,
                senderUserId: user.id,
                text: editMessage
              },
              {
                matchId: gameRequest.matchId,
                gameRequestId: gameRequest.id,
                senderUserId: user.id,
                text: editMessage
              }
            ]
          });
        }
      }

      if (outcomeRequested && !outcomeNoOp && nextOutcome !== undefined) {
        const outcomeMessage = getOutcomeChangeMessage(nextOutcome as GameRequestOutcome | null);

        if (outcomeMessage) {
          await tx.chatMessage.create({
            data: {
              matchId: gameRequest.matchId,
              gameRequestId: gameRequest.id,
              senderUserId: user.id,
              text: outcomeMessage
            }
          });
        }
      }

      if (body.status === GameRequestStatus.accepted && statusRequested && !statusNoOp) {
        const rootId = gameRequest.sharedRootId ?? gameRequest.id;
        const acceptedGroupRequests = await tx.gameRequest.findMany({
          where: {
            OR: [{ id: rootId }, { sharedRootId: rootId }]
          },
          select: {
            id: true
          }
        });
        const isGroupedAcceptance = acceptedGroupRequests.length > 1;

        if (!isGroupedAcceptance && (gameRequest.format === "singles" || gameRequest.format === "both")) {
          if (gameRequest.sharedRootId) {
            await tx.gameRequest.update({
              where: { id: rootId },
              data: {
                matchId: gameRequest.matchId,
                matchedUserId: gameRequest.matchedUserId,
                proposedCourtId: gameRequest.proposedCourtId,
                proposedDatetime: gameRequest.proposedDatetime,
                durationMinutes: gameRequest.durationMinutes,
                levelRangeMin: gameRequest.levelRangeMin,
                levelRangeMax: gameRequest.levelRangeMax,
                sport: gameRequest.sport,
                format: gameRequest.format,
                comment: gameRequest.comment,
                status: GameRequestStatus.accepted,
                outcome: gameRequest.outcome,
                outcomeUpdatedAt: gameRequest.outcomeUpdatedAt
              }
            });
          }

          await tx.gameRequest.updateMany({
            where: {
              OR: [{ id: rootId }, { sharedRootId: rootId }],
              id: {
                not: gameRequest.id
              },
              status: GameRequestStatus.pending
            },
            data: {
              status: GameRequestStatus.canceled
            }
          });
        }
      }

      if (cascadeRequests.length === 0) {
        await tx.match.update({
          where: { id: gameRequest.matchId },
          data: { updatedAt: new Date() }
        });
      }

      if (resolvedNextStatus !== undefined || (editableRequested && !editableNoOp)) {
        const rootRequestId = gameRequest.sharedRootId ?? gameRequest.id;
        const groupRequests = await tx.gameRequest.findMany({
          where: {
            OR: [{ id: rootRequestId }, { sharedRootId: rootRequestId }]
          }
        });

        if (groupRequests.length > 1) {
          const lobbyId = await ensureGroupSearchLobby(tx, groupRequests, {
            senderUserId: user.id,
            createIntroMessage: true,
            existingLobbyId: preferredExistingLobbyId
          });
          if (lobbyId) {
            touchedSearchLobbyId = lobbyId;
            searchLobbyRealtimeUserIds = Array.from(
              new Set(
                groupRequests
                  .flatMap((requestItem) => [requestItem.createdByUserId, requestItem.matchedUserId])
                  .filter((userId): userId is string => Boolean(userId))
              )
            );

            if (editableRequested && !editableNoOp) {
              await tx.gameSearchMessage.create({
                data: {
                  gameSearchId: lobbyId,
                  senderUserId: user.id,
                  text: getEditChangeMessage(gameRequest, result, {
                    resetConfirmation: true
                  })
                }
              });
            }
          }
        }
      }

      return result;
    });

    if (updated.status === GameRequestStatus.accepted && gameRequest.status !== GameRequestStatus.accepted) {
      await recordGameRequestMilestones([updated.id], "request_accepted", "proposal");
    }
    if (updated.outcome === GameRequestOutcome.played && gameRequest.outcome !== GameRequestOutcome.played) {
      await recordGameRequestMilestones([updated.id], "game_played", "outcome");
    }
    if (notificationTargets.length === 0) {
      const recipientUserId = isCreator ? gameRequest.matchedUserId : gameRequest.createdByUserId;
      if (recipientUserId && ((statusRequested && !statusNoOp) || (outcomeRequested && !outcomeNoOp) || (editableRequested && !editableNoOp))) {
        notificationTargets.push({
          requestId: gameRequest.id,
          recipientUserId,
          matchId: gameRequest.matchId
        });
      }
    }

    if ((statusRequested && !statusNoOp) || (outcomeRequested && !outcomeNoOp) || (editableRequested && !editableNoOp)) {
      const realtimeTargets = notificationTargets.length > 0
        ? notificationTargets
        : [{ requestId: updated.id, recipientUserId: user.id, matchId: updated.matchId }];
      const publishedRealtimeKeys = new Set<string>();

      await Promise.all(
        realtimeTargets.map(async (target) => {
          const key = `${target.requestId}:${target.recipientUserId}`;
          if (publishedRealtimeKeys.has(key)) {
            return;
          }
          publishedRealtimeKeys.add(key);

          await publishRealtimeEventToUsers([user.id, target.recipientUserId], {
            type: "game_request_updated",
            matchId: target.matchId ?? updated.matchId,
            gameRequestId: target.requestId,
            status: updated.status,
            href: `/play/games/${target.requestId}`
          });
        })
      );

      const recipients = await prisma.user.findMany({
        where: {
          id: {
            in: Array.from(new Set(notificationTargets.map((target) => target.recipientUserId)))
          }
        },
        select: {
          id: true,
          notificationGames: true,
          notificationSound: true
        }
      });
      const recipientsById = new Map(recipients.map((recipient) => [recipient.id, recipient]));
      const pushBody =
        body.outcome !== undefined
          ? getOutcomeChangeMessage(body.outcome) ?? "Есть обновление по вашей игре."
          : editableRequested && !editableNoOp
            ? getEditChangeMessage(gameRequest, updated, {
                resetConfirmation: true
              })
          : body.status !== undefined
            ? getStatusChangeMessage(body.status, {
                isGrouped: notificationTargets.length > 1 || gameRequest.sharedRootId != null
              }) ?? "Есть обновление по вашей игре."
            : "Есть обновление по вашей игре.";

      await Promise.all(
        notificationTargets.map(async (target) => {
          const recipient = recipientsById.get(target.recipientUserId);
          if (!recipient?.notificationGames) {
            return;
          }

          await sendPushToUser({
            userId: recipient.id,
            title: `Обновление по игре от ${user.name ?? "игрока"}`,
            body: pushBody,
            href: `/play/games/${target.requestId}`,
            sound: recipient.notificationSound ?? true
          });
        })
      );
    }

    if (touchedSearchLobbyId) {
      await publishRealtimeEventToUsers(searchLobbyRealtimeUserIds, {
        type: "game_request_updated",
        searchId: touchedSearchLobbyId,
        gameRequestId: updated.id,
        status: updated.status,
        href: `/play/searches/${touchedSearchLobbyId}`
      });
    }

    return ok({
      gameRequest: serializeGameRequest(updated)
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

function getStatusChangeMessage(status: GameRequestStatus, options: { isGrouped?: boolean } = {}) {
  switch (status) {
    case GameRequestStatus.accepted:
      return "Игра подтверждена. Дальше обсуждаем только эту договоренность в отдельном чате игры.";
    case GameRequestStatus.declined:
      return "Предложение игры отклонено.";
    case GameRequestStatus.canceled:
      return options.isGrouped
        ? "Групповая игра отменена. Весь состав сразу видит обновление статуса."
        : "Игра отменена. Оба участника видят обновление статуса.";
    default:
      return null;
  }
}

function getOutcomeChangeMessage(outcome: GameRequestOutcome | null) {
  switch (outcome) {
    case GameRequestOutcome.played:
      return "Отметили, что игра состоялась.";
    case GameRequestOutcome.not_played:
      return "Отметили, что сыграть не удалось.";
    default:
      return null;
  }
}

function getEditChangeMessage(
  previous: {
    proposedCourtId: string | null;
    proposedDatetime: Date;
    durationMinutes: number | null;
    sport: keyof typeof SPORT_LABELS;
    format: string;
  },
  next: {
    proposedCourtId: string | null;
    proposedDatetime: Date;
    durationMinutes: number | null;
    sport: keyof typeof SPORT_LABELS;
    format: string;
    proposedCourt?: { name: string } | null;
  },
  options: { resetConfirmation?: boolean } = {}
) {
  const changes: string[] = [];

  if ((previous.proposedCourtId ?? null) !== (next.proposedCourtId ?? null)) {
    changes.push(`Изменился клуб: ${next.proposedCourt?.name ?? "место уточняется"}`);
  }

  if (previous.proposedDatetime.getTime() !== next.proposedDatetime.getTime()) {
    changes.push(`Изменилась дата и время: ${next.proposedDatetime.toLocaleString("ru-RU")}`);
  }

  if (previous.sport !== next.sport) {
    changes.push(`Изменился вид спорта: ${SPORT_LABELS[next.sport] ?? next.sport}`);
  }

  if (previous.format !== next.format) {
    changes.push(`Изменился формат: ${next.format}`);
  }

  if ((previous.durationMinutes ?? null) !== (next.durationMinutes ?? null)) {
    changes.push(`Изменилась длительность: ${next.durationMinutes ? `${next.durationMinutes} мин` : "не указана"}`);
  }

  if (changes.length === 0) {
    changes.push("Предложение игры обновлено");
  }

  const confirmationLabel = options.resetConfirmation ? " Подтверждение нужно заново." : "";
  return `${changes.join(". ")}.${confirmationLabel}`.trim();
}
