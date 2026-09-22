import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  session: vi.fn(),
  findUnique: vi.fn(),
  update: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({ prisma: {} }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.session }));
vi.mock("@/lib/uploads", () => ({ uploadProfileMedia: vi.fn() }));
vi.mock("@/lib/prisma-transaction", () => ({
  withSerializableTransactionRetry: (run: (tx: unknown) => unknown) =>
    run({ user: { findUnique: mocks.findUnique, update: mocks.update } })
}));

import { PATCH } from "@/app/uploads/profile-media/route";
import { sanitizeProfileMediaOrder } from "@/lib/profile-media";
import { serializeUserPreview } from "@/server/serializers";

const avatar = "https://cdn.test/avatar.jpg";
const photo = "https://cdn.test/photo.jpg";
const video = "https://cdn.test/clip.mp4";
const state = { avatarUrl: avatar, profilePhotoUrls: [avatar, photo], profileVideoUrls: [video] };

const patch = (body: unknown) =>
  PATCH(new Request("http://localhost/uploads/profile-media", { method: "PATCH", body: JSON.stringify(body) }));

beforeEach(() => {
  vi.resetAllMocks();
  mocks.session.mockResolvedValue({ id: "user-1" });
  mocks.findUnique.mockResolvedValue({ ...state, profileMediaOrder: null });
  mocks.update.mockImplementation(async ({ data }: { data: Record<string, unknown> }) => ({ ...state, ...data }));
});

describe("profile media order", () => {
  it("keeps only media that is still in the profile", () => {
    expect(sanitizeProfileMediaOrder([video, "https://cdn.test/deleted.mp4", photo, video, " "], state)).toEqual([
      video,
      photo
    ]);
  });

  it("saves a mixed order and returns it with the media lists", async () => {
    const response = await patch({ order: [video, photo, avatar] });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(mocks.update.mock.calls[0][0].data).toEqual({ profileMediaOrder: [video, photo, avatar] });
    expect(body.profileMediaOrder).toEqual([video, photo, avatar]);
    expect(body.profileVideoUrls).toEqual([video]);
  });

  it("drops someone else's URL instead of putting it into the card", async () => {
    await patch({ order: ["https://cdn.test/someone-else.jpg", video] });

    expect(mocks.update.mock.calls[0][0].data).toEqual({ profileMediaOrder: [video] });
  });

  it.each([{ order: "nope" }, { order: [video], extra: true }, null])("rejects a malformed body %j", async (body) => {
    expect((await patch(body)).status).toBe(400);
    expect(mocks.update).not.toHaveBeenCalled();
  });

  it("serializes the stored order and falls back to empty for old rows", () => {
    expect(serializeUserPreview({ id: "user-1", profileMediaOrder: [video, " ", 42, photo] as unknown as string[] }).profileMediaOrder)
      .toEqual([video, photo]);
    expect(serializeUserPreview({ id: "user-1", profileMediaOrder: null }).profileMediaOrder).toEqual([]);
  });
});
