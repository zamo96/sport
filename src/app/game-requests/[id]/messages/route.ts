import { NextRequest } from "next/server";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { messageSchema } from "@/lib/validators";

async function getGameRequestForUser(gameRequestId: string, userId: string) {
  return prisma.gameRequest.findFirst({
    where: {
      id: gameRequestId,
      OR: [{ createdByUserId: userId }, { matchedUserId: userId }]
    }
  });
}

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const gameRequest = await getGameRequestForUser(params.id, user.id);

    if (!gameRequest) {
      return fail("Игра не найдена", 404);
    }

    const messages = await prisma.chatMessage.findMany({
      where: {
        matchId: gameRequest.matchId,
        gameRequestId: gameRequest.id
      },
      include: {
        senderUser: true
      },
      orderBy: {
        createdAt: "asc"
      }
    });

    return ok({
      messages: messages.map((message) => ({
        ...message,
        createdAt: message.createdAt.toISOString()
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = messageSchema.parse(await request.json());
    const gameRequest = await getGameRequestForUser(params.id, user.id);

    if (!gameRequest) {
      return fail("Игра не найдена", 404);
    }

    const message = await prisma.$transaction(async (tx) => {
      const created = await tx.chatMessage.create({
        data: {
          matchId: gameRequest.matchId,
          gameRequestId: gameRequest.id,
          senderUserId: user.id,
          text: body.text
        },
        include: {
          senderUser: true
        }
      });

      await tx.gameRequest.update({
        where: { id: gameRequest.id },
        data: { updatedAt: new Date() }
      });

      await tx.match.update({
        where: { id: gameRequest.matchId },
        data: { updatedAt: new Date() }
      });

      return created;
    });

    const recipientUserId = gameRequest.createdByUserId === user.id ? gameRequest.matchedUserId : gameRequest.createdByUserId;
    const recipient = await prisma.user.findUnique({
      where: { id: recipientUserId },
      select: {
        id: true,
        notificationMessages: true,
        notificationSound: true
      }
    });

    if (recipient?.notificationMessages) {
      await sendPushToUser({
        userId: recipient.id,
        title: `Сообщение по игре от ${user.name ?? "игрока"}`,
        body: body.text.length > 120 ? `${body.text.slice(0, 117)}...` : body.text,
        href: `/play/games/${gameRequest.id}`,
        sound: recipient.notificationSound ?? true
      });
    }

    return ok({
      message: {
        ...message,
        createdAt: message.createdAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
