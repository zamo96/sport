import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  tx: {
    match: { findFirst: vi.fn() },
    gameRequest: { findFirst: vi.fn() },
    gameSearch: { findFirst: vi.fn() },
    chatMessage: { findMany: vi.fn() },
    gameSearchMessage: { findMany: vi.fn() },
    block: { findFirst: vi.fn() },
    messageReceipt: { createMany: vi.fn(), updateMany: vi.fn() }
  },
  publish: vi.fn(),
  requireSessionUser: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({ prisma: { $transaction: (callback: (tx: typeof mocks.tx) => unknown) => callback(mocks.tx) } }));
vi.mock("@/server/realtime", () => ({ publishRealtimeEventToUsers: mocks.publish }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.requireSessionUser }));

import { summarizeChatReceipts } from "@/lib/chat-receipts";
import { acknowledgeChatMessages, chatReceiptSchema } from "@/server/chat-receipts";
import { serializeChatMessage } from "@/server/chat-media";
import { POST } from "@/app/activity/chat-receipts/route";

type StoredReceipt = { userId: string; chatMessageId?: string; gameSearchMessageId?: string; deliveredAt: Date; readAt: Date | null };
let stored: StoredReceipt[];

beforeEach(() => {
  vi.clearAllMocks();
  stored = [];
  mocks.requireSessionUser.mockResolvedValue({ id: "recipient" });
  mocks.tx.match.findFirst.mockResolvedValue({ user1Id: "sender", user2Id: "recipient" });
  mocks.tx.gameRequest.findFirst.mockResolvedValue({ matchId: "match", createdByUserId: "sender", matchedUserId: "recipient" });
  mocks.tx.gameSearch.findFirst.mockResolvedValue({ id: "search" });
  mocks.tx.block.findFirst.mockResolvedValue(null);
  const messages = [{ id: "m1", senderUserId: "sender", matchId: "match", gameRequestId: "game", gameSearchId: "search" }];
  for (const model of [mocks.tx.chatMessage, mocks.tx.gameSearchMessage]) {
    model.findMany.mockImplementation(async ({ where }) => messages.filter((message) =>
      where.id.in.includes(message.id) && message.senderUserId !== where.senderUserId.not &&
      (!where.matchId || message.matchId === where.matchId) &&
      (!where.gameRequestId || message.gameRequestId === where.gameRequestId) &&
      (!where.gameSearchId || message.gameSearchId === where.gameSearchId)
    ));
  }
  mocks.tx.messageReceipt.createMany.mockImplementation(async ({ data }: { data: StoredReceipt[] }) => {
    let count = 0;
    for (const row of data) {
      if (!stored.some((old) => old.userId === row.userId && old.chatMessageId === row.chatMessageId && old.gameSearchMessageId === row.gameSearchMessageId)) {
        stored.push({ ...row });
        count++;
      }
    }
    return { count };
  });
  mocks.tx.messageReceipt.updateMany.mockImplementation(async ({ where, data }) => {
    let count = 0;
    for (const row of stored) {
      if (row.userId === where.userId && row.readAt === null &&
        (where.chatMessageId?.in.includes(row.chatMessageId) || where.gameSearchMessageId?.in.includes(row.gameSearchMessageId))) {
        row.readAt = data.readAt;
        count++;
      }
    }
    return { count };
  });
});

const delivery = { matchId: "match", messageIds: ["m1"], status: "delivered" as const };

describe("chat receipt authorization", () => {
  it("rejects missing/ambiguous conversation scope, unsupported status and oversized batches", () => {
    for (const body of [
      { messageIds: ["m1"], status: "read" },
      { ...delivery, searchId: "search" },
      { ...delivery, messageIds: [] },
      { ...delivery, messageIds: Array(201).fill("m1") },
      { ...delivery, status: "sent" }
    ]) expect(chatReceiptSchema.safeParse(body).success).toBe(false);
    expect(chatReceiptSchema.safeParse(delivery).success).toBe(true);
  });

  it("denies strangers and never writes receipts", async () => {
    mocks.tx.match.findFirst.mockResolvedValue(null);
    await expect(acknowledgeChatMessages("stranger", delivery)).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    expect(stored).toEqual([]);
  });

  it("denies own messages", async () => {
    await expect(acknowledgeChatMessages("sender", delivery)).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    expect(stored).toEqual([]);
  });

  it("rejects a mixed batch containing an unknown message without partially acknowledging", async () => {
    await expect(acknowledgeChatMessages("recipient", { ...delivery, messageIds: ["m1", "other"] })).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    expect(stored).toEqual([]);
  });

  it("denies message IDs belonging to another direct chat or game", async () => {
    await expect(acknowledgeChatMessages("recipient", { ...delivery, matchId: "another-match" })).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    await expect(acknowledgeChatMessages("recipient", { gameRequestId: "another-game", messageIds: ["m1"], status: "read" })).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    expect(stored).toEqual([]);
  });

  it("denies blocked recipients in direct and group chats", async () => {
    mocks.tx.block.findFirst.mockResolvedValue({ id: "block" });
    await expect(acknowledgeChatMessages("recipient", delivery)).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    await expect(acknowledgeChatMessages("recipient", { searchId: "search", messageIds: ["m1"], status: "read" })).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    expect(stored).toEqual([]);
  });

  it("requires an approved group participant or creator, including on retries", async () => {
    const request = { searchId: "search", messageIds: ["m1"], status: "read" as const };
    await acknowledgeChatMessages("recipient", request);
    expect(mocks.tx.gameSearch.findFirst.mock.calls[0][0].where.OR).toEqual([
      { createdByUserId: "recipient" },
      { responses: { some: { responderUserId: "recipient", status: "approved" } } }
    ]);
    mocks.tx.gameSearch.findFirst.mockResolvedValue(null);
    await expect(acknowledgeChatMessages("recipient", request)).rejects.toThrow("CHAT_RECEIPT_FORBIDDEN");
    expect(stored).toHaveLength(1);
  });

  it("returns an authorization error from the HTTP endpoint", async () => {
    mocks.requireSessionUser.mockRejectedValue(new Error("UNAUTHORIZED"));
    const response = await POST(new Request("https://example.com/activity/chat-receipts", { method: "POST", body: JSON.stringify(delivery) }));
    expect(response.status).toBe(401);
    expect(stored).toEqual([]);
  });
});

