import { NextRequest } from "next/server";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { messageSchema } from "@/lib/validators";
import { isUserActiveInChat, publishRealtimeEventToUsers } from "@/server/realtime";
import { touchUserActivity } from "@/server/user-activity";
import { hasBlockBetweenUsers, lockActiveUsersForMutation } from "@/server/account-status";
import {
  chatMessageAttachmentsInclude,
  chatMessagePreview,
  claimChatMessageAttachments,
  serializeChatMessage
} from "@/server/chat-media";

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
    const otherUserId = match.user1Id === user.id ? match.user2Id : match.user1Id;
    if (await hasBlockBetweenUsers(prisma, user.id, otherUserId)) return fail("Нет доступа", 403);

    const messages = await prisma.chatMessage.findMany({
      where: {
        matchId: match.id
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
    await touchUserActivity(user.id);
    const body = messageSchema.parse(await request.json());
    const match = await getMatchForUser(params.id, user.id);

    if (!match) {
      return fail("Мэтч не найден", 404);
    }
    const otherUserId = match.user1Id === user.id ? match.user2Id : match.user1Id;
    if (await hasBlockBetweenUsers(prisma, user.id, otherUserId)) return fail("Нет доступа", 403);

    const message = await prisma.$transaction(async (tx) => {
      const locked = await lockActiveUsersForMutation(tx, [user.id, otherUserId]);
      if (!locked.has(user.id) || !locked.has(otherUserId) || await hasBlockBetweenUsers(tx, user.id, otherUserId)) {
        throw new Error("INTERACTION_UNAVAILABLE");
      }
      const created = await tx.chatMessage.create({
        data: {
          matchId: match.id,
          gameRequestId: null,
          senderUserId: user.id,
          text: body.text
        }
      });

      await claimChatMessageAttachments(tx, {
        attachmentIds: body.attachmentIds,
        uploaderUserId: user.id,
        chatMessageId: created.id
      });

      await tx.match.update({
        where: { id: match.id },
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

    const recipientUserId = match.user1Id === user.id ? match.user2Id : match.user1Id;
    const recipient = await prisma.user.findUnique({
      where: { id: recipientUserId },
      select: {
        id: true,
        notificationMessages: true,
        notificationSound: true
      }
    });

    const recipientActiveInChat = await isUserActiveInChat(recipientUserId, [`match:${match.id}`]);

    if (recipient?.notificationMessages && !recipientActiveInChat) {
      await sendPushToUser({
        userId: recipient.id,
        title: `Новое сообщение от ${user.name ?? "игрока"}`,
        body: chatMessagePreview(message),
        href: `/inbox/${match.id}`,
        sound: recipient.notificationSound ?? true
      });
    }

    await publishRealtimeEventToUsers([user.id, recipientUserId], {
      type: "chat_message_created",
      matchId: match.id,
      messageId: message.id,
      href: `/inbox/${match.id}`
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
