import { NextRequest } from "next/server";
import { GameRequestStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameRequestSchema } from "@/lib/validators";
import { publishRealtimeEventToUsers } from "@/server/realtime";
import { touchUserActivity } from "@/server/user-activity";

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    await touchUserActivity(user.id);
    const body = createGameRequestSchema.parse(await request.json());
    const match = await prisma.match.findFirst({
      where: {
        id: body.matchId,
        OR: [{ user1Id: user.id }, { user2Id: user.id }]
      }
    });

    if (!match) {
      return fail("Мэтч не найден", 404);
    }

    const matchedUserId = match.user1Id === user.id ? match.user2Id : match.user1Id;

    const gameRequest = await prisma.$transaction(async (tx) => {
      const created = await tx.gameRequest.create({
        data: {
          matchId: match.id,
          createdByUserId: user.id,
          matchedUserId,
          proposedCourtId: body.proposedCourtId ?? null,
          proposedDatetime: new Date(body.proposedDatetime),
          durationMinutes: body.durationMinutes ?? null,
          levelRangeMin: body.levelRangeMin ?? null,
          levelRangeMax: body.levelRangeMax ?? null,
          sport: body.sport,
          format: body.format,
          comment: body.comment,
          status: GameRequestStatus.pending
        },
        include: {
          proposedCourt: true
        }
      });

      const summaryText = `Предложение игры: ${created.proposedDatetime.toLocaleString("ru-RU")} · ${created.format}. ${
        created.comment?.trim() ? created.comment : "Второй игрок должен подтвердить игру."
      }`;

      await tx.chatMessage.create({
        data: {
          matchId: match.id,
          gameRequestId: null,
          senderUserId: user.id,
          text: summaryText
        }
      });

      await tx.chatMessage.create({
        data: {
          matchId: match.id,
          gameRequestId: created.id,
          senderUserId: user.id,
          text: created.comment?.trim()
            ? `Предложил(а) игру. ${created.comment}`
            : "Предложил(а) игру. Подтверди предложение, если время и место подходят."
        }
      });

      await tx.match.update({
        where: { id: match.id },
        data: { updatedAt: new Date() }
      });

      return created;
    });

    const recipient = await prisma.user.findUnique({
      where: { id: matchedUserId },
      select: {
        id: true,
        notificationGames: true,
        notificationSound: true
      }
    });

    await publishRealtimeEventToUsers([user.id, matchedUserId], {
      type: "game_request_created",
      matchId: match.id,
      gameRequestId: gameRequest.id,
      status: gameRequest.status,
      href: `/play/games/${gameRequest.id}`
    });

    if (recipient?.notificationGames) {
      await sendPushToUser({
        userId: recipient.id,
        title: `Предложение игры от ${user.name ?? "игрока"}`,
        body: `Подтверди: ${gameRequest.proposedCourt?.name ?? "Место уточняется"} · ${gameRequest.proposedDatetime.toLocaleString("ru-RU")}`,
        href: `/play/games/${gameRequest.id}`,
        sound: recipient.notificationSound ?? true
      });
    }

    return ok({
      gameRequest: {
        ...gameRequest,
        proposedDatetime: gameRequest.proposedDatetime.toISOString(),
        createdAt: gameRequest.createdAt.toISOString(),
        updatedAt: gameRequest.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
