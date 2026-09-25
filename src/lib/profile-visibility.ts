import type { Prisma, ProfileVisibility } from "@prisma/client";

import { USER_AGREEMENT_VERSION } from "@/lib/legal-contract";

/**
 * Кто смотрит публичный список анкет. Гость — посетитель без входа: для него
 * нужно отдельное разрешение в согласии на показ.
 */
export type ProfileAudience = "guest" | "registered";

export type ProfileVisibilityFields = {
  profileVisibility?: ProfileVisibility | null;
  profileVisibleToGuests?: boolean | null;
  profileShowsBio?: boolean | null;
  profileShowsPhotos?: boolean | null;
  profileShowsVideos?: boolean | null;
  profileShowsSearches?: boolean | null;
};

/** Фамилия и имя (и отчество при наличии) для согласия на показ анкеты: хотя бы два слова из букв. */
export const CONSENT_FULL_NAME_PATTERN = /^[\p{L}][\p{L}'’-]*(?:\s+[\p{L}][\p{L}'’-]*)+$/u;

/**
 * Клиент с экраном согласий создаёт аккаунт скрытым до ответа; старые сборки
 * получают прежнее поведение (`legacy` по умолчанию в схеме), иначе их новые
 * пользователи остались бы невидимыми без способа это исправить.
 */
export function initialProfileVisibility(consentReview?: boolean) {
  return consentReview === true ? ("pending" as const) : undefined;
}

/** Поля, которые нужны для решения «показывать ли анкету» — добавляются в select публичных списков. */
export const profileVisibilitySelect = {
  profileVisibility: true,
  profileVisibleToGuests: true,
  profileShowsBio: true,
  profileShowsPhotos: true,
  profileShowsVideos: true,
  profileShowsSearches: true
} satisfies Prisma.UserSelect;

/**
 * Условие для публичных списков: поиск, карта, клубы, срочные поиски.
 * Не применяется к собеседникам, парам и участникам общей игры — им данные
 * предоставляются для исполнения договорённости, а не распространяются.
 *
 * Возвращает объект с единственным ключом `AND`, чтобы его можно было
 * безопасно раскрыть рядом с другими условиями на `User`.
 */
export function publicProfileWhere(
  audience: ProfileAudience,
  options: { requireSearches?: boolean } = {}
): Prisma.UserWhereInput {
  return {
    AND: [
      {
        OR: [
          { profileVisibility: "legacy" },
          {
            profileVisibility: "visible",
            ...(audience === "guest" ? { profileVisibleToGuests: true } : {}),
            ...(options.requireSearches ? { profileShowsSearches: true } : {})
          }
        ]
      }
    ]
  };
}

export function isPubliclyVisible(user: ProfileVisibilityFields, audience: ProfileAudience, options: { requireSearches?: boolean } = {}) {
  const state = user.profileVisibility ?? "legacy";
  if (state === "legacy") return true;
  if (state !== "visible") return false;
  if (audience === "guest" && user.profileVisibleToGuests !== true) return false;
  if (options.requireSearches && user.profileShowsSearches !== true) return false;
  return true;
}

type RedactablePreview = {
  bio?: string | null;
  avatarUrl?: string | null;
  profilePhotoUrls?: string[];
  profileVideoUrls?: string[];
  profileMediaOrder?: string[];
  gameSearches?: unknown;
};

/**
 * Убирает из публичной карточки то, что человек не разрешил показывать.
 * Аккаунты `legacy` показываются как раньше, пока владелец не ответит.
 */
export function redactPublicPreview<T extends RedactablePreview>(preview: T, user: ProfileVisibilityFields): T {
  if ((user.profileVisibility ?? "legacy") === "legacy") return preview;

  const showsPhotos = user.profileShowsPhotos === true;
  const showsVideos = user.profileShowsVideos === true;
  const photoUrls = showsPhotos ? preview.profilePhotoUrls ?? [] : [];
  const videoUrls = showsVideos ? preview.profileVideoUrls ?? [] : [];
  const allowedMedia = new Set([...photoUrls, ...videoUrls]);

  return {
    ...preview,
    bio: user.profileShowsBio === true ? preview.bio : null,
    avatarUrl: showsPhotos ? preview.avatarUrl : null,
    profilePhotoUrls: photoUrls,
    profileVideoUrls: videoUrls,
    profileMediaOrder: (preview.profileMediaOrder ?? []).filter((url) => allowedMedia.has(url)),
    ...("gameSearches" in preview ? { gameSearches: user.profileShowsSearches === true ? preview.gameSearches : [] } : {})
  };
}

type RedactableUserRecord = ProfileVisibilityFields & {
  bio?: string | null;
  avatarUrl?: string | null;
  profilePhotoUrls?: unknown;
  profileVideoUrls?: unknown;
  profileMediaOrder?: unknown;
  gameSearches?: unknown;
};

function stringList(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

/**
 * То же, что `redactPublicPreview`, но для записи из базы — для экранов,
 * которые строят карточку прямо из полей пользователя (web-поиск).
 */
export function redactPublicUserRecord<T extends RedactableUserRecord>(record: T): T {
  if ((record.profileVisibility ?? "legacy") === "legacy") return record;
  const redacted = redactPublicPreview(
    {
      bio: record.bio ?? null,
      avatarUrl: record.avatarUrl ?? null,
      profilePhotoUrls: stringList(record.profilePhotoUrls),
      profileVideoUrls: stringList(record.profileVideoUrls),
      profileMediaOrder: stringList(record.profileMediaOrder),
      ...("gameSearches" in record ? { gameSearches: record.gameSearches } : {})
    },
    record
  );
  return { ...record, ...redacted } as T;
}

export type ConsentState = {
  profileVisibility: ProfileVisibility;
  visibleToGuests: boolean;
  showsBio: boolean;
  showsPhotos: boolean;
  showsVideos: boolean;
  showsSearches: boolean;
  analytics: boolean;
  /**
   * ФИО из данного согласия, а до первого согласия — имя из анкеты, чтобы
   * человеку не вписывать его заново: клиент подставляет это значение в поле.
   */
  fullName: string | null;
  agreementVersion: string | null;
  currentAgreementVersion: string;
  termsUpdateRequired: boolean;
  /** Показать экран согласий: после онбординга, пока нет ответа или не принята новая редакция. */
  reviewRequired: boolean;
};

export function buildConsentState(
  user: ProfileVisibilityFields & {
    name?: string | null;
    analyticsConsent?: boolean | null;
    consentFullName?: string | null;
    agreementVersion?: string | null;
  }
): ConsentState {
  const profileVisibility = user.profileVisibility ?? "legacy";
  const termsUpdateRequired = user.agreementVersion !== USER_AGREEMENT_VERSION;
  const profileName = user.name?.trim().replace(/\s+/g, " ") || null;
  return {
    profileVisibility,
    visibleToGuests: user.profileVisibleToGuests === true,
    showsBio: user.profileShowsBio === true,
    showsPhotos: user.profileShowsPhotos === true,
    showsVideos: user.profileShowsVideos === true,
    showsSearches: user.profileShowsSearches === true,
    analytics: user.analyticsConsent === true,
    fullName: user.consentFullName ?? profileName,
    agreementVersion: user.agreementVersion ?? null,
    currentAgreementVersion: USER_AGREEMENT_VERSION,
    termsUpdateRequired,
    reviewRequired: termsUpdateRequired || profileVisibility === "legacy" || profileVisibility === "pending"
  };
}
