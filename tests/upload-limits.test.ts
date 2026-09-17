import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { writeFile } from "fs/promises";

import { IMAGE_SIZE_ERROR, MAX_IMAGE_BYTES, MAX_IMAGE_MEGABYTES } from "@/lib/upload-limits";
import { uploadAvatar, uploadCourtPhoto, uploadGameReportPhoto, uploadPersonalActivityPhoto, uploadProfileMedia } from "@/lib/uploads";

vi.mock("fs/promises", () => ({ mkdir: vi.fn().mockResolvedValue(undefined), writeFile: vi.fn().mockResolvedValue(undefined) }));

const atLimit = Buffer.alloc(MAX_IMAGE_BYTES);
const oversized = Buffer.alloc(MAX_IMAGE_BYTES + 1);
const uploadPhoto = (bytes: Buffer) => ({ bytes, originalName: "photo.jpg", contentType: "image/jpeg", userId: "user-1" });
const surfaces = [
  { name: "avatar", upload: (bytes: Buffer) => uploadAvatar(uploadPhoto(bytes)) },
  { name: "court", upload: (bytes: Buffer) => uploadCourtPhoto({ ...uploadPhoto(bytes), courtId: "court-1" }) },
  { name: "game report", upload: (bytes: Buffer) => uploadGameReportPhoto({ ...uploadPhoto(bytes), gameRequestId: "game-1" }) },
  { name: "personal activity", upload: (bytes: Buffer) => uploadPersonalActivityPhoto({ ...uploadPhoto(bytes), activityId: "activity-1" }) },
  { name: "profile photo", upload: (bytes: Buffer) => uploadProfileMedia(uploadPhoto(bytes)) }
];

beforeEach(() => { vi.stubEnv("UPLOADS_PROVIDER", "local"); vi.clearAllMocks(); });
afterEach(() => vi.unstubAllEnvs());

describe("shared photo upload limits", () => {
  it("uses a browser-safe 20 MiB constant and matching message", () => {
    expect(MAX_IMAGE_MEGABYTES).toBe(20);
    expect(MAX_IMAGE_BYTES).toBe(20 * 1024 * 1024);
    expect(IMAGE_SIZE_ERROR).toBe("Фото должно быть не больше 20 МБ");
  });

  it.each(surfaces)("accepts exactly 20 MiB for $name", async ({ upload }) => {
    await expect(upload(atLimit)).resolves.toBeTruthy();
    expect(vi.mocked(writeFile).mock.calls[0]?.[1]).toBe(atLimit);
  });

  it.each(surfaces)("rejects one extra byte before storing $name", async ({ upload }) => {
    await expect(upload(oversized)).rejects.toThrow(IMAGE_SIZE_ERROR);
    expect(writeFile).not.toHaveBeenCalled();
  });

  it("continues rejecting empty and unsupported generic photos", async () => {
    await expect(uploadAvatar(uploadPhoto(Buffer.alloc(0)))).rejects.toThrow("Файл пустой");
    await expect(uploadAvatar({ ...uploadPhoto(Buffer.from("x")), contentType: "image/heic" })).rejects.toThrow("Поддерживаются только JPG, PNG, WEBP или GIF");
    expect(writeFile).not.toHaveBeenCalled();
  });

  it("keeps the 60 MiB profile video boundary and supported formats", async () => {
    const video = { ...uploadPhoto(Buffer.alloc(60 * 1024 * 1024)), originalName: "intro.mp4", contentType: "video/mp4" };
    await expect(uploadProfileMedia(video)).resolves.toMatchObject({ mediaType: "video" });
    await expect(uploadProfileMedia({ ...video, bytes: Buffer.alloc(60 * 1024 * 1024 + 1) })).rejects.toThrow("Видео должно быть не больше 60 МБ");
    await expect(uploadProfileMedia({ ...video, contentType: "video/webm" })).rejects.toThrow("Поддерживаются только MP4, MOV или MPEG");
  });
});
