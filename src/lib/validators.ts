import {
  AccountStatus,
  CourtSetting,
  CourtStatus,
  ContentReportReason,
  ContentReportStatus,
  GameRequestOutcome,
  GameReportConfirmationStatus,
  GameReportVisibility,
  Gender,
  GameRequestStatus,
  GameSearchResponseStatus,
  GameSearchType,
  HotSearchWindow,
  PersonalActivityStatus,
  PlayFormat,
  Sport,
  Surface,
  SwipeAction
} from "@prisma/client";
import { z } from "zod";

import { AVAILABLE_CITIES, DAY_OPTIONS, DISTRICT_OPTIONS, SPORT_OPTIONS, TIME_RANGE_OPTIONS } from "@/lib/constants";
import { CONTENT_MODERATION_VALIDATION_MESSAGE, isPublicTextAllowed } from "@/lib/content-moderation";
import { ACCEPTED_USER_AGREEMENT_VERSIONS, LEGAL_ACCEPTANCE_ERROR, USER_AGREEMENT_VERSION } from "@/lib/legal-contract";
import { normalizeSupportedLocale } from "@/lib/locales";
import { normalizeRussianMobile } from "@/lib/phone";
import { CONSENT_FULL_NAME_PATTERN } from "@/lib/profile-visibility";
import { isFormatAllowedForSport } from "@/lib/sport-playbook";
import { CLIENT_REPORTABLE_EVENT_TYPES } from "@/lib/user-events";

const dayEnum = z.enum(DAY_OPTIONS);
const cityEnum = z.enum(AVAILABLE_CITIES);
const timeRangeEnum = z.enum(TIME_RANGE_OPTIONS);
const exactTimeSlotSchema = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Укажи время в формате ЧЧ:ММ");
const pairedTimeSlotSchema = z
  .string()
  .regex(/^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)@([01]\d|2[0-3]):[0-5]\d$/, "Укажи день и время в формате day@ЧЧ:ММ");
const timePreferenceSchema = z.union([timeRangeEnum, exactTimeSlotSchema, pairedTimeSlotSchema]);
const publicText = (maximum: number) =>
  z.string().trim().max(maximum).refine(isPublicTextAllowed, CONTENT_MODERATION_VALIDATION_MESSAGE);

function isFutureDateTime(value: string) {
  return new Date(value).getTime() > Date.now();
}
const sportLevelValueSchema = z.union([z.number().int().min(1).max(10), z.null()]);

