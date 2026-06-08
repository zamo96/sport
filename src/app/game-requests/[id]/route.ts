import { NextRequest } from "next/server";
import { GameRequestOutcome, GameRequestStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { isFormatAllowedForSport } from "@/lib/sport-playbook";
import { updateGameRequestSchema } from "@/lib/validators";
import { ensureGroupSearchLobby } from "@/server/game-request-lobbies";
import { canTransitionGameRequest, canUpdateGameRequestOutcome } from "@/server/matching";
import { serializeGameRequest } from "@/server/serializers";

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
        include: { proposedCourt: true }
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

    const notificationTargets: Array<{ requestId: string; recipientUserId: string }> = [];

    const updated = await prisma.$transaction(async (tx) => {
      const shouldCascadeGroupCancellation =
        statusRequested &&
        !statusNoOp &&
        nextStatus === GameRequestStatus.canceled;

      const rootRequestId = gameRequest.sharedRootId ?? gameRequest.id;
      const relatedRequests = shouldCascadeGroupCancellation
        ? await tx.gameRequest.findMany({
            where: {
              OR: [{ id: rootRequestId }, { sharedRootId: rootRequestId }]
            },
            include: {
              proposedCourt: true
            }
          })
        : [];
      const cascadeRequests = relatedRequests.length > 1 ? relatedRequests : [];
      const resolvedNextStatus =
        statusRequested && !statusNoOp && nextStatus !== undefined
          ? nextStatus
          : undefined;

      let result: typeof relatedRequests[number] | (typeof gameRequest & { proposedCourt?: null });

      if (cascadeRequests.length > 0) {
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
              recipientUserId
            });
          }
        }

        const refreshed = await tx.gameRequest.findUnique({
          where: { id: params.id },
          include: { proposedCourt: true }
        });

        if (!refreshed) {
          throw new Error("Предложение игры не найдено");
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
                  proposedCourtId: body.proposedCourtId ?? gameRequest.proposedCourtId,
                  proposedDatetime: body.proposedDatetime ? new Date(body.proposedDatetime) : gameRequest.proposedDatetime,
                  durationMinutes: body.durationMinutes !== undefined ? body.durationMinutes : gameRequest.durationMinutes,
                  levelRangeMin: body.levelRangeMin !== undefined ? body.levelRangeMin : gameRequest.levelRangeMin,
                  levelRangeMax: body.levelRangeMax !== undefined ? body.levelRangeMax : gameRequest.levelRangeMax,
                  sport: effectiveSport,
                  format: effectiveFormat,
                  comment: body.comment !== undefined ? body.comment : (gameRequest.comment ?? "")
                }
              : {})
          },
          include: {
            proposedCourt: true
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
          const editMessage = getEditChangeMessage({
            proposedDatetime: result.proposedDatetime,
            courtName: result.proposedCourt?.name ?? null,
            resetConfirmation: false
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

        if (gameRequest.format === "singles" || gameRequest.format === "both") {
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
          await ensureGroupSearchLobby(tx, groupRequests, {
            senderUserId: user.id,
            createIntroMessage: true
          });
        }
      }

      return result;
    });

    if (notificationTargets.length === 0) {
      const recipientUserId = isCreator ? gameRequest.matchedUserId : gameRequest.createdByUserId;
      if (recipientUserId && ((statusRequested && !statusNoOp) || (outcomeRequested && !outcomeNoOp) || (editableRequested && !editableNoOp))) {
        notificationTargets.push({
          requestId: gameRequest.id,
          recipientUserId
        });
      }
    }

    if ((statusRequested && !statusNoOp) || (outcomeRequested && !outcomeNoOp) || (editableRequested && !editableNoOp)) {
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
            ? getEditChangeMessage({
                proposedDatetime: updated.proposedDatetime,
                courtName: updated.proposedCourt?.name ?? null,
                resetConfirmation: false
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

    return ok({
      gameRequest: serializeGameRequest(updated)
    });
  } catch (error) {
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

function getEditChangeMessage(options: {
  proposedDatetime: Date;
  courtName?: string | null;
  resetConfirmation?: boolean;
}) {
  const timeLabel = options.proposedDatetime.toLocaleString("ru-RU");
  const placeLabel = options.courtName ? ` · ${options.courtName}` : "";
  const confirmationLabel = options.resetConfirmation ? " Подтверждение нужно заново." : "";
  return `Предложение игры обновлено: ${timeLabel}${placeLabel}.${confirmationLabel}`.trim();
}
