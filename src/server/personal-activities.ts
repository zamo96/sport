import { PERSONAL_ACTIVITY_MEDIA_LIMIT, personalActivityVideoUrls } from "@/lib/personal-activity-media";

type ActivityState = {
  scheduledAt: Date;
  durationMinutes: number | null;
  status: string;
  photos?: { url: string }[];
  videoUrls?: unknown;
};

type ActivityUpdate = {
  scheduledAt?: string;
  durationMinutes?: number | null;
  status?: string;
  reportComment?: string | null;
  photoUrls?: string[];
  videoUrls?: string[];
};

export function assertPersonalActivityReportAvailable(activity: ActivityState, now = new Date()) {
  if (activity.status === "canceled") throw new Error("Нельзя добавить отчёт к отменённому визиту");
  if (now.getTime() < activity.scheduledAt.getTime() + (activity.durationMinutes ?? 60) * 60_000) {
    throw new Error("Отчёт можно добавить после завершения визита");
  }
}

/** Omitted media lists preserve existing attachments; explicit [] removes that media kind. */
export function validatePersonalActivityUpdate(existing: ActivityState, body: ActivityUpdate, now = new Date()) {
  const nextStatus = body.status ?? existing.status;
  const nextScheduledAt = body.scheduledAt ? new Date(body.scheduledAt) : existing.scheduledAt;
  const nextDurationMinutes = body.durationMinutes === undefined ? existing.durationMinutes : body.durationMinutes;
  const editsReport = body.reportComment !== undefined || body.photoUrls !== undefined || body.videoUrls !== undefined;

  if (body.scheduledAt && nextScheduledAt.getTime() <= now.getTime()) {
    throw new Error("Выбери будущую дату и время");
  }
  if (existing.status !== "planned" && (body.scheduledAt !== undefined || body.durationMinutes !== undefined)) {
    throw new Error("Изменить план можно только до отметки результата");
  }
  if (existing.status !== "planned" && nextStatus !== existing.status) {
    throw new Error("Результат визита уже сохранён");
  }
  if (editsReport && nextStatus !== "completed") {
    throw new Error("Отчёт можно сохранить только для завершённого визита");
  }
  if (nextStatus === "completed" && (body.status === "completed" || editsReport)) {
    assertPersonalActivityReportAvailable({ ...existing, scheduledAt: nextScheduledAt, durationMinutes: nextDurationMinutes }, now);
  }

  const photos = body.photoUrls ?? existing.photos?.map((photo) => photo.url) ?? [];
  const videos = body.videoUrls ?? personalActivityVideoUrls(existing.videoUrls);
  if (photos.length + videos.length > PERSONAL_ACTIVITY_MEDIA_LIMIT) {
    throw new Error(`В отчёте может быть не больше ${PERSONAL_ACTIVITY_MEDIA_LIMIT} фото и видео`);
  }
}
