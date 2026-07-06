import {
  CourtStatus,
  GameSearchResponseStatus,
  GameSearchStatus,
  GameSearchType,
  HotSearchWindow,
  PlayFormat,
  Sport
} from "@prisma/client";

import { SPORT_LABELS } from "@/lib/constants";
import { prisma } from "@/lib/prisma";

type CliOptions = {
  creators: number;
  perUser: number;
  responses: number;
  reset: boolean;
  dryRun: boolean;
  viewerEmail?: string;
};

type SimUser = {
  id: string;
  name: string | null;
  email: string;
  district: string | null;
  preferredDistricts: unknown;
  preferredSports: unknown;
  sportLevels: unknown;
  preferredPlayFormat: PlayFormat;
};

type SimCourt = {
  id: string;
  name: string;
  district: string | null;
  supportedSports: unknown;
};

const SIMULATION_MARKER = "[симуляция]";
const DAY_KEYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] as const;
const SPORT_VALUES = new Set<string>(Object.values(Sport));

function parseOptions(): CliOptions {
  const args = new Map(
    process.argv
      .slice(2)
      .filter((arg) => arg.startsWith("--"))
      .map((arg) => {
        const [key, value = "true"] = arg.slice(2).split("=");
        return [key, value] as const;
      })
  );

  return {
    creators: Math.max(1, Number(args.get("creators") ?? 4)),
    perUser: Math.max(1, Number(args.get("per-user") ?? 2)),
    responses: Math.max(0, Number(args.get("responses") ?? 1)),
    reset: args.get("reset") === "true",
    dryRun: args.get("dry-run") === "true",
    viewerEmail: args.get("viewer-email")
  };
}

function normalizeSports(value: unknown): Sport[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is Sport => typeof item === "string" && SPORT_VALUES.has(item));
}

function normalizeStrings(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function pick<T>(items: T[], index: number) {
  return items[index % items.length];
}

function pickFormat(user: SimUser, sport: Sport, index: number) {
  if (sport === Sport.football || sport === Sport.volleyball) {
    return PlayFormat.doubles;
  }

  if (sport === Sport.padel) {
    return PlayFormat.doubles;
  }

  if (user.preferredPlayFormat !== PlayFormat.both) {
    return user.preferredPlayFormat;
  }

  return index % 3 === 0 ? PlayFormat.doubles : PlayFormat.singles;
}

function playersNeededForSport(sport: Sport, format: PlayFormat, index: number) {
  if (sport === Sport.football) {
    return 3 + (index % 3);
  }

  if (sport === Sport.volleyball) {
    return 4 + (index % 3);
  }

  if (format === PlayFormat.doubles) {
    return 1 + (index % 3);
  }

  return 1;
}

function pickCourtForSport(courts: SimCourt[], sport: Sport, district: string | null, index: number) {
  const bySport = courts.filter((court) => {
    const supportedSports = normalizeSports(court.supportedSports);
    return supportedSports.length === 0 || supportedSports.includes(sport);
  });
  const byDistrict = bySport.filter((court) => court.district && district && court.district === district);
  const pool = byDistrict.length > 0 ? byDistrict : bySport.length > 0 ? bySport : courts;

  return pool.length > 0 ? pick(pool, index) : null;
}

function buildStartsAt(index: number) {
  const now = new Date();
  const dayOffset = index % 3;
  const startsAt = new Date(now);

  if (dayOffset === 0) {
    startsAt.setTime(now.getTime() + (90 + index * 25) * 60 * 1000);
  } else {
    startsAt.setDate(startsAt.getDate() + dayOffset);
    startsAt.setHours(9 + ((index * 2) % 12), index % 2 === 0 ? 0 : 30, 0, 0);
  }

  return startsAt;
}

function hotWindowForDate(date: Date) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const target = new Date(date);
  target.setHours(0, 0, 0, 0);

  const diffDays = Math.round((target.getTime() - today.getTime()) / (24 * 60 * 60 * 1000));
  if (diffDays <= 0) {
    return HotSearchWindow.today;
  }
  if (diffDays === 1) {
    return HotSearchWindow.tomorrow;
  }
  return HotSearchWindow.day_after_tomorrow;
}

function timeRangeForDate(date: Date) {
  const hour = date.getHours();
  if (hour < 12) return "morning";
  if (hour < 18) return "day";
  return "evening";
}

function levelForSport(user: SimUser, sport: Sport) {
  if (!user.sportLevels || typeof user.sportLevels !== "object" || Array.isArray(user.sportLevels)) {
    return 5;
  }

  const rawLevel = (user.sportLevels as Record<string, unknown>)[sport];
  return typeof rawLevel === "number" && Number.isFinite(rawLevel) ? Math.round(rawLevel) : 5;
}

function buildComment(sport: Sport, court: SimCourt | null, index: number) {
  const sportLabel = SPORT_LABELS[sport].toLowerCase();
  const place = court ? ` в ${court.name}` : "";
  return `${SIMULATION_MARKER} Активный поиск #${index + 1}: ищу игроков на ${sportLabel}${place}.`;
}