function parseMultiValue(value: unknown) {
  if (Array.isArray(value)) {
    return value
      .flatMap((item) => (typeof item === "string" ? item.split(",") : []))
      .map((item) => item.trim())
      .filter(Boolean);
  }

  if (typeof value === "string") {
    return value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  return [];
}

function parseSportLevelsValue(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  return value;
}

function parseOptionalText(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}

function parseAvailabilityByDayValue(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  return value;
}

const userAgreementAcceptanceSchema = z.object({
  accepted: z.boolean().refine((value) => value, LEGAL_ACCEPTANCE_ERROR),
  version: z
    .preprocess(
      (value) => (typeof value === "string" ? value.trim() : ""),
      z.enum(ACCEPTED_USER_AGREEMENT_VERSIONS, "Нужно принять актуальную редакцию пользовательского соглашения")
    )
});

export const requestLinkSchema = z.object({
  email: z.string().email().transform((value) => value.toLowerCase()),
  userAgreement: userAgreementAcceptanceSchema
});

const russianMobileSchema = z
  .string()
  .max(32)
  .transform((value, context) => {
    const phone = normalizeRussianMobile(value);
    if (!phone) {
      context.addIssue({ code: "custom", message: "Укажите российский мобильный номер: +7 9XX XXX-XX-XX" });
      return z.NEVER;
    }
    return phone;
  });

export const phoneRequestSchema = z.object({
  phone: russianMobileSchema,
  userAgreement: userAgreementAcceptanceSchema
});

export const phoneVerifySchema = z.object({
  phone: russianMobileSchema,
  code: z.string().trim().regex(/^\d{6}$/, "Введите 6 цифр из SMS"),
  showOnMap: z.boolean().optional(),
  consentReview: z.boolean().optional(),
  userAgreement: userAgreementAcceptanceSchema
});

export const vkAuthSchema = z.object({
  code: z.string().min(1).max(2048),
  codeVerifier: z.string().regex(/^[A-Za-z0-9_-]{43,128}$/, "Некорректный code_verifier"),
  deviceId: z.string().min(1).max(512),
  state: z.string().regex(/^[A-Za-z0-9_-]{32,256}$/, "Некорректный state"),
  showOnMap: z.boolean().optional(),
  consentReview: z.boolean().optional(),
  userAgreement: userAgreementAcceptanceSchema
});

export const mePhoneRequestSchema = z.object({ phone: russianMobileSchema });

export const mePhoneVerifySchema = z.object({
  phone: russianMobileSchema,
  code: z.string().trim().regex(/^\d{6}$/, "Введите 6 цифр из SMS")
});

/**
 * Клиент умеет показывать экран согласий. Новый аккаунт тогда создаётся
 * скрытым до ответа; старые сборки этого поля не шлют и получают прежнее
 * поведение (`legacy`), иначе их пользователи остались бы невидимыми навсегда.
 */
const consentReviewSupportSchema = z.boolean().optional();

/**
 * Страна, которую человек выбрал на экране входа. Email, Apple и Google — для
 * тех, кто не в России; для России вход по телефону или через VK ID
 * (ч. 10 ст. 8 149-ФЗ). Старые сборки поле не шлют.
 */
const nonRussianSignInCountrySchema = z
  .enum(["RU", "OTHER"])
  .optional()
  .refine((value) => value !== "RU", "Для России вход по номеру телефона или через VK ID");

export const verifySchema = z.object({
  showOnMap: z.boolean().optional(),
  consentReview: consentReviewSupportSchema,
  country: nonRussianSignInCountrySchema,
  email: z.string().email().transform((value) => value.toLowerCase()),
  code: z.string().length(6),
  userAgreement: userAgreementAcceptanceSchema
});

export const appleAuthSchema = z.object({
  showOnMap: z.boolean().optional(),
  consentReview: consentReviewSupportSchema,
  country: nonRussianSignInCountrySchema,
  identityToken: z.string().min(1),
  email: z
    .string()
    .email()
    .transform((value) => value.toLowerCase())
    .optional(),
  givenName: z.string().trim().max(80).optional(),
  familyName: z.string().trim().max(80).optional(),
  userAgreement: userAgreementAcceptanceSchema
});

export const updateMeSchema = z.object({
  name: publicText(40).min(2),
  age: z.number().int().min(18).max(100),
  gender: z.enum(["male", "female", "other"]).nullable().optional(),
  city: z.string().trim().min(1).max(100).optional(),
  locationPlaceId: z.string().trim().min(3).max(180).optional(),
  locationSource: z.enum(["manual", "geolocation"]).optional(),
  district: z.enum(DISTRICT_OPTIONS).nullable().optional(),
  preferredDistricts: z.preprocess((value) => parseMultiValue(value), z.array(z.enum(DISTRICT_OPTIONS)).default([])),
  tennisLevel: z.number().int().min(1).max(10).optional(),
  preferredSports: z.array(z.enum(SPORT_OPTIONS)).min(1),
  sportLevels: z
    .preprocess(
      (value) => parseSportLevelsValue(value),
      z.record(z.string(), sportLevelValueSchema)
    )
    .refine(
      (value) => Object.keys(value).every((key) => SPORT_OPTIONS.includes(key as (typeof SPORT_OPTIONS)[number])),
      "Некорректные виды спорта в уровнях"
    ),
  preferredPlayFormat: z.nativeEnum(PlayFormat),
  preferredSurface: z.nativeEnum(Surface),
  bio: publicText(220).optional().default(""),
  availableDays: z.array(dayEnum).max(DAY_OPTIONS.length).default([]),
  availableTimeRanges: z.array(timeRangeEnum).max(TIME_RANGE_OPTIONS.length).default([]),
  availabilityByDay: z
    .preprocess(
      (value) => parseAvailabilityByDayValue(value),
      z.record(z.string(), z.array(timeRangeEnum).max(TIME_RANGE_OPTIONS.length))
    )
    .refine(
      (value) => Object.keys(value).every((key) => DAY_OPTIONS.includes(key as (typeof DAY_OPTIONS)[number])),
      "Некорректные дни в доступности"
    )
    .default({}),
  avatarUrl: z.string().max(300).optional().nullable(),
  profilePhotoUrls: z.array(z.string().min(1).max(600)).max(6).optional(),
  profileVideoUrls: z.array(z.string().min(1).max(600)).max(4).optional(),
  showOnMap: z.boolean().optional(),
  isLookingForGame: z.boolean().optional(),
  notificationMatches: z.boolean().optional(),
  notificationMessages: z.boolean().optional(),
  notificationGames: z.boolean().optional(),
  notificationDigest: z.boolean().optional(),
  notificationSound: z.boolean().optional()
}).refine((value) => Boolean(value.locationPlaceId || value.city), {
  message: "Выберите город",
  path: ["locationPlaceId"]
});

export const adminPlayersQuerySchema = z.object({
  q: z.string().trim().max(120).optional().default(""),
  status: z.union([z.literal("all"), z.nativeEnum(AccountStatus)]).optional().default("all"),
  page: z.coerce.number().int().min(1).optional().default(1),
  limit: z.coerce.number().int().min(1).max(100).optional().default(24)
});

const adminPlayerProfileFieldsSchema = z
  .object({
    onboardingCompleted: z.boolean().optional(),
    name: z.string().trim().min(2).max(40).nullable().optional(),
    age: z.number().int().min(18).max(100).nullable().optional(),
    gender: z.nativeEnum(Gender).nullable().optional(),
    city: cityEnum.nullable().optional(),
    district: z.enum(DISTRICT_OPTIONS).nullable().optional(),
    preferredDistricts: z.preprocess(
      (value) => parseMultiValue(value),
      z.array(z.enum(DISTRICT_OPTIONS)).max(DISTRICT_OPTIONS.length)
    ).optional(),
    tennisLevel: z.number().int().min(1).max(10).nullable().optional(),
    preferredSports: z.array(z.enum(SPORT_OPTIONS)).min(1).optional(),
    sportLevels: z
      .preprocess((value) => parseSportLevelsValue(value), z.record(z.string(), sportLevelValueSchema))
      .refine(
        (value) => Object.keys(value).every((key) => SPORT_OPTIONS.includes(key as (typeof SPORT_OPTIONS)[number])),
        "Некорректные виды спорта в уровнях"
      )
      .optional(),
    preferredPlayFormat: z.nativeEnum(PlayFormat).optional(),
    preferredSurface: z.nativeEnum(Surface).optional(),
    bio: z.string().trim().max(220).nullable().optional(),
    avatarUrl: z.string().trim().max(300).nullable().optional(),
    profilePhotoUrls: z.array(z.string().trim().min(1).max(600)).max(6).optional(),
    profileVideoUrls: z.array(z.string().trim().min(1).max(600)).max(4).optional(),
    availableDays: z.array(dayEnum).max(DAY_OPTIONS.length).optional(),
    availableTimeRanges: z.array(timeRangeEnum).max(TIME_RANGE_OPTIONS.length).optional(),
    availabilityByDay: z
      .record(z.string(), z.array(timeRangeEnum).max(TIME_RANGE_OPTIONS.length))
      .refine(
        (value) => Object.keys(value).every((key) => DAY_OPTIONS.includes(key as (typeof DAY_OPTIONS)[number])),
        "Некорректные дни в доступности"
      )
      .optional(),
    isLookingForGame: z.boolean().optional()
  })
  .strict()
  .refine((profile) => Object.keys(profile).length > 0, "Укажи хотя бы одно изменение профиля");

export const adminPlayerProfilePatchSchema = z.object({
  expectedUpdatedAt: z.string().datetime(),
  profile: adminPlayerProfileFieldsSchema
}).strict();

export const adminPlayerStatusPatchSchema = z
  .object({
    status: z.nativeEnum(AccountStatus),
    reason: z.string().trim().min(3, "Укажи причину изменения статуса").max(500),
    expectedUpdatedAt: z.string().datetime()
  })
  .strict();

export type AdminPlayerProfilePatch = z.infer<typeof adminPlayerProfilePatchSchema>;
export type AdminPlayerStatusPatch = z.infer<typeof adminPlayerStatusPatchSchema>;

const httpUrlOrNullSchema = z
  .union([z.string().trim().url(), z.null()])
  .refine((value) => value == null || value.startsWith("http://") || value.startsWith("https://"), "Разрешены только http/https ссылки");

const uniqueStrings = (max: number) =>
  z
    .array(z.string().trim().min(1).max(600))
    .max(max)
    .transform((items) => Array.from(new Set(items)));

export const adminClubsQuerySchema = z
  .object({
    q: z.string().trim().max(160).optional().default(""),
    status: z.union([z.literal("all"), z.nativeEnum(CourtStatus)]).optional().default("all"),
    city: z.string().trim().max(100).optional().default("all"),
    sport: z.union([z.literal("all"), z.nativeEnum(Sport)]).optional().default("all"),
    sourceType: z.string().trim().max(100).optional().default("all"),
    page: z.coerce.number().int().min(1).optional().default(1),
    limit: z.coerce.number().int().min(1).max(100).optional().default(24)
  })
  .strict();

export const adminClubProfilePatchSchema = z
  .object({
    expectedUpdatedAt: z.string().datetime(),
    profile: z
      .object({
        name: z.string().trim().min(1).max(160).optional(),
        address: z.string().trim().min(1).max(300).optional(),
        city: z.string().trim().min(1).max(100).optional(),
        district: z.string().trim().min(1).max(100).nullable().optional(),
        locationLat: z.number().finite().min(-90).max(90).optional(),
        locationLng: z.number().finite().min(-180).max(180).optional(),
        surface: z.nativeEnum(Surface).optional(),
        setting: z.nativeEnum(CourtSetting).optional(),
        supportedSports: z.array(z.nativeEnum(Sport)).min(1).transform((items) => Array.from(new Set(items))).optional(),
        phone: z.string().trim().max(100).nullable().optional(),
        workingHours: z.string().trim().max(500).nullable().optional(),
        yandexMapsUrl: httpUrlOrNullSchema.optional(),
        websiteUrl: httpUrlOrNullSchema.optional(),
        bookingUrl: httpUrlOrNullSchema.optional(),
        about: z.string().trim().max(3000).nullable().optional(),
        amenities: uniqueStrings(12).optional(),
        messengerType: z.string().trim().max(80).nullable().optional(),
        messengerUrl: httpUrlOrNullSchema.optional(),
        photoUrl: httpUrlOrNullSchema.optional(),
        photoUrls: uniqueStrings(8)
          .refine((items) => items.every((item) => item.startsWith("http://") || item.startsWith("https://")), "Разрешены только http/https ссылки")
          .optional(),
        priceRange: z.string().trim().min(1).max(160).optional(),
        metroIds: uniqueStrings(8).optional()
      })
      .strict()
      .refine(
        (profile) => (profile.locationLat === undefined) === (profile.locationLng === undefined),
        "Широту и долготу нужно изменять вместе"
      )
      .refine((profile) => Object.keys(profile).length > 0, "Укажи хотя бы одно изменение клуба"),
    moderationNote: z.string().trim().max(500).optional()
  })
  .strict();

export const adminClubStatusPatchSchema = z
  .object({
    expectedUpdatedAt: z.string().datetime(),
    status: z.nativeEnum(CourtStatus),
    reason: z.string().trim().min(3, "Укажи причину изменения статуса").max(500)
  })
  .strict();

export type AdminClubsQuery = z.infer<typeof adminClubsQuerySchema>;
export type AdminClubProfilePatch = z.infer<typeof adminClubProfilePatchSchema>;
export type AdminClubStatusPatch = z.infer<typeof adminClubStatusPatchSchema>;

export const guestOnboardingDraftSchema = z.object({
  name: publicText(40).min(2),
  age: z.number().int().min(18).max(100),
  gender: z.enum(["male", "female", "other"]).nullable().optional(),
  city: z.string().trim().min(1).max(100),
  locationPlaceId: z.string().trim().min(3).max(180).nullable().optional(),
  district: z.enum(DISTRICT_OPTIONS).nullable().optional(),
  preferredDistricts: z.preprocess((value) => parseMultiValue(value), z.array(z.enum(DISTRICT_OPTIONS)).default([])),
  preferredSports: z.array(z.enum(SPORT_OPTIONS)).min(1),
  sportLevels: z
    .preprocess(
      (value) => parseSportLevelsValue(value),
      z.record(z.string(), sportLevelValueSchema)
    )
    .refine(
      (value) => Object.keys(value).every((key) => SPORT_OPTIONS.includes(key as (typeof SPORT_OPTIONS)[number])),
      "Некорректные виды спорта в уровнях"
    ),
  preferredPlayFormat: z.nativeEnum(PlayFormat),
  preferredSurface: z.nativeEnum(Surface),
  isLookingForGame: z.boolean().default(true),
  availableDays: z.array(dayEnum).max(DAY_OPTIONS.length).default([]),
  availableTimeRanges: z.array(timeRangeEnum).max(TIME_RANGE_OPTIONS.length).default([]),
  availabilityByDay: z
    .preprocess(
      (value) => parseAvailabilityByDayValue(value),
      z.record(z.string(), z.array(timeRangeEnum).max(TIME_RANGE_OPTIONS.length))
    )
    .refine(
      (value) => Object.keys(value).every((key) => DAY_OPTIONS.includes(key as (typeof DAY_OPTIONS)[number])),
      "Некорректные дни в доступности"
    )
    .default({})
}).refine(
  (value) => Boolean(value.locationPlaceId || AVAILABLE_CITIES.includes(value.city as (typeof AVAILABLE_CITIES)[number])),
  {
    message: "Выберите город",
    path: ["locationPlaceId"]
  }
);

export const discoverFiltersSchema = z.object({
  levelMin: z.coerce.number().int().min(1).max(10).optional(),
  levelMax: z.coerce.number().int().min(1).max(10).optional(),
  distanceKm: z.coerce.number().int().min(1).max(100).optional(),
  city: z.preprocess((value) => parseOptionalText(value), z.string().trim().min(1).max(120).optional()),
  locationPlaceId: z.preprocess((value) => parseOptionalText(value), z.string().trim().min(1).max(160).optional()),
  gender: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Gender)).default([])),
  sport: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Sport)).default([])),
  format: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(PlayFormat)).default([])),
  surface: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Surface)).default([])),
  day: z.preprocess((value) => parseMultiValue(value), z.array(dayEnum).default([])),
  timeRange: z.preprocess((value) => parseMultiValue(value), z.array(timeRangeEnum).default([])),
  view: z.enum(["upcoming", "swipe", "likes", "seeking", "hot"]).optional()
});

