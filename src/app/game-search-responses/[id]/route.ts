import { NextRequest } from "next/server";
import { GameSearchResponseStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updateGameSearchResponseSchema } from "@/lib/validators";
import { ensureMatchForUsers } from "@/server/matching";

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

      if (body.status === GameSearchResponseStatus.approved) {
        await tx.gameSearchResponse.updateMany({
          where: {
            gameSearchId: response.gameSearchId,
            id: { not: response.id },
            status: GameSearchResponseStatus.pending
          },
          data: {
            status: GameSearchResponseStatus.rejected
          }
        });

        await tx.gameSearch.update({
          where: { id: response.gameSearchId },
          data: {
            status: "matched",
            isActive: false
          }
        });

        const match = await ensureMatchForUsers(tx, response.gameSearch.createdByUserId, response.responderUserId);
        matchId = match.id;

        if (
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
              text: `Я подтвердил(а) твой отклик на поиск игры. Давай согласуем площадку и время.`
            }
          });
        }

        await tx.match.update({
          where: { id: match.id },
          data: { updatedAt: new Date() }
        });
      } else {
        const remainingPending = await tx.gameSearchResponse.count({
          where: {
            gameSearchId: response.gameSearchId,
            status: GameSearchResponseStatus.pending
          }
        });

        await tx.gameSearch.update({
          where: { id: response.gameSearchId },
          data: {
            status:
              response.gameSearch.status === "matched"
                ? "matched"
                : remainingPending > 0
                  ? "in_review"
                  : response.gameSearch.isActive
                    ? "active"
                    : "closed"
          }
        });
      }

      return { updated, matchId, gameRequestId };
    });

    return ok({
      response: {
        ...result.updated,
        createdAt: result.updated.createdAt.toISOString(),
        updatedAt: result.updated.updatedAt.toISOString()
      },
      matchId: result.matchId,
      gameRequestId: result.gameRequestId
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
