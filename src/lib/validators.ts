import {
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

import { DAY_OPTIONS, SPORT_OPTIONS, TIME_RANGE_OPTIONS } from "@/lib/constants";

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
  city: z.string().min(2).max(60),
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
  avatarUrl: z.string().max(300).optional().nullable(),
  isLookingForGame: z.boolean().optional(),
  notificationMatches: z.boolean().optional(),
  notificationMessages: z.boolean().optional(),
  notificationGames: z.boolean().optional()
});

export const discoverFiltersSchema = z.object({
  levelMin: z.coerce.number().int().min(1).max(10).optional(),
  levelMax: z.coerce.number().int().min(1).max(10).optional(),
  distanceKm: z.coerce.number().int().min(1).max(100).optional(),
  city: z.preprocess((value) => parseOptionalText(value), z.string().min(2).max(60).optional()),
  gender: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Gender)).default([])),
  sport: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Sport)).default([])),
  format: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(PlayFormat)).default([])),
  surface: z.preprocess((value) => parseMultiValue(value), z.array(z.nativeEnum(Surface)).default([])),
  day: z.preprocess((value) => parseMultiValue(value), z.array(dayEnum).default([])),
  timeRange: z.preprocess((value) => parseMultiValue(value), z.array(timeRangeEnum).default([])),
  view: z.enum(["swipe", "seeking", "hot"]).optional()
});

export const swipeSchema = z.object({
  toUserId: z.string().min(1),
  action: z.nativeEnum(SwipeAction)
});

export const messageSchema = z.object({
  text: z.string().trim().min(1).max(500)
});

export const courtsQuerySchema = z.object({
  surface: z.nativeEnum(Surface).optional(),
  setting: z.enum(["indoor", "outdoor"]).optional(),
  maxDistanceKm: z.coerce.number().int().min(1).max(100).optional(),
  city: z.string().optional()
});

export const createGameRequestSchema = z.object({
  matchId: z.string().min(1),
  proposedCourtId: z.string().min(1),
  proposedDatetime: z.string().datetime(),
  levelRangeMin: z.number().int().min(1).max(10).optional().nullable(),
  levelRangeMax: z.number().int().min(1).max(10).optional().nullable(),
  sport: z.nativeEnum(Sport),
  format: z.nativeEnum(PlayFormat),
  comment: z.string().max(240).optional().default("")
});

export const updateGameRequestSchema = z.object({
  status: z.nativeEnum(GameRequestStatus)
});

export const createGameSearchSchema = z
  .object({
    preferredCourtId: z.string().min(1).optional().nullable(),
    preferredDays: z.array(dayEnum).max(DAY_OPTIONS.length).default([]),
    preferredTimeRanges: z.array(timeRangeEnum).min(1),
    searchType: z.nativeEnum(GameSearchType).default(GameSearchType.regular),
    hotWindow: z.nativeEnum(HotSearchWindow).optional().nullable(),
    hasCourtBooked: z.boolean().optional().default(false),
    sport: z.nativeEnum(Sport),
    format: z.nativeEnum(PlayFormat),
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