export const guestDiscoverSchema = z.object({
  draft: guestOnboardingDraftSchema,
  filters: discoverFiltersSchema.default(() => ({
    gender: [],
    sport: [],
    format: [],
    surface: [],
    day: [],
    timeRange: []
  }))
});

export const swipeSchema = z.object({
  toUserId: z.string().min(1),
  action: z.nativeEnum(SwipeAction)
});

function createMessageSchema(textSchema: z.ZodType<string>) {
  return z
    .object({
      text: textSchema.optional().default(""),
      attachmentIds: z.array(z.string().min(1)).max(4).optional().default([])
    })
    .refine((value) => value.text.length > 0 || value.attachmentIds.length > 0, {
      message: "Добавьте текст или фото"
    })
    .refine((value) => new Set(value.attachmentIds).size === value.attachmentIds.length, {
      message: "Вложения не должны повторяться",
      path: ["attachmentIds"]
    });
}

export const directMessageSchema = createMessageSchema(z.string().trim().max(500));

export const createGameSearchMessageSchema = createMessageSchema(publicText(500));

export const courtsQuerySchema = z.object({
  sport: z.nativeEnum(Sport).optional(),
  q: z.string().trim().max(120).optional(),
  district: z.enum(DISTRICT_OPTIONS).optional(),
  maxDistanceKm: z.coerce.number().int().min(1).max(100).optional(),
  city: z.string().trim().min(1).max(120).optional(),
  locationPlaceId: z.string().trim().min(1).max(160).optional()
});

