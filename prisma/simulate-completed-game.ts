import {
  CourtSetting,
  GameRequestStatus,
  MatchStatus,
  PlayFormat,
  Prisma,
  Sport,
  Surface
} from "@prisma/client";

import { DEFAULT_CITY } from "@/lib/constants";
import { courtSupportsSport } from "@/lib/courts";
import { prisma } from "@/lib/prisma";
import { buildCompletedGameSimulationDatetime } from "@/server/game-reports";
import { normalizeMatchPair } from "@/server/matching";

type CliOptions = {
  userId?: string;
  email?: string;
  sport: Sport;
  format: PlayFormat;
  durationMinutes: number;
  courtId?: string;
  allowProduction: boolean;
};

const SIM_OPPONENT_EMAIL = "sim-completed-game-opponent@tennis.local";

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
    userId: args.get("user-id"),
    email: args.get("email")?.trim().toLowerCase(),
    sport: parseEnumOption(args.get("sport"), Sport, Sport.tennis),
    format: parseEnumOption(args.get("format"), PlayFormat, PlayFormat.singles),
    durationMinutes: Math.max(30, Math.min(240, Number(args.get("duration") ?? 90))),
    courtId: args.get("court-id"),
    allowProduction: args.get("allow-production") === "true"
  };
}

function parseEnumOption<T extends Record<string, string>>(value: string | undefined, source: T, fallback: T[keyof T]) {
  const values = Object.values(source) as Array<T[keyof T]>;
  return value && values.includes(value as T[keyof T]) ? (value as T[keyof T]) : fallback;
}

function assertSimulationAllowed(options: CliOptions) {
  if (process.env.NODE_ENV === "production" && !options.allowProduction) {
    throw new Error("Refusing to mutate production data. Pass --allow-production only if this is intentional.");
  }
}

async function resolveRecipient(options: CliOptions) {
  if (options.userId) {
    const user = await prisma.user.findUnique({ where: { id: options.userId } });
    if (!user) {
      throw new Error(`Пользователь ${options.userId} не найден.`);
    }
    return user;
  }

  if (options.email) {
    const user = await prisma.user.findUnique({ where: { email: options.email } });
    if (!user) {
      throw new Error(`Пользователь с email ${options.email} не найден.`);
    }
    return user;
  }

  const latestSession = await prisma.session.findFirst({
    where: {
      expiresAt: {
        gt: new Date()
      }
    },
    include: {
      user: true
    },
    orderBy: {
      createdAt: "desc"
    }
  });

  if (!latestSession) {
    throw new Error("Нет активной сессии. Передай --email=<email> или --user-id=<id>.");
  }

  return latestSession.user;
}

async function ensureOpponent(sport: Sport) {
  return prisma.user.upsert({
    where: {
      email: SIM_OPPONENT_EMAIL
    },
    update: {
      name: "Симулятор Фотоотчёта",
      preferredSports: [sport] as Prisma.InputJsonValue,
      sportLevels: { [sport]: 5 } as Prisma.InputJsonValue,
      onboardingCompleted: true,
      isVerified: true,
      isLookingForGame: true
    },
    create: {
      email: SIM_OPPONENT_EMAIL,
      name: "Симулятор Фотоотчёта",
      age: 29,
      city: DEFAULT_CITY,
      district: "central",
      preferredDistricts: ["central"] as Prisma.InputJsonValue,
      tennisLevel: sport === Sport.tennis ? 5 : null,
      preferredSports: [sport] as Prisma.InputJsonValue,
      sportLevels: { [sport]: 5 } as Prisma.InputJsonValue,
      preferredPlayFormat: PlayFormat.both,
      preferredSurface: Surface.any,
      bio: "Системный игрок для проверки завершённой игры и фотоотчёта.",
      availableDays: ["monday", "wednesday", "saturday"] as Prisma.InputJsonValue,
      availableTimeRanges: ["evening"] as Prisma.InputJsonValue,
      availabilityByDay: { monday: ["evening"], wednesday: ["evening"], saturday: ["evening"] } as Prisma.InputJsonValue,
      onboardingCompleted: true,
      isVerified: true,
      isLookingForGame: true
    }
  });
}

