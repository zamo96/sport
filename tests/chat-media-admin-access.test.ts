import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  requireSessionUser: vi.fn(),
  isAdminUser: vi.fn(),
  findAsset: vi.fn(),
  readChatImage: vi.fn()
}));

vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.requireSessionUser }));
vi.mock("@/lib/admin", () => ({ isAdminUser: mocks.isAdminUser }));
vi.mock("@/lib/prisma", () => ({ prisma: { chatMediaAsset: { findUnique: mocks.findAsset } } }));
vi.mock("@/server/chat-media", () => ({ readChatImage: mocks.readChatImage }));

import { GET } from "@/app/chat-media/[id]/route";

const asset = {
  id: "asset-1",
  uploaderUserId: "uploader-1",
  storageKey: "chat-media/evidence.jpg",
  mimeType: "image/jpeg",
  byteSize: 3,
  chatMessageMedia: null,
  searchMessageMedia: null
};

describe("moderation evidence media access", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.requireSessionUser.mockResolvedValue({ id: "moderator-1", email: "admin@example.com" });
    mocks.findAsset.mockResolvedValue(asset);
    mocks.readChatImage.mockResolvedValue(Buffer.from([1, 2, 3]));
  });

  it("allows an authenticated configured administrator to inspect evidence", async () => {
    mocks.isAdminUser.mockReturnValue(true);
    const response = await GET(new Request("https://example.com/chat-media/asset-1"), { params: { id: "asset-1" } });
    expect(response.status).toBe(200);
    expect(mocks.readChatImage).toHaveBeenCalledWith(asset.storageKey);
  });

  it("continues to deny an ordinary nonparticipant", async () => {
    mocks.isAdminUser.mockReturnValue(false);
    const response = await GET(new Request("https://example.com/chat-media/asset-1"), { params: { id: "asset-1" } });
    expect(response.status).toBe(403);
    expect(mocks.readChatImage).not.toHaveBeenCalled();
  });
});