export const createGameRequestSchema = z
  .object({
    matchId: z.string().min(1),
    proposedCourtId: z.string().min(1).nullable().optional(),
    proposedDatetime: z.string().datetime(),
    durationMinutes: z.number().int().min(30).max(240).optional().nullable(),
    levelRangeMin: z.number().int().min(1).max(10).optional().nullable(),
    levelRangeMax: z.number().int().min(1).max(10).optional().nullable(),
    sport: z.nativeEnum(Sport),
    format: z.nativeEnum(PlayFormat),
    comment: publicText(240).optional().default("")
  })
  .superRefine((value, ctx) => {
    if (!isFutureDateTime(value.proposedDatetime)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["proposedDatetime"],
        message: "Выбери будущую дату и время"
      });
    }

    if (!isFormatAllowedForSport(value.sport, value.format)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["format"],
        message: "Этот формат недоступен для выбранного вида спорта"
      });
    }
  });

export const updateGameRequestSchema = z
  .object({
    status: z.nativeEnum(GameRequestStatus).optional(),
    outcome: z.nativeEnum(GameRequestOutcome).nullable().optional(),
    proposedCourtId: z.string().min(1).nullable().optional(),
    proposedDatetime: z.string().datetime().optional(),
    durationMinutes: z.number().int().min(30).max(240).nullable().optional(),
    levelRangeMin: z.number().int().min(1).max(10).nullable().optional(),
    levelRangeMax: z.number().int().min(1).max(10).nullable().optional(),
    sport: z.nativeEnum(Sport).optional(),
    format: z.nativeEnum(PlayFormat).optional(),
    comment: publicText(240).optional()
  })
  .superRefine((value, ctx) => {
    const hasAnyChange =
      value.status !== undefined ||
      value.outcome !== undefined ||
      value.proposedCourtId !== undefined ||
      value.proposedDatetime !== undefined ||
      value.durationMinutes !== undefined ||
      value.levelRangeMin !== undefined ||
      value.levelRangeMax !== undefined ||
      value.sport !== undefined ||
      value.format !== undefined ||
      value.comment !== undefined;

    if (!hasAnyChange) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Нужно передать хотя бы одно изменение"
      });
    }

    if (value.sport !== undefined && value.format !== undefined && !isFormatAllowedForSport(value.sport, value.format)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["format"],
        message: "Этот формат недоступен для выбранного вида спорта"
      });
    }

    if (value.proposedDatetime !== undefined && !isFutureDateTime(value.proposedDatetime)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["proposedDatetime"],
        message: "Выбери будущую дату и время"
      });
    }

    if (
      value.levelRangeMin !== undefined &&
      value.levelRangeMax !== undefined &&
      value.levelRangeMin !== null &&
      value.levelRangeMax !== null &&
      value.levelRangeMin > value.levelRangeMax
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["levelRangeMin"],
        message: "Минимальный уровень не может быть выше максимального"
      });
    }
  });