async function resolveCourt(options: CliOptions) {
  if (options.courtId) {
    const court = await prisma.court.findUnique({ where: { id: options.courtId } });
    if (!court) {
      throw new Error(`Корт ${options.courtId} не найден.`);
    }
    return court;
  }

  const courts = await prisma.court.findMany({
    orderBy: {
      updatedAt: "desc"
    },
    take: 100
  });
  const matchingCourt = courts.find((court) => courtSupportsSport(court.supportedSports, options.sport));
  const fallbackCourt = matchingCourt ?? courts[0];

  if (fallbackCourt) {
    return fallbackCourt;
  }

  return prisma.court.create({
    data: {
      name: "Симуляционный корт",
      address: "Локальная база",
      city: DEFAULT_CITY,
      locationLat: 59.9386,
      locationLng: 30.3141,
      surface: Surface.hard,
      setting: CourtSetting.indoor,
      supportedSports: [options.sport] as Prisma.InputJsonValue,
      priceRange: "demo",
      sourceType: "simulation"
    }
  });
}

async function main() {
  const options = parseOptions();
  assertSimulationAllowed(options);

  const recipient = await resolveRecipient(options);
  const opponent = await ensureOpponent(options.sport);

  if (opponent.id === recipient.id) {
    throw new Error("Синтетический соперник совпал с получателем. Передай другого пользователя через --email или --user-id.");
  }

  const court = await resolveCourt(options);
  const [user1Id, user2Id] = normalizeMatchPair(opponent.id, recipient.id);
  const proposedDatetime = buildCompletedGameSimulationDatetime(options.durationMinutes);

  const result = await prisma.$transaction(async (tx) => {
    const match = await tx.match.upsert({
      where: {
        user1Id_user2Id: {
          user1Id,
          user2Id
        }
      },
      update: {
        status: MatchStatus.active,
        updatedAt: new Date()
      },
      create: {
        user1Id,
        user2Id,
        status: MatchStatus.active
      }
    });

    await tx.chatMessage.create({
      data: {
        matchId: match.id,
        senderUserId: opponent.id,
        text: "Симуляция: я предложил игру, она уже подтверждена и завершена. Можно проверить фотоотчёт."
      }
    });

    const gameRequest = await tx.gameRequest.create({
      data: {
        matchId: match.id,
        createdByUserId: opponent.id,
        matchedUserId: recipient.id,
        proposedCourtId: court.id,
        proposedDatetime,
        durationMinutes: options.durationMinutes,
        levelRangeMin: 4,
        levelRangeMax: 6,
        sport: options.sport,
        format: options.format,
        comment: "Симуляция завершённой подтверждённой игры для проверки фотоотчёта.",
        status: GameRequestStatus.accepted,
        outcome: null,
        outcomeUpdatedAt: null
      }
    });

    await tx.chatMessage.create({
      data: {
        matchId: match.id,
        gameRequestId: gameRequest.id,
        senderUserId: opponent.id,
        text: "Игра завершена. Добавь фотоотчёт, если всё ок."
      }
    });

    return { match, gameRequest };
  });

  console.log("Создана входящая подтверждённая завершённая игра.");
  console.log(`Получатель: ${recipient.name ?? recipient.email} (${recipient.email})`);
  console.log(`Соперник: ${opponent.name ?? opponent.email}`);
  console.log(`GameRequest: ${result.gameRequest.id}`);
  console.log(`Match: ${result.match.id}`);
  console.log(`Время начала: ${proposedDatetime.toISOString()}`);
  console.log(`Корт: ${court.name}`);
  console.log(`Открой: /play/games/${result.gameRequest.id}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
