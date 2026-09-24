import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ user: vi.fn(), find: vi.fn(), update: vi.fn(), deletePhotos: vi.fn(), createPhotos: vi.fn(), uploadPhoto: vi.fn(), uploadVideo: vi.fn() }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.user }));
vi.mock("@/lib/prisma", () => ({ prisma: {
  personalActivity: { findFirst: mocks.find },
  $transaction: (run: (tx: unknown) => unknown) => run({
    personalActivity: { update: mocks.update },
    personalActivityPhoto: { deleteMany: mocks.deletePhotos, createMany: mocks.createPhotos }
  })
} }));
vi.mock("@/server/serializers", () => ({ serializePersonalActivity: (value: unknown) => value }));
vi.mock("@/lib/uploads", async (importOriginal) => ({
  ...await importOriginal<typeof import("@/lib/uploads")>(),
  uploadPersonalActivityPhoto: mocks.uploadPhoto,
  uploadPersonalActivityVideo: mocks.uploadVideo
}));
import { PATCH } from "@/app/personal-activities/[id]/route";
import { POST } from "@/app/uploads/personal-activities/[id]/route";

const past = new Date("2020-01-01T12:00:00Z");
const existing = { id: "a", userId: "owner", status: "completed", scheduledAt: past, durationMinutes: 60, updatedAt: past, photos: [{ url: "/photo.jpg" }], videoUrls: ["/uploads/personal-activities/a/owner/abc-123.mp4"] };
const context = { params: { id: "a" } };
const patch = (body: object) => PATCH(new Request("http://app/personal-activities/a", { method: "PATCH", body: JSON.stringify(body) }), context);
function upload(type: string, name: string) {
  const body = new FormData(); body.append("file", new Blob(["fixture"], { type }), name);
  return POST(new Request("http://app/uploads/personal-activities/a", { method: "POST", body }), context);
}
beforeEach(() => {
  vi.resetAllMocks(); vi.stubEnv("UPLOADS_PROVIDER", "local");
  mocks.user.mockResolvedValue({ id: "owner" }); mocks.find.mockResolvedValue(existing);
  mocks.update.mockResolvedValue(existing); mocks.uploadVideo.mockResolvedValue("/video.mp4"); mocks.uploadPhoto.mockResolvedValue("/photo.jpg");
});
afterEach(() => vi.unstubAllEnvs());

describe("personal activity route compatibility and ownership", () => {
  it("requires the owner for reads before report mutations and uploads", async () => {
    mocks.find.mockResolvedValue(null);
    expect((await patch({ status: "completed" })).status).toBe(404);
    expect((await upload("video/mp4", "v.mp4")).status).toBe(404);
    expect(mocks.find).toHaveBeenCalledWith(expect.objectContaining({ where: { id: "a", userId: "owner" } }));
    expect(mocks.update).not.toHaveBeenCalled(); expect(mocks.uploadVideo).not.toHaveBeenCalled();
  });
  it("does not mutate or upload without an authenticated session", async () => {
    mocks.user.mockRejectedValue(new Error("UNAUTHORIZED"));
    expect((await patch({ status: "completed" })).status).toBe(401);
    expect((await upload("video/mp4", "v.mp4")).status).toBe(401);
    expect(mocks.find).not.toHaveBeenCalled();
  });
  it("preserves both omitted media lists and checks the original version when editing notes", async () => {
    expect((await patch({ reportComment: "Changed note" })).status).toBe(200);
    expect(mocks.deletePhotos).not.toHaveBeenCalled();
    expect(mocks.update.mock.calls[0][0]).toMatchObject({ where: { id: "a", userId: "owner", updatedAt: past } });
    expect(mocks.update.mock.calls[0][0].data.videoUrls).toBeUndefined();
  });
  it("explicitly clears photos without clearing videos, and videos without touching photos", async () => {
    expect((await patch({ photoUrls: [] })).status).toBe(200);
    expect(mocks.deletePhotos).toHaveBeenCalledOnce();
    expect(mocks.update.mock.calls[0][0].data.videoUrls).toBeUndefined();
    mocks.deletePhotos.mockClear();
    expect((await patch({ videoUrls: [] })).status).toBe(200);
    expect(mocks.deletePhotos).not.toHaveBeenCalled();
    expect(mocks.update.mock.calls[1][0].data.videoUrls).toEqual([]);
  });
  it("rejects another visit's or owner's video URL before any mutation", async () => {
    expect((await patch({ videoUrls: ["/uploads/personal-activities/b/owner/abc.mp4"] })).status).toBe(400);
    expect((await patch({ videoUrls: ["/uploads/personal-activities/a/other/abc.mp4"] })).status).toBe(400);
    expect(mocks.update).not.toHaveBeenCalled(); expect(mocks.deletePhotos).not.toHaveBeenCalled();
  });
  it("accepts and returns new video uploads without completing or replacing an existing report", async () => {
    const response = await upload("video/mp4", "v.mp4");
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ videoUrl: "/video.mp4" });
    expect(mocks.uploadVideo).toHaveBeenCalledWith(expect.objectContaining({ activityId: "a", userId: "owner", contentType: "video/mp4" }));
    expect(mocks.update).not.toHaveBeenCalled(); expect(mocks.deletePhotos).not.toHaveBeenCalled();
  });
  it("retains the owner's saved video after a storage/CDN configuration change", async () => {
    const oldUrl = "https://old-media.example/retained.mp4";
    mocks.find.mockResolvedValue({ ...existing, videoUrls: [oldUrl] });
    expect((await patch({ videoUrls: [oldUrl], reportComment: "Keep video" })).status).toBe(200);
    expect((await patch({ videoUrls: [oldUrl, "https://old-media.example/foreign.mp4"] })).status).toBe(400);
  });
  it("keeps the photo upload response backward compatible", async () => {
    const response = await upload("image/jpeg", "p.jpg");
    expect(await response.json()).toEqual({ photoUrl: "/photo.jpg" });
    expect(mocks.uploadVideo).not.toHaveBeenCalled();
  });
  it("does not upload to canceled or future visits", async () => {
    mocks.find.mockResolvedValue({ ...existing, status: "canceled" });
    expect((await upload("video/mp4", "v.mp4")).status).toBe(400);
    mocks.find.mockResolvedValue({ ...existing, status: "planned", scheduledAt: new Date(Date.now() + 3_600_000) });
    expect((await upload("image/jpeg", "p.jpg")).status).toBe(400);
    expect(mocks.uploadVideo).not.toHaveBeenCalled(); expect(mocks.uploadPhoto).not.toHaveBeenCalled();
  });
  it("failed uploads do not touch the saved report", async () => {
    mocks.uploadVideo.mockRejectedValue(new Error("Storage unavailable"));
    expect((await upload("video/mp4", "v.mp4")).status).toBe(400);
    expect(mocks.update).not.toHaveBeenCalled(); expect(mocks.deletePhotos).not.toHaveBeenCalled();
  });
});