export const shareGameRequestSchema = z.object({
  matchIds: z.array(z.string().min(1)).min(1).max(20)
});

export const createGameReportSchema = z.object({
  photoUrls: z.array(z.string().min(1).max(600)).min(1).max(5),
  comment: publicText(240).optional().default(""),
  visibility: z.nativeEnum(GameReportVisibility).optional().default(GameReportVisibility.profile)
});

export const updateGameReportConfirmationSchema = z.object({
  status: z.nativeEnum(GameReportConfirmationStatus)
});

const runningRoutePointSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180)
});

export const createPersonalActivitySchema = z.object({
  courtId: z.string().min(1),
  sport: z.nativeEnum(Sport).default(Sport.tennis),
  scheduledAt: z.string().datetime(),
  durationMinutes: z.number().int().min(15).max(360).optional().nullable(),
  comment: publicText(240).optional().default("")
}).superRefine((value, ctx) => {
  if (!isFutureDateTime(value.scheduledAt)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["scheduledAt"],
      message: "Выбери будущую дату и время"
    });
  }
});

export const updatePersonalActivitySchema = z.object({
  scheduledAt: z.string().datetime().optional(),
  durationMinutes: z.number().int().min(15).max(360).optional().nullable(),
  comment: publicText(240).optional(),
  status: z.nativeEnum(PersonalActivityStatus).optional(),
  reportComment: publicText(240).optional().nullable(),
  photoUrls: z.array(z.string().min(1).max(600)).max(8).optional(),
  videoUrls: z.array(z.string().trim().min(1).max(600)).max(8).optional()
});

