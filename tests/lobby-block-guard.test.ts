import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => {
  const tx = {
    $queryRaw: vi.fn(),
    block: { findFirst: vi.fn() },
    gameSearchMessage: { create: vi.fn(), findUniqueOrThrow: vi.fn() }
  };
  return {
    tx,
    requireSessionUser: vi.fn(),
    gameSearchFindFirst: vi.fn(),
    transaction: vi.fn()
  };
});

vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.requireSessionUser }));
vi.mock("@/lib/prisma", () => ({
  prisma: {
    gameSearch: { findFirst: mocks.gameSearchFindFirst },
    $transaction: mocks.transaction
  }
}));
vi.mock("@/lib/apns", () => ({ sendPushToUser: vi.fn() }));
vi.mock("@/server/realtime", () => ({ isUserActiveInChat: vi.fn(), publishRealtimeEventToUsers: vi.fn() }));
vi.mock("@/server/chat-media", () => ({
  claimGameSearchMessageAttachments: vi.fn(),
  gameSearchMessageAttachmentsInclude: {},
  serializeChatMessage: vi.fn(),
  chatMessagePreview: vi.fn()
}));

import { POST } from "@/app/game-searches/[id]/messages/route";

describe("shared lobby block guard", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.requireSessionUser.mockResolvedValue({ id: "viewer-1", name: "Viewer" });
    mocks.gameSearchFindFirst.mockResolvedValue({
      id: "search-1",
      createdByUserId: "owner-1",
      responses: [{ responderUserId: "viewer-1" }]
    });
    mocks.transaction.mockImplementation(async (callback: (tx: typeof mocks.tx) => unknown) => callback(mocks.tx));
    mocks.tx.$queryRaw.mockResolvedValue([{ id: "owner-1" }, { id: "viewer-1" }]);
    mocks.tx.block.findFirst.mockResolvedValue({ id: "block-1" });
  });

  it("rechecks participant blocks under the same user-row locks before creating a message", async () => {
    const response = await POST(
      new NextRequest("https://example.com/game-searches/search-1/messages", {
        method: "POST",
        body: JSON.stringify({ text: "Новое сообщение" })
      }),
      { params: { id: "search-1" } }
    );

    expect(await response.clone().json()).toEqual({ error: "Нет доступа" });
    expect(response.status).toBe(403);
    expect(mocks.tx.$queryRaw).toHaveBeenCalledOnce();
    expect(mocks.tx.block.findFirst).toHaveBeenCalledWith({
      where: {
        OR: [
          { blockerUserId: "viewer-1", blockedUserId: { in: ["owner-1"] } },
          { blockedUserId: "viewer-1", blockerUserId: { in: ["owner-1"] } }
        ]
      },
      select: { id: true }
    });
    expect(mocks.tx.gameSearchMessage.create).not.toHaveBeenCalled();
  });
});
