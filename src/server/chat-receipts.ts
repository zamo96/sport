import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { hasBlockBetweenUsers } from "@/server/account-status";
import { publishRealtimeEventToUsers, type RealtimeEventPayload } from "@/server/realtime";

export const chatReceiptSchema = z.object({
  matchId: z.string().min(1).optional(),
  gameRequestId: z.string().min(1).optional(),
  searchId: z.string().min(1).optional(),
  messageIds: z.array(z.string().min(1)).min(1).max(200),
  status: z.enum(["delivered", "read"])
}).refine((body) => [body.matchId, body.gameRequestId, body.searchId].filter(Boolean).length === 1, {
  message: "Укажите один чат"
});

type ReceiptInput = z.infer<typeof chatReceiptSchema>;

export async function acknowledgeChatMessages(userId: string, input: ReceiptInput) {
  const messageIds = [...new Set(input.messageIds)];
  const result = await prisma.$transaction(async (tx) => {
    let matchId = input.matchId;
    let otherUserId: string | undefined;
    if (input.searchId) {
      const search = await tx.gameSearch.findFirst({
        where: {
          id: input.searchId,
          OR: [
            { createdByUserId: userId },
            { responses: { some: { responderUserId: userId, status: "approved" } } }
          ]
        },
        select: { id: true }
      });
      if (!search) throw new Error("CHAT_RECEIPT_FORBIDDEN");
    } else if (input.gameRequestId) {
      const game = await tx.gameRequest.findFirst({
        where: {
          id: input.gameRequestId,
          OR: [{ createdByUserId: userId }, { matchedUserId: userId }]
        },
        select: { matchId: true, createdByUserId: true, matchedUserId: true }
      });
      if (!game) throw new Error("CHAT_RECEIPT_FORBIDDEN");
      matchId = game.matchId;
      otherUserId = game.createdByUserId === userId ? game.matchedUserId : game.createdByUserId;
    } else {
      const match = await tx.match.findFirst({
        where: { id: matchId, OR: [{ user1Id: userId }, { user2Id: userId }] },
        select: { user1Id: true, user2Id: true }
      });
      if (!match) throw new Error("CHAT_RECEIPT_FORBIDDEN");
      otherUserId = match.user1Id === userId ? match.user2Id : match.user1Id;
    }
    if (otherUserId && await hasBlockBetweenUsers(tx, userId, otherUserId)) {
      throw new Error("CHAT_RECEIPT_FORBIDDEN");
    }

    const messages = input.searchId
      ? await tx.gameSearchMessage.findMany({
          where: { id: { in: messageIds }, gameSearchId: input.searchId, senderUserId: { not: userId } },
          select: { id: true, senderUserId: true }
        })
      : await tx.chatMessage.findMany({
          where: {
            id: { in: messageIds }, matchId,
            ...(input.gameRequestId ? { gameRequestId: input.gameRequestId } : {}),
            senderUserId: { not: userId }
          },
          select: { id: true, senderUserId: true }
        });
    // An invalid ID rejects the complete batch; it can never acknowledge a
    // different conversation or let the sender confirm their own message.
    if (messages.length !== messageIds.length) throw new Error("CHAT_RECEIPT_FORBIDDEN");
    const senderIds = [...new Set(messages.map((message) => message.senderUserId))];
    if (input.searchId) {
      const block = await tx.block.findFirst({
        where: { OR: [
          { blockerUserId: userId, blockedUserId: { in: senderIds } },
          { blockedUserId: userId, blockerUserId: { in: senderIds } }
        ] },
        select: { id: true }
      });
      if (block) throw new Error("CHAT_RECEIPT_FORBIDDEN");
    }

    const now = new Date();
    const created = await tx.messageReceipt.createMany({
      data: messageIds.map((id) => ({
        userId,
        ...(input.searchId ? { gameSearchMessageId: id } : { chatMessageId: id }),
        deliveredAt: now,
        readAt: input.status === "read" ? now : null
      })),
      skipDuplicates: true
    });
    const advanced = input.status === "read"
      ? await tx.messageReceipt.updateMany({
          where: {
            userId, readAt: null,
            ...(input.searchId ? { gameSearchMessageId: { in: messageIds } } : { chatMessageId: { in: messageIds } })
          },
          data: { readAt: now }
        })
      : { count: 0 };
    return { changed: created.count + advanced.count > 0, senderIds, matchId };
  });

  if (result.changed) {
    const event: RealtimeEventPayload = {
      type: "chat_receipts_updated",
      matchId: result.matchId,
      gameRequestId: input.gameRequestId,
      searchId: input.searchId
    };
    await publishRealtimeEventToUsers(result.senderIds, event);
  }
}