export const createGameSearchSchema = z
  .object({
    inviteSlug: z.string().trim().min(6).max(120).optional().nullable(),
    preferredCourtId: z.string().min(1).optional().nullable(),
    customVenueTitle: publicText(100).optional().nullable(),
    customVenueAddress: publicText(240).optional().nullable(),
    runningRoute: publicText(500).optional().nullable(),
    runningRoutePoints: z.array(runningRoutePointSchema).max(80).optional().nullable(),
    preferredDistricts: z.preprocess((value) => parseMultiValue(value), z.array(z.enum(DISTRICT_OPTIONS)).default([])),
    preferredDays: z.array(dayEnum).max(DAY_OPTIONS.length).default([]),
    preferredTimeRanges: z.array(timePreferenceSchema).min(1),
    searchType: z.nativeEnum(GameSearchType).default(GameSearchType.regular),
    hotWindow: z.nativeEnum(HotSearchWindow).optional().nullable(),
    hotStartTime: z
      .string()
      .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Укажи время начала в формате ЧЧ:ММ")
      .optional()
      .nullable(),
    hotStartsAt: z.string().datetime().optional().nullable(),
    durationMinutes: z.number().int().min(30).max(240).optional().nullable(),
    hasCourtBooked: z.boolean().optional().default(false),
    sport: z.nativeEnum(Sport),
    selfLevel: z.number().int().min(1).max(10).optional().nullable(),
    selfLevelUnknown: z.boolean().optional().default(false),
    desiredLevelMin: z.number().int().min(1).max(10).optional().default(1),
    desiredLevelMax: z.number().int().min(1).max(10).optional().default(10),
    format: z.nativeEnum(PlayFormat),
    playersNeeded: z.number().int().min(1).max(30).optional().default(1),
    comment: publicText(240).optional().default("")
  })
  .superRefine((value, ctx) => {
    if (!isFormatAllowedForSport(value.sport, value.format)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["format"],
        message: "Этот формат недоступен для выбранного вида спорта"
      });
    }

    if (value.searchType === GameSearchType.regular && value.preferredDays.length === 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["preferredDays"],
        message: "Выбери хотя бы один день"
      });
    }

    if (value.searchType === GameSearchType.hot && !value.hotWindow && !value.hotStartsAt) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["hotWindow"],
        message: "Для горячего поиска выбери дату"
      });
    }

    if (value.searchType === GameSearchType.hot && !value.hotStartTime && !value.hotStartsAt) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["hotStartTime"],
        message: "Для горячего поиска укажи время начала"
      });
    }

    if (value.searchType === GameSearchType.hot && !value.durationMinutes) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["durationMinutes"],
        message: "Для горячего поиска укажи длительность"
      });
    }

    if (value.desiredLevelMin > value.desiredLevelMax) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["desiredLevelMin"],
        message: "Минимальный уровень не может быть выше максимального"
      });
    }
  });

