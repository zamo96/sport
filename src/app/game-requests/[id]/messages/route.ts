import { recordUserEvent } from "@/server/user-events";
import { NextRequest } from "next/server";

import { sendPushToUser } from "@/lib/push";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { directMessageSchema } from "@/lib/validators";
import { isUserActiveInChat, publishRealtimeEventToUsers } from "@/server/realtime";
import {
  chatMessageAttachmentsInclude,
  chatMessagePreview,
  claimChatMessageAttachments,
  serializeChatMessage
} from "@/server/chat-media";
import { hasBlockBetweenUsers, lockActiveUsersForMutation } from "@/server/account-status";

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
    const otherUserId = gameRequest.createdByUserId === user.id ? gameRequest.matchedUserId : gameRequest.createdByUserId;
    if (await hasBlockBetweenUsers(prisma, user.id, otherUserId)) return fail("Нет доступа", 403);

    const messages = await prisma.chatMessage.findMany({
      where: {
        matchId: gameRequest.matchId,
        gameRequestId: gameRequest.id
      },
      include: {
        senderUser: true,
        ...chatMessageAttachmentsInclude
      },
      orderBy: {
        createdAt: "asc"
      }
    });

    return ok({
      messages: messages.map(serializeChatMessage)
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
    const body = directMessageSchema.parse(await request.json());
    const gameRequest = await getGameRequestForUser(params.id, user.id);

    if (!gameRequest) {
      return fail("Игра не найдена", 404);
    }
    const otherUserId = gameRequest.createdByUserId === user.id ? gameRequest.matchedUserId : gameRequest.createdByUserId;
    if (await hasBlockBetweenUsers(prisma, user.id, otherUserId)) return fail("Нет доступа", 403);

    const message = await prisma.$transaction(async (tx) => {
      const locked = await lockActiveUsersForMutation(tx, [user.id, otherUserId]);
      if (!locked.has(user.id) || !locked.has(otherUserId) || await hasBlockBetweenUsers(tx, user.id, otherUserId)) {
        throw new Error("INTERACTION_UNAVAILABLE");
      }
      const created = await tx.chatMessage.create({
        data: {
          matchId: gameRequest.matchId,
          gameRequestId: gameRequest.id,
          senderUserId: user.id,
          text: body.text
        }
      });

      await claimChatMessageAttachments(tx, {
        attachmentIds: body.attachmentIds,
        uploaderUserId: user.id,
        chatMessageId: created.id
      });

      await tx.gameRequest.update({
        where: { id: gameRequest.id },
        data: { updatedAt: new Date() }
      });

      await tx.match.update({
        where: { id: gameRequest.matchId },
        data: { updatedAt: new Date() }
      });

      return tx.chatMessage.findUniqueOrThrow({
        where: { id: created.id },
        include: {
          senderUser: true,
          ...chatMessageAttachmentsInclude
        }
      });
    });

    await recordUserEvent({ userId: user.id, type: "message_sent", entityType: "chat_message", entityId: message.id });
    const recipientUserId = gameRequest.createdByUserId === user.id ? gameRequest.matchedUserId : gameRequest.createdByUserId;
    const recipient = await prisma.user.findUnique({
      where: { id: recipientUserId },
      select: {
        id: true,
        notificationMessages: true,
        notificationSound: true
      }
    });

    const recipientActiveInChat = await isUserActiveInChat(recipientUserId, [
      `game:${gameRequest.id}`,
      `match:${gameRequest.matchId}`
    ]);

    if (recipient?.notificationMessages && !recipientActiveInChat) {
      await sendPushToUser({
        userId: recipient.id,
        title: `Сообщение по игре от ${user.name ?? "игрока"}`,
        body: chatMessagePreview(message),
        href: `/play/games/${gameRequest.id}`,
        sound: recipient.notificationSound ?? true
      });
    }

    await publishRealtimeEventToUsers([user.id, recipientUserId], {
      type: "chat_message_created",
      matchId: gameRequest.matchId,
      gameRequestId: gameRequest.id,
      messageId: message.id,
      href: `/play/games/${gameRequest.id}`
    });

    return ok({
      message: serializeChatMessage(message)
    });
  } catch (error) {
    if (getErrorMessage(error) === "INTERACTION_UNAVAILABLE") return fail("Нет доступа", 403);
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
