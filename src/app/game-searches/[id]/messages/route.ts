import { NextRequest } from "next/server";
import { GameSearchResponseStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchMessageSchema } from "@/lib/validators";
import { isUserActiveInChat, publishRealtimeEventToUsers } from "@/server/realtime";
import {
  chatMessagePreview,
  claimGameSearchMessageAttachments,
  gameSearchMessageAttachmentsInclude,
  serializeChatMessage
} from "@/server/chat-media";

async function canAccessSearch(userId: string, gameSearchId: string) {
  return prisma.gameSearch.findFirst({
    where: {
      id: gameSearchId,
      OR: [
        { createdByUserId: userId },
        {
          responses: {
            some: {
              responderUserId: userId,
              status: GameSearchResponseStatus.approved
            }
          }
        }
      ]
    },
    select: { id: true }
  });
}

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const allowed = await canAccessSearch(user.id, params.id);

    if (!allowed) {
      return fail("Нет доступа", 403);
    }

    const messages = await prisma.gameSearchMessage.findMany({
      where: {
        gameSearchId: params.id
      },
      include: {
        senderUser: true,
        ...gameSearchMessageAttachmentsInclude
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
    const allowed = await canAccessSearch(user.id, params.id);

    if (!allowed) {
      return fail("Нет доступа", 403);
    }

    const body = createGameSearchMessageSchema.parse(await request.json());

    const message = await prisma.$transaction(async (tx) => {
      const created = await tx.gameSearchMessage.create({
        data: {
          gameSearchId: params.id,
          senderUserId: user.id,
          text: body.text
        }
      });

      await claimGameSearchMessageAttachments(tx, {
        attachmentIds: body.attachmentIds,
        uploaderUserId: user.id,
        gameSearchMessageId: created.id
      });

      return tx.gameSearchMessage.findUniqueOrThrow({
        where: { id: created.id },
        include: {
          senderUser: true,
          ...gameSearchMessageAttachmentsInclude
        }
      });
    });

    const search = await prisma.gameSearch.findUnique({
      where: { id: params.id },
      select: {
        id: true,
        createdByUser: {
          select: {
            id: true,
            notificationMessages: true,
            notificationSound: true
          }
        },
        responses: {
          where: {
            status: GameSearchResponseStatus.approved
          },
          select: {
            status: true,
            responderUser: {
              select: {
                id: true,
                notificationMessages: true,
                notificationSound: true
              }
            }
          }
        }
      }
    });

    const recipientsById = new Map<
      string,
      { id: string; notificationMessages: boolean; notificationSound: boolean | null }
    >();

    if (search?.createdByUser.id !== user.id) {
      const creator = search?.createdByUser;
      if (creator) {
        recipientsById.set(creator.id, creator);
      }
    }

    for (const response of search?.responses ?? []) {
      const recipient = response.responderUser;
      if (response.status === GameSearchResponseStatus.approved && recipient.id !== user.id) {
        recipientsById.set(recipient.id, recipient);
      }
    }

    const recipients = Array.from(recipientsById.values());
    const realtimeRecipientIds = Array.from(
      new Set((search?.responses ?? []).map((response) => response.responderUser.id).filter((id) => id !== user.id))
    );
    const pushBody = chatMessagePreview(message);

    await Promise.all(
      recipients.map(async (recipient) => {
        const activeInLobby = await isUserActiveInChat(recipient.id, [`search:${params.id}`]);

        if (!recipient.notificationMessages || activeInLobby) {
          return;
        }

        await sendPushToUser({
          userId: recipient.id,
          title: `Сообщение в лобби от ${user.name ?? "игрока"}`,
          body: pushBody,
          href: `/play/searches/${params.id}`,
          sound: recipient.notificationSound ?? true
        });
      })
    );

    await publishRealtimeEventToUsers([user.id, ...realtimeRecipientIds], {
      type: "chat_message_created",
      searchId: params.id,
      messageId: message.id,
      href: `/play/searches/${params.id}`
    });

    return ok({
      message: serializeChatMessage(message)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
