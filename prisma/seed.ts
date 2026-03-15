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

import { prisma } from "@/lib/prisma";

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

  const users = await Promise.all(
    [
      {
        email: "anna@tennis.dev",
        name: "Анна Волкова",
        age: 27,
        city: "Москва",
        homeLat: 55.7518,
        homeLng: 37.6158,
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
        isLookingForGame: true
      },
      {
        email: "elena@tennis.dev",
        name: "Елена Козлова",
        age: 29,
        city: "Москва",
        homeLat: 55.7642,
        homeLng: 37.6015,
        tennisLevel: 5,
        preferredSports: [Sport.tennis, Sport.badminton],
        sportLevels: { tennis: 5, badminton: 6 },
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.clay,
        bio: "Люблю стабильные розыгрыши и игру на счет. Лучшие окна: вечера в будни.",
        avatarUrl: "/demo/avatars/elena.svg",
        searchRadiusKm: 16,
        availableDays: ["tuesday", "thursday", "sunday"],
        availableTimeRanges: ["evening", "day"],
        availableTimeSlots: ["tuesday-evening", "thursday-evening", "sunday-day"],
        isLookingForGame: true
      },
      {
        email: "maria@tennis.dev",
        name: "Мария Соколова",
        age: 31,
        city: "Москва",
        homeLat: 55.7381,
        homeLng: 37.5886,
        tennisLevel: 6,
        preferredSports: [Sport.padel, Sport.pickleball],
        sportLevels: { padel: 6, pickleball: 5 },
        preferredPlayFormat: PlayFormat.both,
        preferredSurface: Surface.hard,
        bio: "Люблю быстрые одиночки, иногда играю пары, могу подтвердить игру в тот же день.",
        avatarUrl: "/demo/avatars/maria.svg",
        searchRadiusKm: 22,
        availableDays: ["monday", "friday", "saturday"],
        availableTimeRanges: ["day", "evening", "morning"],
        availableTimeSlots: ["monday-day", "friday-evening", "saturday-morning"],
        isLookingForGame: false
      },
      {
        email: "daria@tennis.dev",
        name: "Дарья Ким",
        age: 25,
        city: "Москва",
        homeLat: 55.7835,
        homeLng: 37.6411,
        tennisLevel: 4,
        preferredSports: [Sport.badminton, Sport.squash],
        sportLevels: { badminton: 4, squash: 5 },
        preferredPlayFormat: PlayFormat.doubles,
        preferredSurface: Surface.hard,
        bio: "Ищу регулярные парные игры на севере города.",
        avatarUrl: "/demo/avatars/daria.svg",
        searchRadiusKm: 24,
        availableDays: ["wednesday", "friday", "sunday"],
        availableTimeRanges: ["evening"],
        availableTimeSlots: ["wednesday-evening", "friday-evening", "sunday-evening"],
        isLookingForGame: true
      },
      {
        email: "sofia@tennis.dev",
        name: "София Петрова",
        age: 26,
        city: "Москва",
        homeLat: 55.7452,
        homeLng: 37.5607,
        tennisLevel: 5,
        preferredSports: [Sport.tennis, Sport.pickleball],
        sportLevels: { tennis: 5, pickleball: 6 },
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.any,
        bio: "Надежный партнер для часовых сессий и быстрого согласования игры.",
        avatarUrl: "/demo/avatars/sofia.svg",
        searchRadiusKm: 20,
        availableDays: ["tuesday", "saturday", "sunday"],
        availableTimeRanges: ["morning", "day"],
        availableTimeSlots: ["tuesday-morning", "saturday-morning", "sunday-day"],
        isLookingForGame: true
      },
      {
        email: "nina@tennis.dev",
        name: "Нина Лебедева",
        age: 33,
        city: "Москва",
        homeLat: 55.7701,
        homeLng: 37.676,
        tennisLevel: 7,
        preferredSports: [Sport.squash, Sport.tennis],
        sportLevels: { squash: 7, tennis: 6 },
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.clay,
        bio: "Люблю соревновательные тренировочные сеты и структурированные упражнения.",
        avatarUrl: "/demo/avatars/nina.svg",
        searchRadiusKm: 25,
        availableDays: ["monday", "thursday"],
        availableTimeRanges: ["day", "evening"],
        availableTimeSlots: ["monday-day", "thursday-evening"],
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
        name: "Лужники Клей Клаб",
        address: "Лужнецкая набережная, 24",
        city: "Москва",
        locationLat: 55.7158,
        locationLng: 37.5533,
        surface: Surface.clay,
        setting: CourtSetting.outdoor,
        priceRange: "$$",
        rating: 4.8,
        sourceType: "manual",
        bookingUrl: "https://example.com/luzhniki-clay"
      },
      {
        name: "Динамо Индор Арена",
        address: "Ленинградский проспект, 36",
        city: "Москва",
        locationLat: 55.7904,
        locationLng: 37.5605,
        surface: Surface.hard,
        setting: CourtSetting.indoor,
        priceRange: "$$$",
        rating: 4.7,
        sourceType: "manual",
        bookingUrl: "https://example.com/dynamo"
      },
      {
        name: "Крылатское Теннис Поинт",
        address: "Крылатская улица, 2",
        city: "Москва",
        locationLat: 55.7664,
        locationLng: 37.421,
        surface: Surface.hard,
        setting: CourtSetting.outdoor,
        priceRange: "$$",
        rating: 4.6,
        sourceType: "manual",
        bookingUrl: "https://example.com/krylatskoye"
      },
      {
        name: "Сити Смеш Павильон",
        address: "Проспект Мира, 119",
        city: "Москва",
        locationLat: 55.8298,
        locationLng: 37.6331,
        surface: Surface.hard,
        setting: CourtSetting.indoor,
        priceRange: "$$",
        rating: 4.5,
        sourceType: "manual",
        bookingUrl: "https://example.com/city-smash"
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
        preferredCourtId: courts[2].id,
        preferredDays: ["monday"],
        preferredTimeRanges: ["evening"],
        searchType: GameSearchType.hot,
        hotWindow: HotSearchWindow.today,
        hasCourtBooked: true,
        sport: Sport.tennis,
        format: PlayFormat.singles,
        comment: "Игрок сорвался сегодня вечером. Корт уже есть, нужен партнер срочно.",
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
        gameSearchId: gameSearches[2].id,
        responderUserId: anna.id,
        message: "Могу подстроиться сегодня вечером и быстро подтвердить.",
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