export const updateGameSearchSchema = z
  .object({
    inviteSlug: z.string().trim().min(6).max(120).nullable().optional(),
    isActive: z.boolean().optional(),
    scheduledCourtId: z.string().min(1).nullable().optional(),
    scheduledAt: z.string().datetime().nullable().optional(),
    scheduledDurationMinutes: z.number().int().min(30).max(240).nullable().optional(),
    preferredCourtId: z.string().min(1).nullable().optional(),
    customVenueTitle: publicText(100).nullable().optional(),
    customVenueAddress: publicText(240).nullable().optional(),
    runningRoute: publicText(500).nullable().optional(),
    runningRoutePoints: z.array(runningRoutePointSchema).max(80).nullable().optional(),
    preferredDistricts: z.preprocess((value) => parseMultiValue(value), z.array(z.enum(DISTRICT_OPTIONS)).optional()),
    preferredDays: z.array(dayEnum).max(DAY_OPTIONS.length).optional(),
    preferredTimeRanges: z.array(timePreferenceSchema).min(1).optional(),
    searchType: z.nativeEnum(GameSearchType).optional(),
    hotWindow: z.nativeEnum(HotSearchWindow).nullable().optional(),
    hotStartTime: z
      .string()
      .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Укажи время начала в формате ЧЧ:ММ")
      .nullable()
      .optional(),
    hotStartsAt: z.string().datetime().nullable().optional(),
    durationMinutes: z.number().int().min(30).max(240).nullable().optional(),
    hasCourtBooked: z.boolean().optional(),
    sport: z.nativeEnum(Sport).optional(),
    selfLevel: z.number().int().min(1).max(10).nullable().optional(),
    selfLevelUnknown: z.boolean().optional(),
    desiredLevelMin: z.number().int().min(1).max(10).optional(),
    desiredLevelMax: z.number().int().min(1).max(10).optional(),
    format: z.nativeEnum(PlayFormat).optional(),
    playersNeeded: z.number().int().min(1).max(30).optional(),
    comment: publicText(240).optional()
  })
  .superRefine((value, ctx) => {
    if (value.sport !== undefined && value.format !== undefined && !isFormatAllowedForSport(value.sport, value.format)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["format"],
        message: "Этот формат недоступен для выбранного вида спорта"
      });
    }

    if (value.desiredLevelMin !== undefined && value.desiredLevelMax !== undefined && value.desiredLevelMin > value.desiredLevelMax) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["desiredLevelMin"],
        message: "Минимальный уровень не может быть выше максимального"
      });
    }
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: "Нужно передать обновление статуса или параметров игры"
  });

export const createGameSearchResponseSchema = z.object({
  message: publicText(240).optional().default("")
});

export const updateGameSearchResponseSchema = z.object({
  status: z.nativeEnum(GameSearchResponseStatus)
});

export const updateRegularPairOccurrenceSchema = z.object({
  status: z.enum(["confirmed", "declined"]).optional(),
  scheduledAt: z.string().datetime().optional(),
  proposedCourtId: z.string().min(1).nullable().optional(),
  durationMinutes: z.number().int().min(30).max(240).nullable().optional()
}).refine((value) => Object.keys(value).length > 0, {
  message: "Нужно передать подтверждение или новые параметры слота"
});

export const createGameSearchSlotProposalSchema = z.object({
  comment: publicText(240).optional().default(""),
  options: z
    .array(
      z.object({
        scheduledAt: z.string().datetime(),
        proposedCourtId: z.string().min(1).nullable().optional(),
        durationMinutes: z.number().int().min(30).max(240).nullable().optional()
      })
    )
    .min(1, "Выбери хотя бы один слот")
    .max(8, "Можно предложить не больше 8 слотов")
}).superRefine((value, ctx) => {
  const unique = new Set<string>();
  for (const [index, option] of value.options.entries()) {
    const key = `${option.scheduledAt}|${option.proposedCourtId ?? ""}`;
    if (unique.has(key)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["options", index, "scheduledAt"],
        message: "Этот слот уже добавлен"
      });
    }
    unique.add(key);
  }
});

export const voteGameSearchSlotProposalSchema = z.object({
  optionIds: z.array(z.string().min(1)).max(8).default([])
});

export const registerPushDeviceSchema = z.object({
  token: z
    .string()
    .trim()
    .regex(/^[0-9a-fA-F]{32,256}$/, "Некорректный APNs token")
    .transform((value) => value.toLowerCase()),
  platform: z.enum(["ios"]).default("ios"),
  environment: z.enum(["development", "production"]),
  bundleId: z.string().trim().min(3).max(200),
  deviceName: z.string().trim().max(120).optional().nullable(),
  locale: z
    .string()
    .trim()
    .max(35)
    .optional()
    .nullable()
    .transform((value) => normalizeSupportedLocale(value))
});

