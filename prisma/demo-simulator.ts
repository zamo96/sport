import {
  GameRequestOutcome,
  GameRequestStatus,
  GameSearchResponseStatus,
  GameSearchStatus,
  GameSearchType,
  HotSearchWindow,
  MatchStatus,
  PlayFormat,
  Prisma,
  PrismaClient,
  Sport,
  Surface
} from "@prisma/client";

import { DEFAULT_CITY, DISTRICT_MAP_AREAS, DISTRICT_OPTIONS, SPORT_LABELS, SPORT_OPTIONS, type DistrictOption } from "@/lib/constants";
import { normalizeSports } from "@/lib/sport-levels";

const DAY_KEYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"] as const;
const TIME_RANGE_KEYS = ["morning", "day", "evening"] as const;
const FIRST_NAMES = [
  "Артём",
  "Илья",
  "Максим",
  "Георгий",
  "Лев",
  "Михаил",
  "Матвей",
  "Никита",
  "Егор",
  "Тимофей",
  "Алексей",
  "Роман",
  "Антон",
  "Сергей",
  "Дмитрий",
  "Полина",
  "Виктория",
  "Алина",
  "Карина",
  "Вероника",
  "Ксения",
  "Ольга",
  "Светлана",
  "Юлия",
  "Татьяна",
  "Лилия",
  "Марина",
  "Анастасия",
  "Екатерина",
  "Варвара"
] as const;
const LAST_NAMES = [
  "Иванов",
  "Петров",
  "Смирнов",
  "Кузнецов",
  "Попов",
  "Васильев",
  "Соколов",
  "Михайлов",
  "Новиков",
  "Фёдоров",
  "Морозов",
  "Волков",
  "Соловьёв",
  "Лебедев",
  "Козлов",
  "Степанова",
  "Николаева",
  "Орлова",
  "Макарова",
  "Крылова"
] as const;

type SimUser = {
  id: string;
  name: string | null;
  gender: Prisma.JsonValue | null;
  city: string | null;
  district: string | null;
  homeLat: number | null;
  homeLng: number | null;
  tennisLevel: number | null;
  preferredSports: Prisma.JsonValue | null;
  sportLevels: Prisma.JsonValue | null;
  preferredPlayFormat: PlayFormat;
  preferredSurface: Surface;
  availableDays: Prisma.JsonValue | null;
  availableTimeRanges: Prisma.JsonValue | null;
  availableTimeSlots: Prisma.JsonValue | null;
  searchRadiusKm: number;
  isLookingForGame: boolean;
};

type CreatedSearch = {
  id: string;
  creatorId: string;
  sport: Sport;
  searchType: GameSearchType;
  hotStartsAt: Date | null;
  durationMinutes: number | null;
  preferredCourtId: string | null;
  playersNeeded: number;
  format: PlayFormat;
};

export type LiveTickSummary = {
  users: number;
  swipes: number;
  matches: number;
  searches: number;
  responses: number;
  messages: number;
  gameRequests: number;
};

export const GENERATED_DEMO_USER_COUNT = 50;

export function buildGeneratedDemoUsers(count = GENERATED_DEMO_USER_COUNT): Prisma.UserCreateManyInput[] {
  const random = createRandom(214748364);

  return Array.from({ length: count }, (_, index) => buildGeneratedDemoUser(index + 1, random));
}

