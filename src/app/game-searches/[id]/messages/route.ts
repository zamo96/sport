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
import { hasBlockBetweenUsers, lockActiveUsersForMutation } from "@/server/account-status";

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
    select: {
      id: true,
      createdByUserId: true,
      responses: {
        where: { status: GameSearchResponseStatus.approved },
        select: { responderUserId: true }
      }
    }
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
        gameSearchId: params.id,
        senderUser: {
          blockedUsers: { none: { blockedUserId: user.id } },
          blockingUsers: { none: { blockerUserId: user.id } }
        }
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
    const participantIds = Array.from(new Set([
      allowed.createdByUserId,
      ...allowed.responses.map((response) => response.responderUserId)
    ]));

    const message = await prisma.$transaction(async (tx) => {
      const locked = await lockActiveUsersForMutation(tx, participantIds);
      if (!locked.has(user.id)) throw new Error("INTERACTION_UNAVAILABLE");
      const otherParticipantIds = participantIds.filter((id) => id !== user.id);
      const block = otherParticipantIds.length > 0
        ? await tx.block.findFirst({
            where: {
              OR: [
                { blockerUserId: user.id, blockedUserId: { in: otherParticipantIds } },
                { blockedUserId: user.id, blockerUserId: { in: otherParticipantIds } }
              ]
            },
            select: { id: true }
          })
        : null;
      if (block) throw new Error("INTERACTION_UNAVAILABLE");
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
    const unblockedRecipients = (
      await Promise.all(
        recipients.map(async (recipient) => ({
          recipient,
          blocked: await hasBlockBetweenUsers(prisma, user.id, recipient.id)
        }))
      )
    ).filter((item) => !item.blocked).map((item) => item.recipient);
    const candidateRealtimeRecipientIds = Array.from(
      new Set((search?.responses ?? []).map((response) => response.responderUser.id).filter((id) => id !== user.id))
    );
    const realtimeRecipientIds = (
      await Promise.all(
        candidateRealtimeRecipientIds.map(async (id) => ({ id, blocked: await hasBlockBetweenUsers(prisma, user.id, id) }))
      )
    ).filter((item) => !item.blocked).map((item) => item.id);
    const pushBody = chatMessagePreview(message);

    await Promise.all(
      unblockedRecipients.map(async (recipient) => {
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
    if (getErrorMessage(error) === "INTERACTION_UNAVAILABLE") return fail("Нет доступа", 403);
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
