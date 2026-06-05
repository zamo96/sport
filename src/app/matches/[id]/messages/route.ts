import { NextRequest } from "next/server";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { messageSchema } from "@/lib/validators";
import { touchUserActivity } from "@/server/user-activity";

async function getMatchForUser(matchId: string, userId: string) {
  return prisma.match.findFirst({
    where: {
      id: matchId,
      OR: [{ user1Id: userId }, { user2Id: userId }]
    }
  });
}

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    await touchUserActivity(user.id);
    const match = await getMatchForUser(params.id, user.id);

    if (!match) {
      return fail("Мэтч не найден", 404);
    }

    const messages = await prisma.chatMessage.findMany({
      where: {
        matchId: match.id,
        gameRequestId: null
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
    await touchUserActivity(user.id);
    const body = messageSchema.parse(await request.json());
    const match = await getMatchForUser(params.id, user.id);

    if (!match) {
      return fail("Мэтч не найден", 404);
    }

    const message = await prisma.$transaction(async (tx) => {
      const created = await tx.chatMessage.create({
        data: {
          matchId: match.id,
          gameRequestId: null,
          senderUserId: user.id,
          text: body.text
        },
        include: {
          senderUser: true
        }
      });

      await tx.match.update({
        where: { id: match.id },
        data: { updatedAt: new Date() }
      });

      return created;
    });

    const recipientUserId = match.user1Id === user.id ? match.user2Id : match.user1Id;
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
        title: `Новое сообщение от ${user.name ?? "игрока"}`,
        body: body.text.length > 120 ? `${body.text.slice(0, 117)}...` : body.text,
        href: `/inbox/${match.id}`,
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
