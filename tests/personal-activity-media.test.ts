import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { writeFile } from "fs/promises";
import { PERSONAL_ACTIVITY_VIDEO_MAX_BYTES, personalActivityVideoUrls, validatePersonalActivityVideo } from "@/lib/personal-activity-media";
import { isOwnedPersonalActivityVideoUrl, uploadPersonalActivityVideo } from "@/lib/uploads";
import { updatePersonalActivitySchema } from "@/lib/validators";
import { assertPersonalActivityReportAvailable, validatePersonalActivityUpdate } from "@/server/personal-activities";
import { serializePersonalActivity } from "@/server/serializers";

vi.mock("fs/promises", () => ({ mkdir: vi.fn().mockResolvedValue(undefined), writeFile: vi.fn().mockResolvedValue(undefined) }));

const now = new Date("2026-09-21T15:00:00Z");
const ended = { scheduledAt: new Date("2026-09-21T12:00:00Z"), durationMinutes: 60, status: "planned", photos: [{ url: "/photo.jpg" }], videoUrls: ["/video.mp4"] };
function videoBytes(size = 32) {
  const bytes = Buffer.alloc(size);
  bytes.write("ftyp", 4); bytes.write("isom", 8);
  return bytes;
}

beforeEach(() => { vi.stubEnv("UPLOADS_PROVIDER", "local"); vi.clearAllMocks(); });
afterEach(() => vi.unstubAllEnvs());

describe("personal report lifecycle and media", () => {
  it("completes ended plans with no media and permits notes-only edits", () => {
    expect(() => validatePersonalActivityUpdate(ended, { status: "completed" }, now)).not.toThrow();
    expect(() => validatePersonalActivityUpdate({ ...ended, status: "completed" }, { reportComment: "Updated note" }, now)).not.toThrow();
  });
  it("does not confuse passed time with permission to edit canceled or future visits", () => {
    expect(() => assertPersonalActivityReportAvailable({ ...ended, status: "canceled" }, now)).toThrow("отменённому");
    expect(() => validatePersonalActivityUpdate({ ...ended, status: "canceled" }, { status: "completed" }, now)).toThrow();
    expect(() => validatePersonalActivityUpdate({ ...ended, scheduledAt: now }, { status: "completed" }, now)).toThrow("после завершения");
    expect(() => validatePersonalActivityUpdate(ended, { reportComment: "Unfinished" }, now)).toThrow("завершённого");
  });
  it("checks the exact ending boundary using the server's 60-minute fallback", () => {
    const activity = { ...ended, durationMinutes: null, scheduledAt: new Date(now.getTime() - 3_600_000) };
    expect(() => assertPersonalActivityReportAvailable(activity, now)).not.toThrow();
    expect(() => assertPersonalActivityReportAvailable(activity, new Date(now.getTime() - 1))).toThrow();
  });
  it("does not allow creating a past record through update or reopening a saved result", () => {
    expect(() => validatePersonalActivityUpdate(ended, { scheduledAt: ended.scheduledAt.toISOString(), status: "completed" }, now)).toThrow("будущую");
    expect(() => validatePersonalActivityUpdate({ ...ended, status: "completed" }, { status: "planned" }, now)).toThrow();
    expect(() => validatePersonalActivityUpdate({ ...ended, status: "completed" }, { durationMinutes: 90 }, now)).toThrow();
  });
  it("counts existing attachments when one media field is omitted and allows explicit removal", () => {
    const full = { ...ended, status: "completed", photos: Array.from({ length: 7 }, (_, i) => ({ url: `/photo${i}.jpg` })) };
    expect(() => validatePersonalActivityUpdate(full, { videoUrls: ["/1.mp4"] }, now)).not.toThrow();
    expect(() => validatePersonalActivityUpdate(full, { videoUrls: ["/1.mp4", "/2.mp4"] }, now)).toThrow("8 фото и видео");
    expect(() => validatePersonalActivityUpdate(full, { photoUrls: [], videoUrls: ["/1.mp4", "/2.mp4"] }, now)).not.toThrow();
    expect(() => validatePersonalActivityUpdate({ ...full, videoUrls: Array(8).fill("/v.mp4") }, { photoUrls: [] }, now)).not.toThrow();
  });
  it("keeps old PATCH payloads valid and distinguishes absent and empty video lists", () => {
    expect(updatePersonalActivitySchema.parse({ reportComment: "note" }).videoUrls).toBeUndefined();
    expect(updatePersonalActivitySchema.parse({ videoUrls: [] }).videoUrls).toEqual([]);
    expect(updatePersonalActivitySchema.safeParse({ videoUrls: Array(9).fill("/v.mp4") }).success).toBe(false);
    expect(updatePersonalActivitySchema.safeParse({ videoUrls: null }).success).toBe(false);
  });
  it("serializes legacy absent video state and new ordered videos without changing photos", () => {
    const activity = { ...ended, id: "a", userId: "u", courtId: "c", sport: "tennis", reportComment: null, comment: null, createdAt: now, updatedAt: now, photos: [{ id: "p", url: "/p.jpg", position: 0 }] };
    const legacy = serializePersonalActivity({ ...activity, videoUrls: undefined } as never);
    expect(legacy.videoUrls).toEqual([]); expect(legacy.photos.map((photo) => photo.url)).toEqual(["/p.jpg"]);
    expect(serializePersonalActivity({ ...activity, videoUrls: ["/b.mp4", "/a.mov"] } as never).videoUrls).toEqual(["/b.mp4", "/a.mov"]);
    expect(personalActivityVideoUrls([" /b.mp4 ", "/b.mp4", null, ""])).toEqual(["/b.mp4"]);
  });
});

