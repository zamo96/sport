export const PROFILE_PHOTO_LIMIT = 6;
export const PROFILE_VIDEO_LIMIT = 4;
/** Аватар может не входить в список фото, поэтому на одну позицию больше. */
export const PROFILE_MEDIA_ORDER_LIMIT = PROFILE_PHOTO_LIMIT + PROFILE_VIDEO_LIMIT + 1;

export type ProfileMediaType = "photo" | "video";

export type ProfileMediaState = {
  avatarUrl: string | null;
  profilePhotoUrls: string[];
  profileVideoUrls: string[];
};

export type ProfileMediaRemovalResult = ProfileMediaState & {
  mediaUrl: string;
  mediaType: ProfileMediaType;
  removed: boolean;
};

export function normalizeProfileMediaList(value: unknown, limit: number) {
  return Array.from(
    new Set(
      (Array.isArray(value) ? value : [])
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean)
    )
  ).slice(0, limit);
}

/**
 * Оставляет в порядке только медиа, которое сейчас есть в профиле: ссылка на
 * удалённое или чужое видео не должна всплыть в карточке. Всё, чего в порядке
 * нет, клиенты показывают следом в прежнем порядке «фото, потом видео».
 */
export function sanitizeProfileMediaOrder(
  order: unknown,
  state: { avatarUrl: string | null; profilePhotoUrls: unknown; profileVideoUrls: unknown }
) {
  const known = new Set([
    ...normalizeProfileMediaList(state.profilePhotoUrls, PROFILE_PHOTO_LIMIT),
    ...normalizeProfileMediaList(state.profileVideoUrls, PROFILE_VIDEO_LIMIT),
    ...(state.avatarUrl?.trim() ? [state.avatarUrl.trim()] : [])
  ]);

  return normalizeProfileMediaList(order, PROFILE_MEDIA_ORDER_LIMIT).filter((url) => known.has(url));
}

export function removeProfileMedia(
  state: { avatarUrl: string | null; profilePhotoUrls: unknown; profileVideoUrls: unknown },
  requestedMediaUrl: string
): ProfileMediaRemovalResult {
  const mediaUrl = requestedMediaUrl.trim();
  const currentPhotoUrls = normalizeProfileMediaList(state.profilePhotoUrls, PROFILE_PHOTO_LIMIT);
  const currentVideoUrls = normalizeProfileMediaList(state.profileVideoUrls, PROFILE_VIDEO_LIMIT);
  const isPhoto = currentPhotoUrls.includes(mediaUrl);
  const isVideo = currentVideoUrls.includes(mediaUrl);
  const profilePhotoUrls = isPhoto ? currentPhotoUrls.filter((url) => url !== mediaUrl) : currentPhotoUrls;
  const profileVideoUrls = isVideo ? currentVideoUrls.filter((url) => url !== mediaUrl) : currentVideoUrls;

  return {
    mediaUrl,
    mediaType: isPhoto ? "photo" : isVideo ? "video" : inferProfileMediaType(mediaUrl),
    removed: isPhoto || isVideo,
    avatarUrl: isPhoto && state.avatarUrl?.trim() === mediaUrl ? profilePhotoUrls[0] ?? null : state.avatarUrl,
    profilePhotoUrls,
    profileVideoUrls
  };
}

function inferProfileMediaType(mediaUrl: string): ProfileMediaType {
  const pathname = mediaUrl.split(/[?#]/, 1)[0]?.toLowerCase() ?? "";
  return /\.(?:mp4|mov|mpeg|mpg)$/.test(pathname) ? "video" : "photo";
}