export async function runDemoActivitySimulation(
  prisma: PrismaClient,
  options: {
    resetExisting?: boolean;
    seed?: number;
  } = {}
) {
  const resetExisting = options.resetExisting ?? true;
  const random = createRandom(options.seed ?? 918273);

  if (resetExisting) {
    await prisma.chatMessage.deleteMany();
    await prisma.gameRequest.deleteMany();
    await prisma.gameSearch.deleteMany();
    await prisma.match.deleteMany();
    await prisma.swipe.deleteMany();
  }

  const users = (await prisma.user.findMany({
    where: {
      onboardingCompleted: true,
      isVerified: true
    },
    select: {
      id: true,
      name: true,
      gender: true,
      city: true,
      district: true,
      homeLat: true,
      homeLng: true,
      tennisLevel: true,
      preferredSports: true,
      sportLevels: true,
      preferredPlayFormat: true,
      preferredSurface: true,
      availableDays: true,
      availableTimeRanges: true,
      availableTimeSlots: true,
      searchRadiusKm: true,
      isLookingForGame: true
    }
  })) as SimUser[];

  const courts = await prisma.court.findMany({
    select: {
      id: true,
      name: true,
      district: true,
      supportedSports: true
    }
  });

  if (users.length === 0 || courts.length === 0) {
    return;
  }

  const swipeRows = buildSwipeRows(users, random);
  if (swipeRows.length > 0) {
    await prisma.swipe.createMany({
      data: swipeRows,
      skipDuplicates: true
    });
  }

  const matchIdByPair = new Map<string, string>();
  const pairsWithMutualLike = getMutualLikePairs(swipeRows);

  for (const [leftUserId, rightUserId] of pairsWithMutualLike) {
    const [user1Id, user2Id] = leftUserId < rightUserId ? [leftUserId, rightUserId] : [rightUserId, leftUserId];
    const match = await prisma.match.upsert({
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
    matchIdByPair.set(`${user1Id}:${user2Id}`, match.id);
  }

  const baseMessages: Prisma.ChatMessageCreateManyInput[] = [];
  for (const [pairKey, matchId] of matchIdByPair.entries()) {
    const [user1Id, user2Id] = pairKey.split(":");
    const user1 = users.find((user) => user.id === user1Id);
    const user2 = users.find((user) => user.id === user2Id);

    if (!user1 || !user2 || random() < 0.28) {
      continue;
    }

    const sharedSport = getSharedPrimarySport(user1, user2);
    baseMessages.push(
      {
        matchId,
        senderUserId: user1.id,
        text: `Привет! Видел(а), что ты тоже играешь в ${SPORT_LABELS[sharedSport]}. Когда тебе удобнее?`
      },
      {
        matchId,
        senderUserId: user2.id,
        text: "Могу после работы или в выходные. Давай быстро выберем клуб и время."
      }
    );
  }

  if (baseMessages.length > 0) {
    await prisma.chatMessage.createMany({
      data: baseMessages
    });
  }

  const createdSearches: CreatedSearch[] = [];
  const searchCreators = shuffle(users.filter((user) => user.isLookingForGame), random).slice(0, Math.min(22, users.length));

  for (const creator of searchCreators) {
    const sports = normalizeSports(creator.preferredSports);
    if (sports.length === 0) {
      continue;
    }

    const sport = sports[Math.floor(random() * sports.length)];
    const searchType = random() > 0.72 ? GameSearchType.hot : GameSearchType.regular;
    const format = pickSearchFormat(random, creator.preferredPlayFormat, sport);
    const playersNeeded = defaultPlayersNeeded(sport, format, random);
    const preferredCourt = pickCourtForSport(courts, sport, creator.district, random);
    const preferredDays = searchType === GameSearchType.hot ? [DAY_KEYS[new Date().getDay() || 6]] : pickDaysFromUser(creator, random);
    const preferredTimeRanges = searchType === GameSearchType.hot ? [TIME_RANGE_KEYS[Math.floor(random() * TIME_RANGE_KEYS.length)]] : pickTimeRangesFromUser(creator, random);
    const hotWindow = searchType === GameSearchType.hot ? pickHotWindow(random) : null;
    const hotStartsAt = searchType === GameSearchType.hot ? buildHotStartsAt(hotWindow, random) : null;
    const selfLevel = extractSportLevel(creator, sport);
    const selfLevelUnknown = random() > 0.88;

    const search = await prisma.gameSearch.create({
      data: {
        createdByUserId: creator.id,
        preferredCourtId: preferredCourt?.id ?? null,
        preferredDays,
        preferredTimeRanges,
        searchType,
        hotWindow,
        hotStartsAt,
        durationMinutes: searchType === GameSearchType.hot ? [60, 90, 120][Math.floor(random() * 3)] : null,
        hasCourtBooked: random() > 0.45,
        sport,
        selfLevel: selfLevelUnknown ? null : selfLevel,
        selfLevelUnknown,
        desiredLevelMin: Math.max(1, (selfLevel ?? 5) - (random() > 0.6 ? 1 : 2)),
        desiredLevelMax: Math.min(10, (selfLevel ?? 5) + (random() > 0.6 ? 1 : 2)),
        format,
        playersNeeded,
        comment: buildSearchComment(searchType, sport, preferredCourt?.name ?? null),
        status: GameSearchStatus.active,
        isActive: true
      }
    });

    createdSearches.push({
      id: search.id,
      creatorId: creator.id,
      sport,
      searchType,
      hotStartsAt,
      durationMinutes: search.durationMinutes,
      preferredCourtId: preferredCourt?.id ?? null,
      playersNeeded,
      format
    });
  }

  for (const search of createdSearches) {
    const creator = users.find((user) => user.id === search.creatorId);
    if (!creator) {
      continue;
    }

    const candidateResponders = shuffle(
      users.filter((user) => user.id !== creator.id && normalizeSports(user.preferredSports).includes(search.sport)),
      random
    ).slice(0, Math.min(search.playersNeeded + 2, 5));

    const approvedLimit = Math.min(search.playersNeeded, Math.max(1, Math.floor(random() * (search.playersNeeded + 1))));
    let approvedCount = 0;
    let pendingCount = 0;

    for (const responder of candidateResponders) {
      const status =
        approvedCount < approvedLimit && random() > 0.34
          ? GameSearchResponseStatus.approved
          : random() > 0.62
            ? GameSearchResponseStatus.pending
            : GameSearchResponseStatus.rejected;

      if (status === GameSearchResponseStatus.approved) {
        approvedCount += 1;
      }
      if (status === GameSearchResponseStatus.pending) {
        pendingCount += 1;
      }

      await prisma.gameSearchResponse.create({
        data: {
          gameSearchId: search.id,
          responderUserId: responder.id,
          message: buildResponseMessage(search.sport, status),
          status
        }
      });

      if (status !== GameSearchResponseStatus.approved) {
        continue;
      }

      const matchId = await ensureMatch(prisma, matchIdByPair, creator.id, responder.id);
      const proposedCourt = search.preferredCourtId
        ? { id: search.preferredCourtId }
        : pickCourtForSport(courts, search.sport, creator.district, random);
      const proposedDatetime =
        search.hotStartsAt ??
        buildRegularRequestDate(
          pickDaysFromUser(creator, random),
          pickTimeRangesFromUser(creator, random),
          random
        );
      const requestStatus =
        search.searchType === GameSearchType.hot
          ? random() > 0.22
            ? GameRequestStatus.accepted
            : GameRequestStatus.pending
          : random() > 0.58
            ? GameRequestStatus.accepted
            : GameRequestStatus.pending;

      const gameRequest = await prisma.gameRequest.create({
        data: {
          matchId,
          createdByUserId: creator.id,
          matchedUserId: responder.id,
          proposedCourtId: proposedCourt?.id ?? courts[Math.floor(random() * courts.length)]?.id,
          proposedDatetime,
          durationMinutes: search.durationMinutes ?? 90,
          levelRangeMin: 1,
          levelRangeMax: 10,
          sport: search.sport,
          format: search.format,
          comment: buildGameRequestComment(search.searchType, search.sport),
          status: requestStatus,
          outcome:
            requestStatus === GameRequestStatus.accepted && proposedDatetime.getTime() < Date.now() - 1000 * 60 * 60 * 12
              ? random() > 0.25
                ? GameRequestOutcome.played
                : GameRequestOutcome.not_played
              : null,
          outcomeUpdatedAt:
            requestStatus === GameRequestStatus.accepted && proposedDatetime.getTime() < Date.now() - 1000 * 60 * 60 * 12
              ? new Date()
              : null
        }
      });

      await prisma.chatMessage.createMany({
        data: [
          {
            matchId,
            senderUserId: creator.id,
            text: `Привет! Подтверждаю игру по ${SPORT_LABELS[search.sport]}.`
          },
          {
            matchId,
            senderUserId: responder.id,
            text: requestStatus === GameRequestStatus.accepted ? "Супер, беру слот. Встретимся на месте." : "Отлично, жду подтверждение по времени."
          },
          {
            matchId,
            gameRequestId: gameRequest.id,
            senderUserId: creator.id,
            text: search.searchType === GameSearchType.hot ? "Это срочная игра, лучше сразу закрепить время." : "Если всё ок, можем потом ещё сыграть регулярно."
          }
        ]
      });
    }

    await prisma.gameSearch.update({
      where: { id: search.id },
      data: {
        status:
          approvedCount >= search.playersNeeded
            ? GameSearchStatus.matched
            : approvedCount > 0 || pendingCount > 0
              ? GameSearchStatus.in_review
              : random() > 0.7
                ? GameSearchStatus.closed
                : GameSearchStatus.active,
        isActive: approvedCount >= search.playersNeeded ? false : approvedCount === 0 && pendingCount === 0 ? random() > 0.7 ? false : true : true
      }
    });
  }
}

export async function runLiveActivityTick(
  prisma: PrismaClient,
  options: {
    seed?: number;
  } = {}
) {
  const random = createRandom(options.seed ?? Date.now());
  const summary: LiveTickSummary = {
    users: 0,
    swipes: 0,
    matches: 0,
    searches: 0,
    responses: 0,
    messages: 0,
    gameRequests: 0
  };

  const users = (await prisma.user.findMany({
    where: {
      onboardingCompleted: true,
      isVerified: true,
      OR: [{ email: { endsWith: "@sport.dev" } }, { email: { endsWith: "@tennis.dev" } }]
    },
    select: {
      id: true,
      name: true,
      gender: true,
      city: true,
      district: true,
      homeLat: true,
      homeLng: true,
      tennisLevel: true,
      preferredSports: true,
      sportLevels: true,
      preferredPlayFormat: true,
      preferredSurface: true,
      availableDays: true,
      availableTimeRanges: true,
      availableTimeSlots: true,
      searchRadiusKm: true,
      isLookingForGame: true
    }
  })) as SimUser[];

  if (users.filter((user) => user.id).length > 0) {
    summary.users += await createLiveUser(prisma, users.length, random);
  }

  const courts = await prisma.court.findMany({
    select: {
      id: true,
      name: true,
      district: true,
      supportedSports: true
    }
  });

  if (users.length < 2 || courts.length === 0) {
    return summary;
  }

  const actions = shuffle(["swipe", "search", "response", "message", "gameRequest", "user"], random).slice(
    0,
    2 + Math.floor(random() * 3)
  );

  for (const action of actions) {
    if (action === "user") {
      summary.users += await createLiveUser(prisma, users.length + summary.users, random);
    }

    if (action === "swipe") {
      const created = await createLiveSwipe(prisma, users, random);
      summary.swipes += created.swipes;
      summary.matches += created.matches;
    }

    if (action === "search") {
      summary.searches += await createLiveSearch(prisma, users, courts, random);
    }

    if (action === "response") {
      const created = await createLiveResponse(prisma, users, courts, random);
      summary.responses += created.responses;
      summary.matches += created.matches;
      summary.gameRequests += created.gameRequests;
      summary.messages += created.messages;
    }

    if (action === "message") {
      summary.messages += await createLiveMessage(prisma, users, random);
    }

    if (action === "gameRequest") {
      const created = await createLiveGameRequest(prisma, users, courts, random);
      summary.gameRequests += created.gameRequests;
      summary.messages += created.messages;
    }
  }

  return summary;
}

function buildGeneratedDemoUser(index: number, random: () => number): Prisma.UserCreateManyInput {
  const district = DISTRICT_OPTIONS[(index - 1) % DISTRICT_OPTIONS.length];
  const area = DISTRICT_MAP_AREAS[district];
  const firstName = FIRST_NAMES[(index - 1) % FIRST_NAMES.length];
  const lastName = LAST_NAMES[((index - 1) * 3) % LAST_NAMES.length];
  const sports = sampleSports(random, 1 + Math.floor(random() * 3));
  const sportLevels = Object.fromEntries(sports.map((sport) => [sport, 3 + Math.floor(random() * 6)])) as Record<Sport, number>;
  const availabilityByDay = buildAvailability(random);
  const availableDays = Object.keys(availabilityByDay);
  const availableTimeRanges = Array.from(new Set(Object.values(availabilityByDay).flat()));

  return {
    email: `demo.player.${String(index).padStart(3, "0")}@sport.dev`,
    name: `${firstName} ${lastName}`,
    age: 20 + Math.floor(random() * 20),
    gender: index % 5 === 0 ? "female" : index % 3 === 0 ? "male" : null,
    city: DEFAULT_CITY,
    district,
    homeLat: area.center.lat + (random() - 0.5) * 0.04,
    homeLng: area.center.lng + (random() - 0.5) * 0.07,
    tennisLevel: sportLevels[sports[0]] ?? 5,
    preferredSports: sports,
    sportLevels,
    preferredPlayFormat: pickPlayFormat(random, sports[0]),
    preferredSurface: pickSurface(random, sports[0]),
    bio: buildBio(firstName, sports[0], district, random),
    avatarUrl: null,
    searchRadiusKm: 8 + Math.floor(random() * 18),
    availableDays,
    availableTimeRanges,
    availableTimeSlots: availableDays.flatMap((day) => (availabilityByDay[day] ?? []).map((range) => `${day}-${range}`)),
    availabilityByDay,
    isLookingForGame: random() > 0.32,
    isVerified: true,
    onboardingCompleted: true,
    notificationMatches: true,
    notificationMessages: true,
    notificationGames: true,
    notificationSound: true
  };
}

async function createLiveUser(prisma: PrismaClient, currentUserCount: number, random: () => number) {
  if (random() > 0.18) {
    return 0;
  }

  const demoUsersCount = await prisma.user.count({
    where: {
      email: {
        endsWith: "@sport.dev"
      }
    }
  });

  const nextIndex = Math.max(currentUserCount, demoUsersCount) + 1;
  const user = buildGeneratedDemoUser(nextIndex, random);

  await prisma.user.upsert({
    where: {
      email: user.email
    },
    update: {
      name: user.name,
      age: user.age,
      gender: user.gender,
      city: user.city,
      district: user.district,
      homeLat: user.homeLat,
      homeLng: user.homeLng,
      tennisLevel: user.tennisLevel,
      preferredSports: user.preferredSports,
      sportLevels: user.sportLevels,
      preferredPlayFormat: user.preferredPlayFormat,
      preferredSurface: user.preferredSurface,
      bio: user.bio,
      avatarUrl: user.avatarUrl,
      searchRadiusKm: user.searchRadiusKm,
      availableDays: user.availableDays,
      availableTimeRanges: user.availableTimeRanges,
      availableTimeSlots: user.availableTimeSlots,
      availabilityByDay: user.availabilityByDay,
      isLookingForGame: user.isLookingForGame,
      isVerified: true,
      onboardingCompleted: true,
      notificationMatches: true,
      notificationMessages: true,
      notificationGames: true,
      notificationSound: true
    },
    create: user
  });

  return 1;
}

function createRandom(seed: number) {
  let value = seed >>> 0;
  return () => {
    value += 0x6d2b79f5;
    let t = value;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

async function createLiveSwipe(prisma: PrismaClient, users: SimUser[], random: () => number) {
  const initiator = shuffle(users, random)[0];
  if (!initiator) {
    return { swipes: 0, matches: 0 };
  }

  const existingSwipes = await prisma.swipe.findMany({
    where: { fromUserId: initiator.id },
    select: { toUserId: true }
  });
  const alreadySwiped = new Set(existingSwipes.map((swipe) => swipe.toUserId));
  const candidates = shuffle(
    users.filter((candidate) => candidate.id !== initiator.id && !alreadySwiped.has(candidate.id)),
    random
  ).filter((candidate) => compatibilityScore(initiator, candidate) >= 12);

  const target = candidates[0];
  if (!target) {
    return { swipes: 0, matches: 0 };
  }

  const action = compatibilityScore(initiator, target) >= 20 || random() > 0.35 ? "like" : "dislike";
  await prisma.swipe.create({
    data: {
      fromUserId: initiator.id,
      toUserId: target.id,
      action
    }
  });

  if (action !== "like") {
    return { swipes: 1, matches: 0 };
  }

  const reciprocal = await prisma.swipe.findUnique({
    where: {
      fromUserId_toUserId: {
        fromUserId: target.id,
        toUserId: initiator.id
      }
    }
  });

  if (!reciprocal || reciprocal.action !== "like") {
    return { swipes: 1, matches: 0 };
  }

  const [user1Id, user2Id] = initiator.id < target.id ? [initiator.id, target.id] : [target.id, initiator.id];
  const existingMatch = await prisma.match.findUnique({
    where: {
      user1Id_user2Id: {
        user1Id,
        user2Id
      }
    }
  });

  const match = await prisma.match.upsert({
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

  if (!existingMatch) {
    await prisma.chatMessage.create({
      data: {
        matchId: match.id,
        senderUserId: initiator.id,
        text: `Привет! Похоже, у нас совпадает ${SPORT_LABELS[getSharedPrimarySport(initiator, target)].toLowerCase()}.`
      }
    });
  }

  return { swipes: 1, matches: existingMatch ? 0 : 1 };
}

async function createLiveSearch(
  prisma: PrismaClient,
  users: SimUser[],
  courts: Array<{ id: string; name: string; district: string | null; supportedSports: Prisma.JsonValue | null }>,
  random: () => number
) {
  const creator = shuffle(users.filter((user) => user.isLookingForGame), random)[0];
  if (!creator) {
    return 0;
  }

  const activeCount = await prisma.gameSearch.count({
    where: {
      createdByUserId: creator.id,
      isActive: true
    }
  });

  if (activeCount >= 2) {
    return 0;
  }

  const sports = normalizeSports(creator.preferredSports);
  const sport = sports[Math.floor(random() * sports.length)];
  if (!sport) {
    return 0;
  }

  const searchType = random() > 0.75 ? GameSearchType.hot : GameSearchType.regular;
  const format = pickSearchFormat(random, creator.preferredPlayFormat, sport);
  const preferredCourt = pickCourtForSport(courts, sport, creator.district, random);
  const selfLevel = extractSportLevel(creator, sport);

  await prisma.gameSearch.create({
    data: {
      createdByUserId: creator.id,
      preferredCourtId: preferredCourt?.id ?? null,
      preferredDays: searchType === GameSearchType.hot ? [DAY_KEYS[new Date().getDay() || 6]] : pickDaysFromUser(creator, random),
      preferredTimeRanges:
        searchType === GameSearchType.hot ? [TIME_RANGE_KEYS[Math.floor(random() * TIME_RANGE_KEYS.length)]] : pickTimeRangesFromUser(creator, random),
      searchType,
      hotWindow: searchType === GameSearchType.hot ? pickHotWindow(random) : null,
      hotStartsAt: searchType === GameSearchType.hot ? buildHotStartsAt(pickHotWindow(random), random) : null,
      durationMinutes: searchType === GameSearchType.hot ? [60, 90, 120][Math.floor(random() * 3)] ?? 90 : null,
      hasCourtBooked: random() > 0.45,
      sport,
      selfLevel: selfLevel,
      selfLevelUnknown: random() > 0.9,
      desiredLevelMin: Math.max(1, selfLevel - 1),
      desiredLevelMax: Math.min(10, selfLevel + 1),
      format,
      playersNeeded: defaultPlayersNeeded(sport, format, random),
      comment: buildSearchComment(searchType, sport, preferredCourt?.name ?? null),
      status: GameSearchStatus.active,
      isActive: true
    }
  });

  return 1;
}

async function createLiveResponse(
  prisma: PrismaClient,
  users: SimUser[],
  courts: Array<{ id: string; name: string; district: string | null; supportedSports: Prisma.JsonValue | null }>,
  random: () => number
) {
  const activeSearches = await prisma.gameSearch.findMany({
    where: {
      isActive: true
    },
    include: {
      createdByUser: true,
      responses: true
    },
    orderBy: {
      createdAt: "desc"
    },
    take: 20
  });

  const search = shuffle(activeSearches, random)[0];
  if (!search) {
    return { responses: 0, matches: 0, gameRequests: 0, messages: 0 };
  }

  const responder = shuffle(
    users.filter(
      (user) =>
        user.id !== search.createdByUserId &&
        normalizeSports(user.preferredSports).includes(search.sport) &&
        !search.responses.some((response) => response.responderUserId === user.id)
    ),
    random
  )[0];

  if (!responder) {
    return { responses: 0, matches: 0, gameRequests: 0, messages: 0 };
  }

  const status =
    search.searchType === GameSearchType.hot
      ? random() > 0.45
        ? GameSearchResponseStatus.approved
        : GameSearchResponseStatus.pending
      : random() > 0.55
        ? GameSearchResponseStatus.approved
        : GameSearchResponseStatus.pending;

  await prisma.gameSearchResponse.create({
    data: {
      gameSearchId: search.id,
      responderUserId: responder.id,
      message: buildResponseMessage(search.sport, status),
      status
    }
  });

  if (status !== GameSearchResponseStatus.approved) {
    return { responses: 1, matches: 0, gameRequests: 0, messages: 0 };
  }

  const matchId = await ensureMatch(prisma, new Map<string, string>(), search.createdByUserId, responder.id);
  const proposedCourt = search.preferredCourtId
    ? { id: search.preferredCourtId }
    : pickCourtForSport(courts, search.sport, search.createdByUser.district, random);
  const proposedDatetime =
    search.hotStartsAt ?? buildRegularRequestDate(search.preferredDays as string[], search.preferredTimeRanges as string[], random);

  await prisma.gameRequest.create({
    data: {
      matchId,
      createdByUserId: search.createdByUserId,
      matchedUserId: responder.id,
      proposedCourtId: proposedCourt?.id ?? courts[0]?.id,
      proposedDatetime,
      durationMinutes: search.durationMinutes ?? 90,
      levelRangeMin: search.desiredLevelMin,
      levelRangeMax: search.desiredLevelMax,
      sport: search.sport,
      format: search.format,
      comment: buildGameRequestComment(search.searchType, search.sport),
      status: search.searchType === GameSearchType.hot ? GameRequestStatus.accepted : GameRequestStatus.pending
    }
  });

  await prisma.chatMessage.createMany({
    data: [
      {
        matchId,
        senderUserId: search.createdByUserId,
        text: `Подтверждаю участие по ${SPORT_LABELS[search.sport].toLowerCase()}.`
      },
      {
        matchId,
        senderUserId: responder.id,
        text: search.searchType === GameSearchType.hot ? "Отлично, беру слот." : "Супер, давай согласуем детали."
      }
    ]
  });

  await prisma.gameSearch.update({
    where: { id: search.id },
    data: {
      status: GameSearchStatus.in_review
    }
  });

  return { responses: 1, matches: 1, gameRequests: 1, messages: 2 };
}

async function createLiveMessage(prisma: PrismaClient, users: SimUser[], random: () => number) {
  const matches = await prisma.match.findMany({
    where: {
      status: MatchStatus.active,
      OR: [
        ...users.map((user) => ({ user1Id: user.id })),
        ...users.map((user) => ({ user2Id: user.id }))
      ]
    },
    take: 30
  });

  const match = shuffle(matches, random)[0];
  if (!match) {
    return 0;
  }

  const senderUserId = random() > 0.5 ? match.user1Id : match.user2Id;
  const recipientUserId = senderUserId === match.user1Id ? match.user2Id : match.user1Id;
  const sender = users.find((user) => user.id === senderUserId);
  const recipient = users.find((user) => user.id === recipientUserId);
  const sharedSport = sender && recipient ? getSharedPrimarySport(sender, recipient) : Sport.tennis;

  await prisma.$transaction([
    prisma.chatMessage.create({
      data: {
        matchId: match.id,
        senderUserId,
        text: buildLiveMessageText(sharedSport, random)
      }
    }),
    prisma.match.update({
      where: { id: match.id },
      data: { updatedAt: new Date() }
    })
  ]);

  return 1;
}

async function createLiveGameRequest(
  prisma: PrismaClient,
  users: SimUser[],
  courts: Array<{ id: string; name: string; district: string | null; supportedSports: Prisma.JsonValue | null }>,
  random: () => number
) {
  const matches = await prisma.match.findMany({
    where: {
      status: MatchStatus.active
    },
    include: {
      gameRequests: {
        orderBy: { createdAt: "desc" },
        take: 1
      }
    },
    take: 20
  });

  const match = shuffle(
    matches.filter((item) => {
      const latest = item.gameRequests[0];
      return !latest || latest.createdAt.getTime() < Date.now() - 1000 * 60 * 30;
    }),
    random
  )[0];

  if (!match) {
    return { gameRequests: 0, messages: 0 };
  }

  const creator = users.find((user) => user.id === match.user1Id) ?? users[0];
  const responder = users.find((user) => user.id === match.user2Id) ?? users[1];
  if (!creator || !responder) {
    return { gameRequests: 0, messages: 0 };
  }

  const sport = getSharedPrimarySport(creator, responder);
  const proposedCourt = pickCourtForSport(courts, sport, creator.district, random);

  await prisma.$transaction([
    prisma.gameRequest.create({
      data: {
        matchId: match.id,
        createdByUserId: creator.id,
        matchedUserId: responder.id,
        proposedCourtId: proposedCourt?.id ?? courts[0]?.id,
        proposedDatetime: buildRegularRequestDate(pickDaysFromUser(creator, random), pickTimeRangesFromUser(creator, random), random),
        durationMinutes: 90,
        levelRangeMin: 1,
        levelRangeMax: 10,
        sport,
        format: pickSearchFormat(random, creator.preferredPlayFormat, sport),
        comment: `Свежий слот по ${SPORT_LABELS[sport].toLowerCase()}`
      }
    }),
    prisma.chatMessage.create({
      data: {
        matchId: match.id,
        senderUserId: creator.id,
        text: `Есть новый вариант игры по ${SPORT_LABELS[sport].toLowerCase()}. Посмотри предложение.`
      }
    }),
    prisma.match.update({
      where: { id: match.id },
      data: { updatedAt: new Date() }
    })
  ]);

  return { gameRequests: 1, messages: 1 };
}

function shuffle<T>(items: T[], random: () => number) {
  const copy = [...items];
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(random() * (index + 1));
    [copy[index], copy[swapIndex]] = [copy[swapIndex], copy[index]];
  }
  return copy;
}

function sampleSports(random: () => number, count: number) {
  return shuffle([...SPORT_OPTIONS], random).slice(0, count);
}

function buildAvailability(random: () => number) {
  const days = shuffle([...DAY_KEYS], random).slice(0, 2 + Math.floor(random() * 3));
  return Object.fromEntries(
    days.map((day) => [day, shuffle([...TIME_RANGE_KEYS], random).slice(0, 1 + Math.floor(random() * 2))])
  ) as Record<string, string[]>;
}

function pickPlayFormat(random: () => number, sport: Sport) {
  if (sport === Sport.football || sport === Sport.volleyball) {
    return random() > 0.35 ? PlayFormat.doubles : PlayFormat.both;
  }
  return [PlayFormat.singles, PlayFormat.both, PlayFormat.doubles][Math.floor(random() * 3)] ?? PlayFormat.both;
}

function pickSurface(random: () => number, sport: Sport) {
  if (sport !== Sport.tennis && sport !== Sport.padel) {
    return Surface.any;
  }
  return [Surface.hard, Surface.clay, Surface.any][Math.floor(random() * 3)] ?? Surface.any;
}

function buildBio(firstName: string, sport: Sport, district: DistrictOption, random: () => number) {
  const intros = [
    "Люблю договариваться быстро и без лишней переписки.",
    "Обычно выхожу на игру в тот же день, если всё совпало по времени.",
    "Ищу понятный и спокойный сценарий: выбрать клуб, подтвердить слот и играть."
  ];
  return `${firstName} играет в ${SPORT_LABELS[sport].toLowerCase()} и чаще выбирает ${DISTRICT_MAP_AREAS[district].label.toLowerCase()} район. ${
    intros[Math.floor(random() * intros.length)]
  }`;
}

function extractSportLevel(user: SimUser, sport: Sport) {
  if (!user.sportLevels || typeof user.sportLevels !== "object" || Array.isArray(user.sportLevels)) {
    return user.tennisLevel ?? 5;
  }
  const level = (user.sportLevels as Record<string, unknown>)[sport];
  return typeof level === "number" ? level : user.tennisLevel ?? 5;
}

function compatibilityScore(left: SimUser, right: SimUser) {
  const leftSports = normalizeSports(left.preferredSports);
  const rightSports = normalizeSports(right.preferredSports);
  const sharedSports = leftSports.filter((sport) => rightSports.includes(sport));

  if (sharedSports.length === 0) {
    return -1;
  }

  const primarySport = sharedSports[0];
  const levelGap = Math.abs(extractSportLevel(left, primarySport) - extractSportLevel(right, primarySport));
  const districtBoost = left.district && right.district && left.district === right.district ? 8 : 0;
  const availabilityBoost = overlapCount(left.availableDays, right.availableDays) + overlapCount(left.availableTimeRanges, right.availableTimeRanges);

  return sharedSports.length * 16 + districtBoost + availabilityBoost * 2 - levelGap * 3;
}

function buildSwipeRows(users: SimUser[], random: () => number) {
  const rows: Prisma.SwipeCreateManyInput[] = [];

  for (let leftIndex = 0; leftIndex < users.length; leftIndex += 1) {
    for (let rightIndex = leftIndex + 1; rightIndex < users.length; rightIndex += 1) {
      const left = users[leftIndex];
      const right = users[rightIndex];
      const score = compatibilityScore(left, right);

      if (score < 8) {
        continue;
      }

      if (score >= 24 && random() > 0.7) {
        rows.push(
          { fromUserId: left.id, toUserId: right.id, action: "like" },
          { fromUserId: right.id, toUserId: left.id, action: "like" }
        );
        continue;
      }

      if (score >= 18 && random() > 0.72) {
        const initiator = random() > 0.5 ? left : right;
        const target = initiator.id === left.id ? right : left;
        rows.push({ fromUserId: initiator.id, toUserId: target.id, action: "like" });
        if (random() > 0.76) {
          rows.push({ fromUserId: target.id, toUserId: initiator.id, action: "dislike" });
        }
        continue;
      }

      if (random() > 0.96) {
        rows.push({ fromUserId: left.id, toUserId: right.id, action: "dislike" });
      }
    }
  }

  return dedupeSwipes(rows);
}

function dedupeSwipes(rows: Prisma.SwipeCreateManyInput[]) {
  const map = new Map<string, Prisma.SwipeCreateManyInput>();
  for (const row of rows) {
    map.set(`${row.fromUserId}:${row.toUserId}`, row);
  }
  return Array.from(map.values());
}

function getMutualLikePairs(rows: Prisma.SwipeCreateManyInput[]) {
  const likedPairs = new Set(rows.filter((row) => row.action === "like").map((row) => `${row.fromUserId}:${row.toUserId}`));
  const pairs: Array<[string, string]> = [];

  for (const row of rows) {
    if (row.action !== "like") {
      continue;
    }
    if (likedPairs.has(`${row.toUserId}:${row.fromUserId}`) && row.fromUserId < row.toUserId) {
      pairs.push([row.fromUserId, row.toUserId]);
    }
  }

  return pairs;
}

async function ensureMatch(prisma: PrismaClient, matchIdByPair: Map<string, string>, leftUserId: string, rightUserId: string) {
  const [user1Id, user2Id] = leftUserId < rightUserId ? [leftUserId, rightUserId] : [rightUserId, leftUserId];
  const key = `${user1Id}:${user2Id}`;
  const existing = matchIdByPair.get(key);
  if (existing) {
    return existing;
  }

  const match = await prisma.match.upsert({
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
  matchIdByPair.set(key, match.id);
  return match.id;
}

function pickCourtForSport(
  courts: Array<{ id: string; name: string; district: string | null; supportedSports: Prisma.JsonValue | null }>,
  sport: Sport,
  district: string | null,
  random: () => number
) {
  const candidates = courts.filter((court) => {
    const supported = Array.isArray(court.supportedSports)
      ? court.supportedSports.filter((value): value is Sport => typeof value === "string" && SPORT_OPTIONS.includes(value as Sport))
      : [];
    const sportMatch = supported.length === 0 || supported.includes(sport);
    const districtMatch = district ? court.district === district : true;
    return sportMatch && districtMatch;
  });

  const pool = candidates.length > 0 ? candidates : courts;
  return pool[Math.floor(random() * pool.length)] ?? null;
}

function pickDaysFromUser(user: SimUser, random: () => number) {
  const days = Array.isArray(user.availableDays) ? user.availableDays.filter((value): value is string => typeof value === "string") : [];
  if (days.length === 0) {
    return shuffle([...DAY_KEYS], random).slice(0, 2);
  }
  return shuffle(days, random).slice(0, Math.min(days.length, 2));
}

function pickTimeRangesFromUser(user: SimUser, random: () => number) {
  const ranges = Array.isArray(user.availableTimeRanges)
    ? user.availableTimeRanges.filter((value): value is string => typeof value === "string")
    : [];
  if (ranges.length === 0) {
    return shuffle([...TIME_RANGE_KEYS], random).slice(0, 1);
  }
  return shuffle(ranges, random).slice(0, Math.min(ranges.length, 2));
}

function pickHotWindow(random: () => number) {
  return [HotSearchWindow.today, HotSearchWindow.tomorrow, HotSearchWindow.day_after_tomorrow][Math.floor(random() * 3)] ?? HotSearchWindow.tomorrow;
}

function buildHotStartsAt(window: HotSearchWindow | null, random: () => number) {
  const date = new Date();
  if (window === HotSearchWindow.tomorrow) {
    date.setDate(date.getDate() + 1);
  } else if (window === HotSearchWindow.day_after_tomorrow) {
    date.setDate(date.getDate() + 2);
  }

  const hours = [8, 10, 12, 14, 16, 18, 20][Math.floor(random() * 7)] ?? 18;
  const minutes = [0, 15, 30, 45][Math.floor(random() * 4)] ?? 0;
  date.setHours(hours, minutes, 0, 0);

  if (window === HotSearchWindow.today && date.getTime() < Date.now() + 1000 * 60 * 60) {
    date.setHours(date.getHours() + 2);
  }

  return date;
}

function pickSearchFormat(random: () => number, preferredFormat: PlayFormat, sport: Sport) {
  if (sport === Sport.football || sport === Sport.volleyball) {
    return PlayFormat.doubles;
  }

  if (preferredFormat === PlayFormat.both) {
    return random() > 0.55 ? PlayFormat.singles : PlayFormat.doubles;
  }

  return preferredFormat;
}

function defaultPlayersNeeded(sport: Sport, format: PlayFormat, random: () => number) {
  if (sport === Sport.football) {
    return [4, 6, 8][Math.floor(random() * 3)] ?? 6;
  }
  if (sport === Sport.volleyball) {
    return [2, 4, 6][Math.floor(random() * 3)] ?? 4;
  }
  if (sport === Sport.tennis && format === PlayFormat.doubles) {
    return 3;
  }
  if (sport === Sport.padel && format === PlayFormat.doubles) {
    return 3;
  }
  return 1;
}

function buildSearchComment(type: GameSearchType, sport: Sport, courtName: string | null) {
  if (type === GameSearchType.hot) {
    return courtName
      ? `Нужен игрок в ${SPORT_LABELS[sport].toLowerCase()} как можно быстрее. ${courtName} уже на примете.`
      : `Нужен игрок в ${SPORT_LABELS[sport].toLowerCase()} на ближайшее время.`;
  }

  return courtName
    ? `Ищу партнёра по ${SPORT_LABELS[sport].toLowerCase()} и готов(а) сыграть в ${courtName}.`
    : `Ищу регулярного партнёра по ${SPORT_LABELS[sport].toLowerCase()} в удобное время.`;
}

function buildResponseMessage(sport: Sport, status: GameSearchResponseStatus) {
  if (status === GameSearchResponseStatus.approved) {
    return `Готов(а) подтвердить участие по ${SPORT_LABELS[sport].toLowerCase()} и быстро договориться.`;
  }
  if (status === GameSearchResponseStatus.pending) {
    return `Интересен этот слот по ${SPORT_LABELS[sport].toLowerCase()}, жду решения.`;
  }
  return `Спасибо, если не подойду сейчас — буду рад(а) сыграть позже.`;
}

function buildGameRequestComment(searchType: GameSearchType, sport: Sport) {
  return searchType === GameSearchType.hot
    ? `Срочная договорённость по ${SPORT_LABELS[sport].toLowerCase()}.`
    : `Предложение игры по ${SPORT_LABELS[sport].toLowerCase()} после отклика на поиск.`;
}

function buildLiveMessageText(sport: Sport, random: () => number) {
  const messages = [
    `У меня освободилось окно на ${SPORT_LABELS[sport].toLowerCase()}. Как тебе идея?`,
    `Если удобно, можем быстро подтвердить игру по ${SPORT_LABELS[sport].toLowerCase()}.`,
    `Смотрю слот на ближайшие дни по ${SPORT_LABELS[sport].toLowerCase()}. Подойдёт?`,
    `Я на связи. Давай закрепим время и клуб по ${SPORT_LABELS[sport].toLowerCase()}.`
  ];

  return messages[Math.floor(random() * messages.length)] ?? messages[0];
}

function buildRegularRequestDate(days: string[], ranges: string[], random: () => number) {
  const date = new Date();
  date.setDate(date.getDate() + 2 + Math.floor(random() * 6));
  const preferredRange = ranges[0] ?? "evening";
  const hour = preferredRange === "morning" ? 9 : preferredRange === "day" ? 14 : 19;
  date.setHours(hour, [0, 15, 30, 45][Math.floor(random() * 4)] ?? 0, 0, 0);
  return date;
}

function getSharedPrimarySport(left: SimUser, right: SimUser) {
  const leftSports = normalizeSports(left.preferredSports);
  const rightSports = normalizeSports(right.preferredSports);
  return leftSports.find((sport) => rightSports.includes(sport)) ?? Sport.tennis;
}

function overlapCount(left: Prisma.JsonValue | null, right: Prisma.JsonValue | null) {
  const leftValues = Array.isArray(left) ? left.filter((value): value is string => typeof value === "string") : [];
  const rightValues = Array.isArray(right) ? right.filter((value): value is string => typeof value === "string") : [];
  return leftValues.filter((value) => rightValues.includes(value)).length;
}
