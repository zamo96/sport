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
import { isFormatAllowedForSport } from "@/lib/sport-playbook";

const dayEnum = z.enum(DAY_OPTIONS);
const timeRangeEnum = z.enum(TIME_RANGE_OPTIONS);
const exactTimeSlotSchema = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Укажи время в формате ЧЧ:ММ");
const pairedTimeSlotSchema = z
  .string()
  .regex(/^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)@([01]\d|2[0-3]):[0-5]\d$/, "Укажи день и время в формате day@ЧЧ:ММ");
const timePreferenceSchema = z.union([timeRangeEnum, exactTimeSlotSchema, pairedTimeSlotSchema]);

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

export const requestLinkSchema = z.object({
  email: z.string().email().transform((value) => value.toLowerCase())
});

export const verifySchema = z.object({
  email: z.string().email().transform((value) => value.toLowerCase()),
  code: z.string().length(6)
});

export const appleAuthSchema = z.object({
  identityToken: z.string().min(1),
  email: z
    .string()
    .email()
    .transform((value) => value.toLowerCase())
    .optional(),
  givenName: z.string().trim().max(80).optional(),
  familyName: z.string().trim().max(80).optional()
});

export const updateMeSchema = z.object({
  name: z.string().min(2).max(40),
  age: z.number().int().min(18).max(70),
  gender: z.enum(["male", "female", "other"]).nullable().optional(),
  city: z.literal(DEFAULT_CITY),
  district: z.enum(DISTRICT_OPTIONS).nullable().optional(),
  preferredDistricts: z.preprocess((value) => parseMultiValue(value), z.array(z.enum(DISTRICT_OPTIONS)).default([])),
  tennisLevel: z.number().int().min(1).max(10),
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
  bio: z.string().max(220).optional().default(""),
  searchRadiusKm: z.number().int().min(1).max(100).optional().default(20),
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
  searchRadiusKm: z.number().int().min(1).max(100).optional().default(20),
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

export const createGameRequestSchema = z
  .object({
    matchId: z.string().min(1),
    proposedCourtId: z.string().min(1),
    proposedDatetime: z.string().datetime(),
    durationMinutes: z.number().int().min(30).max(240).optional().nullable(),
    levelRangeMin: z.number().int().min(1).max(10).optional().nullable(),
    levelRangeMax: z.number().int().min(1).max(10).optional().nullable(),
    sport: z.nativeEnum(Sport),
    format: z.nativeEnum(PlayFormat),
    comment: z.string().max(240).optional().default("")
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
    proposedCourtId: z.string().min(1).optional(),
    proposedDatetime: z.string().datetime().optional(),
    durationMinutes: z.number().int().min(30).max(240).nullable().optional(),
    levelRangeMin: z.number().int().min(1).max(10).nullable().optional(),
    levelRangeMax: z.number().int().min(1).max(10).nullable().optional(),
    sport: z.nativeEnum(Sport).optional(),
    format: z.nativeEnum(PlayFormat).optional(),
    comment: z.string().max(240).optional()
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

export const createGameSearchSchema = z
  .object({
    inviteSlug: z.string().trim().min(6).max(120).optional().nullable(),
    preferredCourtId: z.string().min(1).optional().nullable(),
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

export const updateGameSearchSchema = z
  .object({
    inviteSlug: z.string().trim().min(6).max(120).nullable().optional(),
    isActive: z.boolean().optional(),
    scheduledCourtId: z.string().min(1).nullable().optional(),
    scheduledAt: z.string().datetime().nullable().optional(),
    scheduledDurationMinutes: z.number().int().min(30).max(240).nullable().optional(),
    preferredCourtId: z.string().min(1).nullable().optional(),
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
    durationMinutes: z.number().int().min(30).max(240).nullable().optional(),
    hasCourtBooked: z.boolean().optional(),
    sport: z.nativeEnum(Sport).optional(),
    selfLevel: z.number().int().min(1).max(10).nullable().optional(),
    selfLevelUnknown: z.boolean().optional(),
    desiredLevelMin: z.number().int().min(1).max(10).optional(),
    desiredLevelMax: z.number().int().min(1).max(10).optional(),
    format: z.nativeEnum(PlayFormat).optional(),
    playersNeeded: z.number().int().min(1).max(30).optional(),
    comment: z.string().max(240).optional()
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
  message: z.string().max(240).optional().default("")
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

export const createGameSearchMessageSchema = z.object({
  text: z.string().trim().min(1).max(500)
});

export const createGameSearchSlotProposalSchema = z.object({
  comment: z.string().trim().max(240).optional().default(""),
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
  deviceName: z.string().trim().max(120).optional().nullable()
});
