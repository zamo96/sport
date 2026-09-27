import { mkdir, mkdtemp, rm, writeFile } from "fs/promises";
import { tmpdir } from "os";
import path from "path";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  assetFindMany: vi.fn(),
  assetDeleteMany: vi.fn(),
  listStoredChatImages: vi.fn(),
  removeStoredChatImage: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: { chatMediaAsset: { findMany: mocks.assetFindMany, deleteMany: mocks.assetDeleteMany } }
}));
vi.mock("@/server/chat-media", () => ({
  listStoredChatImages: mocks.listStoredChatImages,
  removeStoredChatImage: mocks.removeStoredChatImage
}));

import { removeUnusedChatMedia } from "@/server/chat-media-cleanup";

const now = new Date("2026-09-27T12:00:00.000Z");
const minutesAgo = (minutes: number) => new Date(now.getTime() - minutes * 60_000);

describe("chat photo cleanup", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.listStoredChatImages.mockResolvedValue([]);
    mocks.assetFindMany.mockResolvedValue([]);
  });

  it("removes photos whose messages are gone, and their rows", async () => {
    mocks.assetFindMany.mockResolvedValueOnce([
      { id: "a1", storageKey: "chat-media/u1/one.jpg" },
      { id: "a2", storageKey: "chat-media/u2/two.jpg" }
    ]);

    const result = await removeUnusedChatMedia(now);

    const where = mocks.assetFindMany.mock.calls[0][0].where;
    expect(where.OR).toEqual([
      { claimedAt: null, createdAt: { lt: minutesAgo(24 * 60) } },
      { claimedAt: { not: null }, chatMessageMedia: null, searchMessageMedia: null }
    ]);
    expect(mocks.removeStoredChatImage).toHaveBeenCalledWith("chat-media/u1/one.jpg");
    expect(mocks.removeStoredChatImage).toHaveBeenCalledWith("chat-media/u2/two.jpg");
    expect(mocks.assetDeleteMany).toHaveBeenCalledWith({ where: { id: { in: ["a1", "a2"] } } });
    expect(result).toEqual({ unusedAssets: 2, untrackedFiles: 0 });
  });

  it("removes files the database no longer knows, but not fresh uploads or known photos", async () => {
    mocks.listStoredChatImages.mockResolvedValue([
      { storageKey: "chat-media/deleted-user/old.jpg", storedAt: minutesAgo(3 * 24 * 60) },
      { storageKey: "chat-media/u1/kept.jpg", storedAt: minutesAgo(3 * 24 * 60) },
      { storageKey: "chat-media/u1/uploading.jpg", storedAt: minutesAgo(5) }
    ]);
    mocks.assetFindMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([{ storageKey: "chat-media/u1/kept.jpg" }]);

    const result = await removeUnusedChatMedia(now);

    expect(mocks.assetFindMany.mock.calls[1][0].where.storageKey.in).toEqual([
      "chat-media/deleted-user/old.jpg",
      "chat-media/u1/kept.jpg"
    ]);
    expect(mocks.removeStoredChatImage).toHaveBeenCalledOnce();
    expect(mocks.removeStoredChatImage).toHaveBeenCalledWith("chat-media/deleted-user/old.jpg");
    expect(mocks.assetDeleteMany).not.toHaveBeenCalled();
    expect(result).toEqual({ unusedAssets: 0, untrackedFiles: 1 });
  });
});

describe("listing stored chat photos on local disk", () => {
  it("returns every file under chat-media with its storage key", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "chat-media-"));
    await mkdir(path.join(root, "user-1"), { recursive: true });
    await writeFile(path.join(root, "user-1", "photo.jpg"), "x");
    vi.stubEnv("UPLOADS_PROVIDER", "local");
    vi.stubEnv("CHAT_MEDIA_LOCAL_DIR", root);

    try {
      const actual = await vi.importActual<typeof import("@/server/chat-media")>("@/server/chat-media");
      const files = await actual.listStoredChatImages();

      expect(files.map((file) => file.storageKey)).toEqual(["chat-media/user-1/photo.jpg"]);
      expect(files[0].storedAt).toBeInstanceOf(Date);
    } finally {
      vi.unstubAllEnvs();
      await rm(root, { recursive: true, force: true });
    }
  });
});
