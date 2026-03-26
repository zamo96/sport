import {
  GameRequestOutcome,
  Gender,
  GameRequestStatus,
  GameSearchResponseStatus,
  GameSearchType,
  HotSearchWindow,
  PlayFormat,
  Sport,
  Surface,
  SwipeAction
} from "@prisma/client";
import { z } from "zod";

import { DAY_OPTIONS, DEFAULT_CITY, DISTRICT_OPTIONS, SPORT_OPTIONS, TIME_RANGE_OPTIONS } from "@/lib/constants";

const dayEnum = z.enum(DAY_OPTIONS);
const timeRangeEnum = z.enum(TIME_RANGE_OPTIONS);

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

export const requestLinkSchema = z.object({
  email: z.string().email().transform((value) => value.toLowerCase())
});

export const verifySchema = z.object({
  email: z.string().email().transform((value) => value.toLowerCase()),
  code: z.string().length(6)
});

export const updateMeSchema = z.object({
  name: z.string().min(2).max(40),
  age: z.number().int().min(18).max(70),
  gender: z.enum(["male", "female", "other"]).nullable().optional(),
  city: z.literal(DEFAULT_CITY),
  district: z.enum(DISTRICT_OPTIONS).nullable().optional(),
  tennisLevel: z.number().int().min(1).max(10),
  preferredSports: z.array(z.enum(SPORT_OPTIONS)).min(1),
  sportLevels: z
    .preprocess(
      (value) => parseSportLevelsValue(value),
      z.record(z.string(), z.number().int().min(1).max(10))
    )
    .refine(
      (value) => Object.keys(value).every((key) => SPORT_OPTIONS.includes(key as (typeof SPORT_OPTIONS)[number])),
      "Некорректные виды спорта в уровнях"
    ),
  preferredPlayFormat: z.nativeEnum(PlayFormat),
  preferredSurface: z.nativeEnum(Surface),
  bio: z.string().max(220).optional().default(""),
  searchRadiusKm: z.number().int().min(1).max(100),
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
  isLookingForGame: z.boolean().optional(),
  notificationMatches: z.boolean().optional(),
  notificationMessages: z.boolean().optional(),
  notificationGames: z.boolean().optional(),
  notificationSound: z.boolean().optional()
});

export const guestOnboardingDraftSchema = z.object({
  name: z.string().min(2).max(40),
  age: z.number().int().min(18).max(70),
  gender: z.enum(["male", "female", "other"]).nullable().optional(),
  city: z.literal(DEFAULT_CITY),
  district: z.enum(DISTRICT_OPTIONS).nullable().optional(),
  preferredSports: z.array(z.enum(SPORT_OPTIONS)).min(1),
  sportLevels: z
    .preprocess(
      (value) => parseSportLevelsValue(value),
      z.record(z.string(), z.number().int().min(1).max(10))
    )
    .refine(
      (value) => Object.keys(value).every((key) => SPORT_OPTIONS.includes(key as (typeof SPORT_OPTIONS)[number])),
      "Некорректные виды спорта в уровнях"
    ),
  preferredPlayFormat: z.nativeEnum(PlayFormat),
  preferredSurface: z.nativeEnum(Surface),
  searchRadiusKm: z.number().int().min(1).max(100),
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
});

export const discoverFiltersSchema = z.object({
  levelMin: z.coerce.number().int().min(1).max(10).optional(),
  levelMax: z.coerce.number().int().min(1).max(10).optional(),
  distanceKm: z.coerce.number().int().min(1).max(100).optional(),
  city: z.preprocess((value) => parseOptionalText(value), z.literal(DEFAULT_CITY).optional()),
  gender: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Gender)).default([])),
  sport: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Sport)).default([])),
  format: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(PlayFormat)).default([])),
  surface: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Surface)).default([])),
  day: z.preprocess((value) => parseMultiValue(value), z.array(dayEnum).default([])),
  timeRange: z.preprocess((value) => parseMultiValue(value), z.array(timeRangeEnum).default([])),
  view: z.enum(["swipe", "likes", "seeking", "hot"]).optional()
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

export const messageSchema = z.object({
  text: z.string().trim().min(1).max(500)
});

export const courtsQuerySchema = z.object({
  sport: z.nativeEnum(Sport).optional(),
  q: z.string().trim().max(120).optional(),
  district: z.enum(DISTRICT_OPTIONS).optional(),
  maxDistanceKm: z.coerce.number().int().min(1).max(100).optional(),
  city: z.literal(DEFAULT_CITY).optional()
});

export const createGameRequestSchema = z.object({
  matchId: z.string().min(1),
  proposedCourtId: z.string().min(1),
  proposedDatetime: z.string().datetime(),
  durationMinutes: z.number().int().min(30).max(240).optional().nullable(),
  levelRangeMin: z.number().int().min(1).max(10).optional().nullable(),
  levelRangeMax: z.number().int().min(1).max(10).optional().nullable(),
  sport: z.nativeEnum(Sport),
  format: z.nativeEnum(PlayFormat),
  comment: z.string().max(240).optional().default("")
});

export const updateGameRequestSchema = z
  .object({
    status: z.nativeEnum(GameRequestStatus).optional(),
    outcome: z.nativeEnum(GameRequestOutcome).nullable().optional()
  })
  .refine((value) => value.status !== undefined || value.outcome !== undefined, {
    message: "Нужно передать статус или результат игры"
  });

export const createGameSearchSchema = z
  .object({
    preferredCourtId: z.string().min(1).optional().nullable(),
    preferredDays: z.array(dayEnum).max(DAY_OPTIONS.length).default([]),
    preferredTimeRanges: z.array(timeRangeEnum).min(1),
    searchType: z.nativeEnum(GameSearchType).default(GameSearchType.regular),
    hotWindow: z.nativeEnum(HotSearchWindow).optional().nullable(),
    hotStartTime: z
      .string()
      .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Укажи время начала в формате ЧЧ:ММ")
      .optional()
      .nullable(),
    durationMinutes: z.number().int().min(30).max(240).optional().nullable(),
    hasCourtBooked: z.boolean().optional().default(false),
    sport: z.nativeEnum(Sport),
    selfLevel: z.number().int().min(1).max(10).optional().nullable(),
    selfLevelUnknown: z.boolean().optional().default(false),
    desiredLevelMin: z.number().int().min(1).max(10).optional().default(1),
    desiredLevelMax: z.number().int().min(1).max(10).optional().default(10),
    format: z.nativeEnum(PlayFormat),
    playersNeeded: z.number().int().min(1).max(30).optional().default(1),
    comment: z.string().max(240).optional().default("")
  })
  .superRefine((value, ctx) => {
    if (value.searchType === GameSearchType.regular && value.preferredDays.length === 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["preferredDays"],
        message: "Выбери хотя бы один день"
      });
    }

    if (value.searchType === GameSearchType.hot && !value.hotWindow) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["hotWindow"],
        message: "Для горячего поиска выбери сегодня или завтра"
      });
    }

    if (value.searchType === GameSearchType.hot && !value.hotStartTime) {
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

export const updateGameSearchSchema = z.object({
  isActive: z.boolean()
});

export const createGameSearchResponseSchema = z.object({
  message: z.string().max(240).optional().default("")
});

export const updateGameSearchResponseSchema = z.object({
  status: z.nativeEnum(GameSearchResponseStatus)
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
  deviceName: z.string().trim().max(120).optional().nullable()
});
