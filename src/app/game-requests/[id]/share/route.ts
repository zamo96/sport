import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { shareGameRequestSchema } from "@/lib/validators";
import { serializeGameRequest, serializeUserPreview } from "@/server/serializers";

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = shareGameRequestSchema.parse(await request.json());

    const sourceRequest = await prisma.gameRequest.findUnique({
      where: { id: params.id },
      include: {
        match: true,
        proposedCourt: true
      }
    });

    if (!sourceRequest) {
      return fail("Договоренность не найдена", 404);
    }

    if (sourceRequest.createdByUserId !== user.id) {
      return fail("Рассылать приглашения может только автор договоренности", 403);
    }

    if (sourceRequest.status === "canceled" || sourceRequest.status === "declined") {
      return fail("Нельзя рассылать отмененную или отклоненную договоренность", 409);
    }

    const sharedRootId = sourceRequest.sharedRootId ?? sourceRequest.id;

    const uniqueMatchIds = Array.from(new Set(body.matchIds)).filter((matchId) => matchId !== sourceRequest.matchId);
    if (uniqueMatchIds.length === 0) {
      return fail("Нужен хотя бы один другой мэтч", 400);
    }

    const targetMatches = await prisma.match.findMany({
      where: {
        id: {
          in: uniqueMatchIds
        },
        OR: [{ user1Id: user.id }, { user2Id: user.id }]
      },
      include: {
        user1: true,
        user2: true
      }
    });

    if (targetMatches.length !== uniqueMatchIds.length) {
      return fail("Не все мэтчи доступны для рассылки", 404);
    }

    const sharedGameRequests = await prisma.$transaction(async (tx) => {
      const createdRequests = [];

      for (const targetMatch of targetMatches) {
        const matchedUserId = targetMatch.user1Id === user.id ? targetMatch.user2Id : targetMatch.user1Id;

        const duplicate = await tx.gameRequest.findFirst({
          where: {
            matchId: targetMatch.id,
            sharedRootId,
            createdByUserId: user.id,
            matchedUserId,
            proposedCourtId: sourceRequest.proposedCourtId,
            proposedDatetime: sourceRequest.proposedDatetime,
            sport: sourceRequest.sport,
            format: sourceRequest.format,
            status: {
              in: ["pending", "accepted"]
            }
          },
          include: {
            proposedCourt: true
          }
        });

        if (duplicate) {
          createdRequests.push({
            ...duplicate,
            createdByUser: user,
            matchedUser: targetMatch.user1Id === user.id ? targetMatch.user2 : targetMatch.user1,
            match: targetMatch
          });
          continue;
        }

        const created = await tx.gameRequest.create({
          data: {
            matchId: targetMatch.id,
            sharedRootId,
            createdByUserId: user.id,
            matchedUserId,
            proposedCourtId: sourceRequest.proposedCourtId,
            proposedDatetime: sourceRequest.proposedDatetime,
            durationMinutes: sourceRequest.durationMinutes ?? null,
            levelRangeMin: sourceRequest.levelRangeMin ?? null,
            levelRangeMax: sourceRequest.levelRangeMax ?? null,
            sport: sourceRequest.sport,
            format: sourceRequest.format,
            comment: sourceRequest.comment
          },
          include: {
            proposedCourt: true
          }
        });

        const summaryText = `Предложение игры: ${created.proposedDatetime.toLocaleString("ru-RU")} · ${created.format}. ${
          created.comment?.trim() ? created.comment : "Открой детали, чтобы обсудить игру отдельно."
        }`;

        await tx.chatMessage.create({
          data: {
            matchId: targetMatch.id,
            gameRequestId: null,
            senderUserId: user.id,
            text: summaryText
          }
        });

        await tx.chatMessage.create({
          data: {
            matchId: targetMatch.id,
            gameRequestId: created.id,
            senderUserId: user.id,
            text: "Отправил(а) уже созданную игру и жду подтверждения приглашения."
          }
        });

        await tx.match.update({
          where: { id: targetMatch.id },
          data: { updatedAt: new Date() }
        });

        createdRequests.push({
          ...created,
          createdByUser: user,
          matchedUser: targetMatch.user1Id === user.id ? targetMatch.user2 : targetMatch.user1,
          match: targetMatch
        });
      }

      return createdRequests;
    });

    return ok({
      gameRequests: sharedGameRequests.map((gameRequest) => ({
        ...serializeGameRequest(gameRequest),
        createdByUser: serializeUserPreview(gameRequest.createdByUser),
        matchedUser: serializeUserPreview(gameRequest.matchedUser),
        participants: [serializeUserPreview(gameRequest.match.user1), serializeUserPreview(gameRequest.match.user2)]
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