// FCM registration tokens are not hex like APNs ones: they carry ":" and the
// base64url alphabet, so they need their own shape.
export const registerFCMDeviceSchema = z.object({
  token: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9_:.-]{64,4096}$/, "Некорректный FCM token"),
  platform: z.literal("android").default("android"),
  environment: z.enum(["development", "production"]),
  bundleId: z.string().trim().min(3).max(200),
  deviceName: z.string().trim().max(120).optional().nullable(),
  locale: z
    .string()
    .trim()
    .max(35)
    .optional()
    .nullable()
    .transform((value) => normalizeSupportedLocale(value))
});

const publicReportReasonSchema = z.enum([
  ContentReportReason.harassment,
  ContentReportReason.hate_speech,
  ContentReportReason.sexual_content,
  ContentReportReason.violence,
  ContentReportReason.spam,
  ContentReportReason.impersonation,
  ContentReportReason.other
]);

export const createContentReportSchema = z.object({
  reason: publicReportReasonSchema,
  details: z.string().trim().max(1000).optional(),
  context: z.object({
    type: z.enum(["profile", "chat"]),
    id: z.string().trim().min(1).max(200).optional()
  }).strict().optional()
}).strict();

export const blockUserSchema = createContentReportSchema.partial().default({});

export const adminContentReportsQuerySchema = z.object({
  status: z.union([z.literal("all"), z.nativeEnum(ContentReportStatus)]).optional().default("pending"),
  origin: z.enum(["all", "report", "block"]).optional().default("all"),
  q: z.string().trim().max(120).optional().default(""),
  page: z.coerce.number().int().min(1).optional().default(1),
  limit: z.coerce.number().int().min(1).max(100).optional().default(24)
}).strict();

export const resolveContentReportSchema = z.object({
  status: z.enum([ContentReportStatus.actioned, ContentReportStatus.dismissed]),
  resolutionNote: z.string().trim().min(3).max(1000),
  expectedUpdatedAt: z.string().datetime()
}).strict();

export type CreateContentReportInput = z.infer<typeof createContentReportSchema>;
export type AdminContentReportsQuery = z.infer<typeof adminContentReportsQuerySchema>;
export type ResolveContentReportInput = z.infer<typeof resolveContentReportSchema>;

/** Порядок фото и видео в карточке: аватар, 6 фото и 4 видео — не больше 11. */
export const profileMediaOrderSchema = z.object({
  order: z.array(z.string().trim().min(1).max(600)).max(11)
}).strict();

export const userEventSchema = z.object({
  type: z.enum(CLIENT_REPORTABLE_EVENT_TYPES),
  entityType: z.string().trim().max(60).optional(),
  entityId: z.string().trim().max(200).optional(),
  deliveryId: z.string().trim().max(200).optional(),
  context: z.object({
    platform: z.enum(["web", "ios", "android"]).optional(),
    screen: z.enum(["app", "onboarding", "discover", "play", "inbox", "profile", "settings", "activity"]).optional(),
    step: z.number().int().min(0).max(20).optional(),
    view: z.enum(["players", "likes", "hot", "regular", "searches", "map", "cards", "list"]).optional(),
    count: z.number().int().min(0).max(10000).optional(),
    empty: z.boolean().optional()
  }).strict().optional()
}).strict();

export const userEventsSchema = z.object({
  events: z.array(userEventSchema).min(1).max(20)
}).strict();

export type UserEventPayload = z.infer<typeof userEventSchema>;

export const consentUpdateSchema = z
  .object({
    source: z.enum(["web", "ios", "android"]),
    acceptAgreementVersion: z
      .literal(USER_AGREEMENT_VERSION, "Нужно принять актуальную редакцию пользовательского соглашения")
      .optional(),
    profile: z
      .object({
        decision: z.enum(["visible", "hidden"]),
        fullName: z
          .string()
          .trim()
          .max(150)
          .transform((value) => value.replace(/\s+/g, " "))
          .refine((value) => CONSENT_FULL_NAME_PATTERN.test(value), "Укажите фамилию и имя")
          .optional(),
        visibleToGuests: z.boolean().optional(),
        showsBio: z.boolean().optional(),
        showsPhotos: z.boolean().optional(),
        showsVideos: z.boolean().optional(),
        showsSearches: z.boolean().optional(),
        showOnMap: z.boolean().optional()
      })
      .strict()
      .optional(),
    analytics: z.boolean().optional()
  })
  .strict()
  .refine(
    (value) => value.acceptAgreementVersion !== undefined || value.profile !== undefined || value.analytics !== undefined,
    "Нет изменений согласий"
  );

export type ConsentUpdatePayload = z.infer<typeof consentUpdateSchema>;