describe("personal video uploads", () => {
  it("accepts MP4/MOV up to exactly 60 MiB and rejects unsupported MIME or empty/corrupt content", () => {
    expect(() => validatePersonalActivityVideo(videoBytes(PERSONAL_ACTIVITY_VIDEO_MAX_BYTES), "video/mp4")).not.toThrow();
    expect(() => validatePersonalActivityVideo(videoBytes(), "video/quicktime")).not.toThrow();
    expect(() => validatePersonalActivityVideo(videoBytes(PERSONAL_ACTIVITY_VIDEO_MAX_BYTES + 1), "video/mp4")).toThrow("60 МБ");
    expect(() => validatePersonalActivityVideo(videoBytes(), "video/webm")).toThrow("MP4 или MOV");
    expect(() => validatePersonalActivityVideo(Buffer.alloc(0), "video/mp4")).toThrow("пустой");
    expect(() => validatePersonalActivityVideo(Buffer.from("not a video file"), "video/mp4")).toThrow("прочитать");
  });
  it("writes visit-scoped URLs and ignores a misleading source filename extension", async () => {
    const url = await uploadPersonalActivityVideo({ bytes: videoBytes(), originalName: "image.jpg", contentType: "video/mp4", activityId: "a", userId: "u" });
    expect(url).toMatch(/^\/uploads\/personal-activities\/a\/u\/[a-f0-9-]+\.mp4$/);
    expect(writeFile).toHaveBeenCalledOnce();
    expect(isOwnedPersonalActivityVideoUrl(url, "a", "u")).toBe(true);
    expect(isOwnedPersonalActivityVideoUrl(url, "b", "u")).toBe(false);
    expect(isOwnedPersonalActivityVideoUrl(url, "a", "other")).toBe(false);
    expect(isOwnedPersonalActivityVideoUrl(`${url}?redirect=1`, "a", "u")).toBe(false);
    expect(isOwnedPersonalActivityVideoUrl(`https://attacker.example${url}`, "a", "u")).toBe(false);
  });
  it("does not store oversized or unsupported files", async () => {
    await expect(uploadPersonalActivityVideo({ bytes: videoBytes(), originalName: "v.webm", contentType: "video/webm", activityId: "a", userId: "u" })).rejects.toThrow();
    expect(writeFile).not.toHaveBeenCalled();
  });
  it("recognizes only the configured S3 URL prefix for the exact owner and activity", () => {
    vi.stubEnv("UPLOADS_PROVIDER", "s3"); vi.stubEnv("S3_BUCKET", "media");
    vi.stubEnv("S3_PUBLIC_BASE_URL", "https://media.example/app");
    const url = "https://media.example/app/personal-activities/a/u/abc-123.mov";
    expect(isOwnedPersonalActivityVideoUrl(url, "a", "u")).toBe(true);
    expect(isOwnedPersonalActivityVideoUrl(url.replace("media.example", "other.example"), "a", "u")).toBe(false);
  });
});