async function main() {
  const options = parseOptions();

  if (options.reset && options.dryRun) {
    console.log("Dry-run: симулированные поиски не будут удалены.");
  } else if (options.reset) {
    const deleted = await prisma.gameSearch.deleteMany({
      where: {
        comment: {
          startsWith: SIMULATION_MARKER
        }
      }
    });
    console.log(`Удалено симулированных поисков: ${deleted.count}`);
  }

  const users = await prisma.user.findMany({
    where: {
      onboardingCompleted: true,
      isVerified: true,
      ...(options.viewerEmail ? { email: { not: options.viewerEmail } } : {})
    },
    select: {
      id: true,
      name: true,
      email: true,
      district: true,
      preferredDistricts: true,
      preferredSports: true,
      sportLevels: true,
      preferredPlayFormat: true
    },
    orderBy: {
      createdAt: "asc"
    }
  });

  if (users.length < 2) {
    throw new Error("Нужно минимум 2 верифицированных пользователя с завершенным онбордингом. Запусти seed или создай тестовых пользователей.");
  }

  const courts = await prisma.court.findMany({
    where: {
      status: CourtStatus.active
    },
    select: {
      id: true,
      name: true,
      district: true,
      supportedSports: true
    },
    orderBy: {
      name: "asc"
    }
  });

  if (courts.length === 0) {
    throw new Error("В базе нет активных клубов/кортов. Сначала импортируй или засейди clubs.");
  }

  const creators = users.slice(0, Math.min(options.creators, users.length - 1));
  let createdSearches = 0;
  let createdResponses = 0;

  for (const [creatorIndex, creator] of creators.entries()) {
    const creatorSports = normalizeSports(creator.preferredSports);
    const sports = creatorSports.length > 0 ? creatorSports : [Sport.tennis];
    const preferredDistricts = normalizeStrings(creator.preferredDistricts);

    for (let searchIndex = 0; searchIndex < options.perUser; searchIndex += 1) {
      const absoluteIndex = creatorIndex * options.perUser + searchIndex;
      const sport = pick(sports, searchIndex);
      const format = pickFormat(creator, sport, absoluteIndex);
      const startsAt = buildStartsAt(absoluteIndex);
      const court = pickCourtForSport(courts, sport, creator.district, absoluteIndex);
      const selfLevel = levelForSport(creator, sport);
      const playersNeeded = playersNeededForSport(sport, format, absoluteIndex);
      const searchDistricts = preferredDistricts.length > 0 ? preferredDistricts : creator.district ? [creator.district] : [];
      const candidateResponders = users
        .filter((user) => user.id !== creator.id && normalizeSports(user.preferredSports).includes(sport))
        .slice(0, Math.min(options.responses, playersNeeded + 1));

      if (options.dryRun) {
        createdSearches += 1;
        createdResponses += candidateResponders.length;
        console.log(
          `[dry-run] Поиск: ${creator.name ?? creator.email}, ${SPORT_LABELS[sport]}, ${startsAt.toLocaleString(
            "ru-RU"
          )}, ищем ${playersNeeded}, откликов ${candidateResponders.length}`
        );
        continue;
      }

      const search = await prisma.gameSearch.create({
        data: {
          createdByUserId: creator.id,
          preferredCourtId: court?.id ?? null,
          preferredDistricts: searchDistricts,
          preferredDays: [DAY_KEYS[startsAt.getDay()]],
          preferredTimeRanges: [timeRangeForDate(startsAt)],
          searchType: GameSearchType.hot,
          hotWindow: hotWindowForDate(startsAt),
          hotStartsAt: startsAt,
          durationMinutes: absoluteIndex % 2 === 0 ? 90 : 60,
          hasCourtBooked: Boolean(court),
          sport,
          selfLevel,
          selfLevelUnknown: false,
          desiredLevelMin: Math.max(1, selfLevel - 2),
          desiredLevelMax: Math.min(10, selfLevel + 2),
          format,
          playersNeeded,
          comment: buildComment(sport, court, absoluteIndex),
          status: GameSearchStatus.active,
          isActive: true
        }
      });
      createdSearches += 1;

      for (const responder of candidateResponders) {
        await prisma.gameSearchResponse.upsert({
          where: {
            gameSearchId_responderUserId: {
              gameSearchId: search.id,
              responderUserId: responder.id
            }
          },
          update: {
            message: `${SIMULATION_MARKER} Готов(а) откликнуться на этот слот.`,
            status: GameSearchResponseStatus.pending
          },
          create: {
            gameSearchId: search.id,
            responderUserId: responder.id,
            message: `${SIMULATION_MARKER} Готов(а) откликнуться на этот слот.`,
            status: GameSearchResponseStatus.pending
          }
        });
        createdResponses += 1;
      }

      console.log(
        `Создан поиск ${search.id}: ${creator.name ?? creator.email}, ${SPORT_LABELS[sport]}, ${startsAt.toLocaleString("ru-RU")}, ищем ${playersNeeded}`
      );
    }
  }

  console.log(`Готово: создано поисков ${createdSearches}, откликов ${createdResponses}.`);
  console.log(
    "Пример: npm run simulate:created-searches -- --creators=4 --per-user=3 --responses=2 --reset=true"
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