describe("persistent monotonic receipts", () => {
  it("distinguishes delivered from read and survives duplicate, reordered multi-device acknowledgements", async () => {
    await acknowledgeChatMessages("recipient", delivery);
    expect(summarizeChatReceipts(stored)).toEqual({ status: "delivered", deliveredCount: 1, readCount: 0 });
    const deliveredAt = stored[0].deliveredAt;
    await acknowledgeChatMessages("recipient", { ...delivery, status: "read" });
    const readAt = stored[0].readAt;
    await acknowledgeChatMessages("recipient", delivery);
    await acknowledgeChatMessages("recipient", { ...delivery, status: "read" });
    expect(stored).toHaveLength(1);
    expect(stored[0].deliveredAt).toBe(deliveredAt);
    expect(stored[0].readAt).toBe(readAt);
    expect(summarizeChatReceipts(stored)).toEqual({ status: "read", deliveredCount: 1, readCount: 1 });
    expect(mocks.publish).toHaveBeenCalledTimes(2);
    expect(mocks.publish).toHaveBeenCalledWith(["sender"], expect.objectContaining({ type: "chat_receipts_updated", matchId: "match" }));
  });

  it("a read arriving first also confirms delivery, deduplicating IDs", async () => {
    await acknowledgeChatMessages("recipient", { ...delivery, messageIds: ["m1", "m1"], status: "read" });
    await acknowledgeChatMessages("recipient", delivery);
    expect(stored).toHaveLength(1);
    expect(stored[0].readAt).toBe(stored[0].deliveredAt);
    expect(mocks.publish).toHaveBeenCalledTimes(1);
  });

  it("uses the same per-message state from the match and game view", async () => {
    await acknowledgeChatMessages("recipient", delivery);
    await acknowledgeChatMessages("recipient", { gameRequestId: "game", messageIds: ["m1"], status: "read" });
    expect(stored).toHaveLength(1);
    expect(summarizeChatReceipts(stored).status).toBe("read");
    expect(mocks.publish).toHaveBeenLastCalledWith(["sender"], expect.objectContaining({ matchId: "match", gameRequestId: "game" }));
  });

  it("counts distinct group recipients and preserves historical confirmed counts", async () => {
    const request = { searchId: "search", messageIds: ["m1"], status: "read" as const };
    await acknowledgeChatMessages("recipient", request);
    await acknowledgeChatMessages("another-recipient", { ...request, status: "delivered" });
    await acknowledgeChatMessages("recipient", request);
    expect(summarizeChatReceipts(stored)).toEqual({ status: "read", deliveredCount: 2, readCount: 1 });
    expect(stored.every((row) => row.gameSearchMessageId === "m1" && !row.chatMessageId)).toBe(true);
  });

  it("serializes summary without exposing recipient timestamps and retains photo-only messages", () => {
    const result = serializeChatMessage({ id: "m1", text: "", createdAt: new Date(), attachments: [], receipts: [{ readAt: new Date() }, { readAt: null }] });
    expect(result.receipt).toEqual({ status: "read", deliveredCount: 2, readCount: 1 });
    expect(result).not.toHaveProperty("receipts");
    expect(result.text).toBe("");
  });

  it("does not invent historical confirmation or turn an omitted legacy field into a reset", () => {
    expect(summarizeChatReceipts([])).toEqual({ status: "sent", deliveredCount: 0, readCount: 0 });
    const old = serializeChatMessage({ id: "old", text: "hello", createdAt: new Date(), attachments: [] });
    expect(old).not.toHaveProperty("receipt");
  });
});
