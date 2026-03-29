import { readFile } from "node:fs/promises";
import path from "node:path";
import {
  CourtSetting,
  GameRequestStatus,
  GameSearchResponseStatus,
  GameSearchStatus,
  GameSearchType,
  HotSearchWindow,
  MatchStatus,
  PlayFormat,
  Sport,
  Surface
} from "@prisma/client";

import { DEFAULT_CITY, DISTRICT_MAP_AREAS, type DistrictOption } from "@/lib/constants";
import { prisma } from "@/lib/prisma";
import { importClubsFromWorkbook } from "./import-clubs";

async function main() {
  await prisma.chatMessage.deleteMany();
  await prisma.gameRequest.deleteMany();
  await prisma.gameSearch.deleteMany();
  await prisma.match.deleteMany();
  await prisma.swipe.deleteMany();
  await prisma.authCode.deleteMany();
  await prisma.session.deleteMany();
  await prisma.court.deleteMany();
  await prisma.user.deleteMany();
  await prisma.metro.deleteMany();
  await prisma.district.deleteMany();

  const districtsReference = await loadReferenceRows("districts-reference.csv");
  const metrosReference = await loadReferenceRows("metros-spb.reference.csv");

  await prisma.district.createMany({
    data: districtsReference.map((row) => {
      const code = row.code as DistrictOption;
      const area = DISTRICT_MAP_AREAS[code];

      return {
        code,
        name: row.label,
        city: DEFAULT_CITY,
        color: area?.color ?? null,
        centerLat: area?.center.lat ?? null,
        centerLng: area?.center.lng ?? null,
        polygon: area?.polygon ?? null,
        searchHints: area?.searchHints ?? []
      };
    })
  });

  await prisma.metro.createMany({
    data: metrosReference.map((row) => ({
      name: row.name,
      city: DEFAULT_CITY
    }))
  });

  const metros = await prisma.metro.findMany();
  const metroByName = new Map(metros.map((metro) => [metro.name, metro.id]));

  const tomorrowAt1930 = new Date();
  tomorrowAt1930.setDate(tomorrowAt1930.getDate() + 1);
  tomorrowAt1930.setHours(19, 30, 0, 0);

  const users = await Promise.all(
    [
      {
        email: "anna@tennis.dev",
        name: "Анна Волкова",
        age: 27,
        city: "Санкт-Петербург",
        district: "petrogradsky",
        homeLat: 59.9539,
        homeLng: 30.3158,
        tennisLevel: 5,
        preferredSports: [Sport.tennis, Sport.padel],
        sportLevels: { tennis: 5, padel: 4 },
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.clay,
        bio: "Люблю вечерние розыгрыши, дисциплинированную работу по диагонали и быстрое бронирование корта.",
        avatarUrl: "/demo/avatars/anna.svg",
        searchRadiusKm: 18,
        availableDays: ["monday", "wednesday", "saturday"],
        availableTimeRanges: ["evening", "morning"],
        availableTimeSlots: ["monday-evening", "wednesday-evening", "saturday-morning"],
        availabilityByDay: {
          monday: ["evening"],
          wednesday: ["evening"],
          saturday: ["morning"]
        },
        isLookingForGame: true
      },
      {
        email: "elena@tennis.dev",
        name: "Елена Козлова",
        age: 29,
        city: "Санкт-Петербург",
        district: "central",
        homeLat: 59.9346,
        homeLng: 30.3342,
        tennisLevel: 6,
        preferredSports: [Sport.badminton, Sport.yoga],
        sportLevels: { badminton: 6, yoga: 4 },
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.any,
        bio: "Ищу стабильные игры в бадминтон и люблю совмещать спорт с вечерней йогой.",
        avatarUrl: "/demo/avatars/elena.svg",
        searchRadiusKm: 16,
        availableDays: ["tuesday", "thursday", "sunday"],
        availableTimeRanges: ["evening", "day"],
        availableTimeSlots: ["tuesday-evening", "thursday-evening", "sunday-day"],
        availabilityByDay: {
          tuesday: ["evening"],
          thursday: ["evening"],
          sunday: ["day"]
        },
        isLookingForGame: true
      },
      {
        email: "maria@tennis.dev",
        name: "Мария Соколова",
        age: 31,
        city: "Санкт-Петербург",
        district: "admiralteysky",
        homeLat: 59.9196,
        homeLng: 30.3015,
        tennisLevel: 6,
        preferredSports: [Sport.padel, Sport.fitness],
        sportLevels: { padel: 6, fitness: 5 },
        preferredPlayFormat: PlayFormat.both,
        preferredSurface: Surface.hard,
        bio: "Люблю быстрые одиночки в падел и часто могу сорваться в зал в тот же день.",
        avatarUrl: "/demo/avatars/maria.svg",
        searchRadiusKm: 22,
        availableDays: ["monday", "friday", "saturday"],
        availableTimeRanges: ["day", "evening", "morning"],
        availableTimeSlots: ["monday-day", "friday-evening", "saturday-morning"],
        availabilityByDay: {
          monday: ["day"],
          friday: ["evening"],
          saturday: ["morning"]
        },
        isLookingForGame: false
      },
      {
        email: "daria@tennis.dev",
        name: "Дарья Ким",
        age: 25,
        city: "Санкт-Петербург",
        district: "primorsky",
        homeLat: 60.0054,
        homeLng: 30.2651,
        tennisLevel: 4,
        preferredSports: [Sport.volleyball, Sport.badminton, Sport.football],
        sportLevels: { volleyball: 5, badminton: 4, football: 5 },
        preferredPlayFormat: PlayFormat.doubles,
        preferredSurface: Surface.any,
        bio: "Ищу регулярные командные игры на севере города и быстрые договоренности без лишней переписки.",
        avatarUrl: "/demo/avatars/daria.svg",
        searchRadiusKm: 24,
        availableDays: ["wednesday", "friday", "sunday"],
        availableTimeRanges: ["evening"],
        availableTimeSlots: ["wednesday-evening", "friday-evening", "sunday-evening"],
        availabilityByDay: {
          wednesday: ["evening"],
          friday: ["evening"],
          sunday: ["evening"]
        },
        isLookingForGame: true
      },
      {
        email: "sofia@tennis.dev",
        name: "София Петрова",
        age: 26,
        city: "Санкт-Петербург",
        district: "kalininsky",
        homeLat: 59.9723,
        homeLng: 30.3108,
        tennisLevel: 5,
        preferredSports: [Sport.table_tennis, Sport.tennis],
        sportLevels: { table_tennis: 6, tennis: 5 },
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.any,
        bio: "Надежный партнер для часовых сессий и быстрого согласования игры.",
        avatarUrl: "/demo/avatars/sofia.svg",
        searchRadiusKm: 20,
        availableDays: ["tuesday", "saturday", "sunday"],
        availableTimeRanges: ["morning", "day"],
        availableTimeSlots: ["tuesday-morning", "saturday-morning", "sunday-day"],
        availabilityByDay: {
          tuesday: ["morning"],
          saturday: ["morning"],
          sunday: ["day"]
        },
        isLookingForGame: true
      },
      {
        email: "nina@tennis.dev",
        name: "Нина Лебедева",
        age: 33,
        city: "Санкт-Петербург",
        district: "nevsky",
        homeLat: 59.9412,
        homeLng: 30.3776,
        tennisLevel: 7,
        preferredSports: [Sport.squash, Sport.boxing],
        sportLevels: { squash: 7, boxing: 6 },
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.any,
        bio: "Люблю интенсивные тренировки, спарринги в сквош и четкий тайминг без долгих согласований.",
        avatarUrl: "/demo/avatars/nina.svg",
        searchRadiusKm: 25,
        availableDays: ["monday", "thursday"],
        availableTimeRanges: ["day", "evening"],
        availableTimeSlots: ["monday-day", "thursday-evening"],
        availabilityByDay: {
          monday: ["day"],
          thursday: ["evening"]
        },
        isLookingForGame: false
      }
    ].map((user) =>
      prisma.user.create({
        data: {
          ...user,
          isVerified: true,
          onboardingCompleted: true
        }
      })
    )
  );

  const courts = await Promise.all(
    [
      {
        name: "Крестовский Tennis & Padel Club",
        address: "Крестовский проспект, 21",
        city: "Санкт-Петербург",
        district: "petrogradsky",
        nearestMetroId: metroByName.get("Крестовский остров"),
        locationLat: 59.9722,
        locationLng: 30.2324,
        surface: Surface.clay,
        setting: CourtSetting.outdoor,
        supportedSports: [Sport.tennis, Sport.padel, Sport.table_tennis],
        priceRange: "$$",
        rating: 4.8,
        sourceType: "manual",
        bookingUrl: "https://example.com/krestovsky-tennis"
      },
      {
        name: "Петроград Indoor Arena",
        address: "Большой проспект П.С., 98",
        city: "Санкт-Петербург",
        district: "petrogradsky",
        nearestMetroId: metroByName.get("Петроградская"),
        locationLat: 59.9667,
        locationLng: 30.3119,
        surface: Surface.hard,
        setting: CourtSetting.indoor,
        supportedSports: [Sport.badminton, Sport.squash, Sport.table_tennis],
        priceRange: "$$$",
        rating: 4.7,
        sourceType: "manual",
        bookingUrl: "https://example.com/petrograd-arena"
      },
      {
        name: "Приморский MultiSport Center",
        address: "Приморский проспект, 72",
        city: "Санкт-Петербург",
        district: "primorsky",
        nearestMetroId: metroByName.get("Беговая"),
        locationLat: 59.9854,
        locationLng: 30.2297,
        surface: Surface.hard,
        setting: CourtSetting.outdoor,
        supportedSports: [Sport.football, Sport.volleyball, Sport.fitness, Sport.yoga],
        priceRange: "$$",
        rating: 4.6,
        sourceType: "manual",
        bookingUrl: "https://example.com/primorsky-multisport"
      },
      {
        name: "Невский Court House",
        address: "Лиговский проспект, 50",
        city: "Санкт-Петербург",
        district: "central",
        nearestMetroId: metroByName.get("Лиговский проспект"),
        locationLat: 59.9207,
        locationLng: 30.3615,
        surface: Surface.hard,
        setting: CourtSetting.indoor,
        supportedSports: [Sport.tennis, Sport.badminton, Sport.boxing, Sport.fitness],
        priceRange: "$$",
        rating: 4.5,
        sourceType: "manual",
        bookingUrl: "https://example.com/nevsky-court-house"
      },
      {
        name: "Московский Football Hub",
        address: "Московский проспект, 183",
        city: "Санкт-Петербург",
        district: "moskovsky",
        nearestMetroId: metroByName.get("Московская"),
        locationLat: 59.8519,
        locationLng: 30.3211,
        surface: Surface.hard,
        setting: CourtSetting.outdoor,
        supportedSports: [Sport.football, Sport.volleyball],
        priceRange: "$$$",
        rating: 4.7,
        sourceType: "manual",
        bookingUrl: "https://example.com/moskovsky-football-hub"
      },
      {
        name: "Невский Racket Lab",
        address: "Проспект Большевиков, 18",
        city: "Санкт-Петербург",
        district: "nevsky",
        nearestMetroId: metroByName.get("Проспект Большевиков"),
        locationLat: 59.9189,
        locationLng: 30.4688,
        surface: Surface.hard,
        setting: CourtSetting.indoor,
        supportedSports: [Sport.table_tennis, Sport.badminton, Sport.squash],
        priceRange: "$$",
        rating: 4.6,
        sourceType: "manual",
        bookingUrl: "https://example.com/nevsky-racket-lab"
      },
      {
        name: "Васька Padel Yard",
        address: "Малый проспект В.О., 64",
        city: "Санкт-Петербург",
        district: "vasileostrovsky",
        nearestMetroId: metroByName.get("Василеостровская"),
        locationLat: 59.9448,
        locationLng: 30.2497,
        surface: Surface.hard,
        setting: CourtSetting.indoor,
        supportedSports: [Sport.padel, Sport.tennis],
        priceRange: "$$$",
        rating: 4.8,
        sourceType: "manual",
        bookingUrl: "https://example.com/padel-yard"
      },
      {
        name: "Центр Balance & Yoga",
        address: "Набережная Обводного канала, 118",
        city: "Санкт-Петербург",
        district: "admiralteysky",
        nearestMetroId: metroByName.get("Балтийская"),
        locationLat: 59.9102,
        locationLng: 30.3054,
        surface: Surface.any,
        setting: CourtSetting.indoor,
        supportedSports: [Sport.yoga, Sport.fitness, Sport.boxing],
        priceRange: "$$",
        rating: 4.4,
        sourceType: "manual",
        bookingUrl: "https://example.com/balance-yoga"
      },
      {
        name: "Калининский Sports Hall",
        address: "Гражданский проспект, 84",
        city: "Санкт-Петербург",
        district: "kalininsky",
        nearestMetroId: metroByName.get("Академическая"),
        locationLat: 60.0142,
        locationLng: 30.4091,
        surface: Surface.hard,
        setting: CourtSetting.indoor,
        supportedSports: [Sport.volleyball, Sport.badminton, Sport.fitness],
        priceRange: "$",
        rating: 4.3,
        sourceType: "manual",
        bookingUrl: "https://example.com/kalininsky-hall"
      }
    ].map((court) => prisma.court.create({ data: court }))
  );

  const anna = users[0];
  const elena = users[1];
  const maria = users[2];
  const daria = users[3];
  const sofia = users[4];
  const gameSearches = await Promise.all([
    prisma.gameSearch.create({
      data: {
        createdByUserId: anna.id,
        preferredCourtId: courts[0].id,
        preferredDays: ["wednesday", "saturday"],
        preferredTimeRanges: ["evening"],
        searchType: GameSearchType.regular,
        hotWindow: null,
        hasCourtBooked: false,
        sport: Sport.tennis,
        format: PlayFormat.singles,
        comment: "Могу играть после работы, предпочитаю быстрое подтверждение.",
        status: GameSearchStatus.in_review,
        isActive: true
      }
    }),
    prisma.gameSearch.create({
      data: {
        createdByUserId: elena.id,
        preferredCourtId: courts[1].id,
        preferredDays: ["thursday", "sunday"],
        preferredTimeRanges: ["evening", "day"],
        searchType: GameSearchType.regular,
        hotWindow: null,
        hasCourtBooked: false,
        sport: Sport.badminton,
        format: PlayFormat.singles,
        comment: "Ищу корт ближе к центру и сессию с упором на розыгрыши.",
        status: GameSearchStatus.active,
        isActive: true
      }
    }),
    prisma.gameSearch.create({
      data: {
        createdByUserId: sofia.id,
        preferredCourtId: courts[1].id,
        preferredDays: ["monday"],
        preferredTimeRanges: ["evening"],
        searchType: GameSearchType.hot,
        hotWindow: HotSearchWindow.tomorrow,
        hotStartsAt: tomorrowAt1930,
        durationMinutes: 90,
        hasCourtBooked: true,
        sport: Sport.table_tennis,
        format: PlayFormat.singles,
        comment: "Игрок сорвался на завтра вечером. Стол уже забронирован, нужен партнер срочно.",
        status: GameSearchStatus.in_review,
        isActive: true
      }
    }),
    prisma.gameSearch.create({
      data: {
        createdByUserId: daria.id,
        preferredCourtId: courts[4].id,
        preferredDays: ["friday"],
        preferredTimeRanges: ["evening"],
        searchType: GameSearchType.regular,
        hotWindow: null,
        hasCourtBooked: true,
        sport: Sport.football,
        format: PlayFormat.doubles,
        playersNeeded: 4,
        comment: "Собираю мини-футбол на пятницу вечером. Поле уже есть, нужно ещё несколько человек.",
        status: GameSearchStatus.in_review,
        isActive: true
      }
    })
  ]);

  await prisma.gameSearchResponse.createMany({
    data: [
      {
        gameSearchId: gameSearches[0].id,
        responderUserId: sofia.id,
        message: "Свободна в среду вечером, могу быстро подтвердить.",
        status: GameSearchResponseStatus.pending
      },
      {
        gameSearchId: gameSearches[0].id,
        responderUserId: daria.id,
        message: "Суббота мне тоже подходит.",
        status: GameSearchResponseStatus.pending
      },
      {
        gameSearchId: gameSearches[3].id,
        responderUserId: anna.id,
        message: "Могу в пятницу вечером, если нужен ещё один игрок.",
        status: GameSearchResponseStatus.approved
      },
      {
        gameSearchId: gameSearches[3].id,
        responderUserId: elena.id,
        message: "Тоже смогу присоединиться после работы.",
        status: GameSearchResponseStatus.pending
      },
      {
        gameSearchId: gameSearches[2].id,
        responderUserId: anna.id,
        message: "Могу подстроиться завтра вечером и быстро подтвердить.",
        status: GameSearchResponseStatus.pending
      }
    ]
  });

  await prisma.swipe.createMany({
    data: [
      { fromUserId: anna.id, toUserId: elena.id, action: "like" },
      { fromUserId: elena.id, toUserId: anna.id, action: "like" },
      { fromUserId: anna.id, toUserId: maria.id, action: "like" },
      { fromUserId: maria.id, toUserId: anna.id, action: "dislike" }
    ]
  });

  const match = await prisma.match.create({
    data: {
      user1Id: anna.id < elena.id ? anna.id : elena.id,
      user2Id: anna.id < elena.id ? elena.id : anna.id,
      status: MatchStatus.active
    }
  });

  await prisma.chatMessage.createMany({
    data: [
      {
        matchId: match.id,
        senderUserId: anna.id,
        text: "Привет! Готова сыграть на грунте завтра вечером?"
      },
      {
        matchId: match.id,
        senderUserId: elena.id,
        text: "Да, если закрепим корт поближе к центру."
      }
    ]
  });

  await prisma.gameRequest.create({
    data: {
      matchId: match.id,
      createdByUserId: anna.id,
      matchedUserId: elena.id,
      proposedCourtId: courts[0].id,
      proposedDatetime: new Date(Date.now() + 1000 * 60 * 60 * 24),
      levelRangeMin: 4,
      levelRangeMax: 6,
      sport: Sport.tennis,
      format: PlayFormat.singles,
      comment: "Могу сразу подтвердить и забронировать.",
      status: GameRequestStatus.pending
    }
  });

  const archivedMatch = await prisma.match.create({
    data: {
      user1Id: anna.id < sofia.id ? anna.id : sofia.id,
      user2Id: anna.id < sofia.id ? sofia.id : anna.id,
      status: MatchStatus.active
    }
  });

  await prisma.chatMessage.createMany({
    data: [
      {
        matchId: archivedMatch.id,
        senderUserId: sofia.id,
        text: "На прошлой неделе можем сыграть в Лужниках вечером?"
      },
      {
        matchId: archivedMatch.id,
        senderUserId: anna.id,
        text: "Да, подтверждаю. После игры отмечу, как прошло."
      }
    ]
  });

  await prisma.gameRequest.create({
    data: {
      matchId: archivedMatch.id,
      createdByUserId: sofia.id,
      matchedUserId: anna.id,
      proposedCourtId: courts[0].id,
      proposedDatetime: new Date(Date.now() - 1000 * 60 * 60 * 24 * 3),
      levelRangeMin: 4,
      levelRangeMax: 6,
      sport: Sport.tennis,
      format: PlayFormat.singles,
      comment: "Старая подтвержденная игра для проверки истории и опроса.",
      status: GameRequestStatus.accepted,
      outcome: null,
      outcomeUpdatedAt: null
    }
  });

  const clubsImportFile = process.env.CLUBS_IMPORT_FILE?.trim();
  if (clubsImportFile) {
    await importClubsFromWorkbook(clubsImportFile);
  }

  console.log("Сиды загружены");
  console.log("Демо-пользователи:", users.map((user) => user.email).join(", "));
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

async function loadReferenceRows(filename: string) {
  const csvPath = path.join(process.cwd(), "docs", "import", filename);
  const content = await readFile(csvPath, "utf8");
  const lines = content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  if (lines.length < 2) {
    return [];
  }

  const headers = lines[0].split(",").map((item) => item.trim());

  return lines.slice(1).map((line) => {
    const values = line.split(",").map((item) => item.trim());
    return headers.reduce<Record<string, string>>((accumulator, header, index) => {
      accumulator[header] = values[index] ?? "";
      return accumulator;
    }, {});
  });
}
