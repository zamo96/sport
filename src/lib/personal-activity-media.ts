/** Personal report limits. Photos retain their existing 20 MiB upload limit. */
export const PERSONAL_ACTIVITY_MEDIA_LIMIT = 8;
export const PERSONAL_ACTIVITY_VIDEO_MAX_BYTES = 60 * 1024 * 1024;
export const PERSONAL_ACTIVITY_VIDEO_CONTENT_TYPES = new Set(["video/mp4", "video/quicktime"]);

export function personalActivityVideoUrls(value: unknown): string[] {
  return Array.isArray(value)
    ? Array.from(new Set(value.filter((item): item is string => typeof item === "string" && item.trim().length > 0).map((item) => item.trim())))
    : [];
}

export function validatePersonalActivityVideo(bytes: Buffer, contentType?: string) {
  if (!bytes.length) throw new Error("Файл пустой");
  if (bytes.length > PERSONAL_ACTIVITY_VIDEO_MAX_BYTES) throw new Error("Видео должно быть не больше 60 МБ");
  if (!contentType || !PERSONAL_ACTIVITY_VIDEO_CONTENT_TYPES.has(contentType)) {
    throw new Error("Поддерживаются только MP4 или MOV");
  }
  // Both supported containers exported by iOS have an ISO base media file-type box.
  // This is a format check, not a duration or codec validation promise.
  if (bytes.length < 12 || bytes.toString("ascii", 4, 8) !== "ftyp") {
    throw new Error("Не удалось прочитать видео. Выберите MP4 или MOV");
  }
}
