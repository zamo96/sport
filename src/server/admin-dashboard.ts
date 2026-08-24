import type { GameRequestStatus, GameSearchStatus, Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";

const DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_ACTIVITY_DAYS = 14;
const MAX_PLAYER_ROADMAPS = 12;

type CountByStatus<T extends string> = Record<T, number>;

export type AdminMetric = {
  label: string;
  value: number;
  helper: string;
};

export type AdminTimelineItem = {
  id: string;
  kind: "user" | "session" | "search" | "request" | "message" | "report";
  title: string;
  subtitle: string;
  occurredAt: Date;
  actorName: string | null;
};

export type AdminOperationalEvent = {
  id: string;
  source: "maintenance" | "website" | "push" | "auth";
  severity: "info" | "warning" | "error";
  title: string;
  message: string;
  occurredAt: Date;
};

export type AdminDailyActivity = {
  day: string;
  label: string;
  newUsers: number;
  lastSeenUsers: number;
  searches: number;
  gameRequests: number;
  matches: number;
  messages: number;
  swipes: number;
  errors: number;
  total: number;
};

export type AdminPlayerRoadmap = {
  id: string;
  name: string | null;
  email: string;
  city: string | null;
  district: string | null;
  createdAt: Date;
  lastActiveAt: Date | null;
  onboardingCompleted: boolean;
  isVerified: boolean;
  preferredSports: string[];
  matchesTotal: number;
  matches7d: number;
  proposalsSent: number;
  proposalsReceived: number;
  proposalsPending: number;
  proposalsAccepted: number;
  proposalsDeclined: number;
  proposalsCanceled: number;
  searchesTotal: number;
  searchesActive: number;
  messages7d: number;
};

export type AdminDashboardData = {
  generatedAt: Date;
  playerQuery: string;
  metrics: {
    usersTotal: number;
    usersVerified: number;
    usersOnboarded: number;
    usersActive24h: number;
    usersActive7d: number;
    usersNew24h: number;
    usersNew7d: number;
    activeSessions: number;
    activeGameSearches: number;
    activeHotSearches: number;
    pendingGameRequests: number;
    activeMatches: number;
    messages24h: number;
    swipes24h: number;
    reportsPending: number;
    operationalErrors24h: number;
  };
  dailyActivity: AdminDailyActivity[];
  playerRoadmaps: AdminPlayerRoadmap[];
  searchStatusCounts: CountByStatus<GameSearchStatus>;
  requestStatusCounts: CountByStatus<GameRequestStatus>;
  authCodeStats: {
    created24h: number;
    consumed24h: number;
    pending: number;
    expiredUnconsumed7d: number;
  };
  recentUsers: Array<{
    id: string;
    name: string | null;
    email: string;
    city: string | null;
    district: string | null;
    createdAt: Date;
    lastActiveAt: Date | null;
    onboardingCompleted: boolean;
    isVerified: boolean;
  }>;
  recentActivity: AdminTimelineItem[];
  operationalEvents: AdminOperationalEvent[];
  maintenanceRuns: Array<{
    id: string;
    sourceType: string;
    city: string;
    status: string;
    startedAt: Date;
    finishedAt: Date | null;
    fetchedCount: number;
    createdCount: number;
    updatedCount: number;
    proposedCount: number;
    websiteFailedCount: number;
    errorMessage: string | null;
  }>;
};

export type AdminDashboardOptions = {
  playerQuery?: string | null;
  days?: number;
};

const gameSearchStatuses: GameSearchStatus[] = ["active", "in_review", "matched", "closed"];
const gameRequestStatuses: GameRequestStatus[] = ["pending", "accepted", "declined", "canceled"];

export async function getAdminDashboardData(options: AdminDashboardOptions = {}): Promise<AdminDashboardData> {
  const now = new Date();
  const since24h = new Date(now.getTime() - DAY_MS);
  const since7d = new Date(now.getTime() - 7 * DAY_MS);
  const playerQuery = normalizePlayerQuery(options.playerQuery);
  const days = clampActivityDays(options.days);
  const dailyStart = startOfLocalDay(new Date(now.getTime() - (days - 1) * DAY_MS));

  const [
    usersTotal,
    usersVerified,
    usersOnboarded,
    usersActive24h,
    usersActive7d,
    usersNew24h,
    usersNew7d,
    activeSessions,
    activeGameSearches,
    activeHotSearches,
    pendingGameRequests,
    activeMatches,
    chatMessages24h,
    searchMessages24h,
    swipes24h,
    reportsPending,
    searchStatusCounts,
    requestStatusCounts,
    authCodeStats,
    recentUsers,
    recentSessions,
    recentGameSearches,
    recentGameRequests,
    recentChatMessages,
    recentSearchMessages,
    recentReports,
    maintenanceRuns,
    failedWebsiteChecks,
    pushFailures,
    authWarnings24h,
    dailyActivity,
    playerRoadmaps
  ] = await Promise.all([
    prisma.user.count(),
    prisma.user.count({ where: { isVerified: true } }),
    prisma.user.count({ where: { onboardingCompleted: true } }),
    prisma.user.count({ where: { lastActiveAt: { gte: since24h } } }),
    prisma.user.count({ where: { lastActiveAt: { gte: since7d } } }),
    prisma.user.count({ where: { createdAt: { gte: since24h } } }),
    prisma.user.count({ where: { createdAt: { gte: since7d } } }),
    prisma.session.count({ where: { expiresAt: { gt: now } } }),
    prisma.gameSearch.count({
      where: {
        isActive: true,
        status: {
          in: ["active", "in_review"]
        }
      }
    }),
    prisma.gameSearch.count({
      where: {
        isActive: true,
        searchType: "hot",
        status: {
          in: ["active", "in_review"]
        }
      }
    }),
    prisma.gameRequest.count({ where: { status: "pending" } }),
    prisma.match.count({ where: { status: "active" } }),
    prisma.chatMessage.count({ where: { createdAt: { gte: since24h } } }),
    prisma.gameSearchMessage.count({ where: { createdAt: { gte: since24h } } }),
    prisma.swipe.count({ where: { createdAt: { gte: since24h } } }),
    prisma.contentReport.count({ where: { status: "pending" } }),
    countGameSearchStatuses(),
    countGameRequestStatuses(),
    getAuthCodeStats(since24h, since7d, now),
    prisma.user.findMany({
      take: 10,
      orderBy: [{ lastActiveAt: "desc" }, { createdAt: "desc" }],
      select: {
        id: true,
        name: true,
        email: true,
        city: true,
        district: true,
        createdAt: true,
        lastActiveAt: true,
        onboardingCompleted: true,
        isVerified: true
      }
    }),
    prisma.session.findMany({
      take: 8,
      orderBy: { createdAt: "desc" },
      include: {
        user: {
          select: {
            name: true,
            email: true
          }
        }
      }
    }),
    prisma.gameSearch.findMany({
      take: 8,
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        searchType: true,
        status: true,
        sport: true,
        createdAt: true,
        createdByUser: {
          select: {
            name: true,
            email: true
          }
        },
        preferredCourt: {
          select: {
            name: true
          }
        },
        scheduledCourt: {
          select: {
            name: true
          }
        }
      }
    }),
    prisma.gameRequest.findMany({
      take: 8,
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        status: true,
        createdAt: true,
        createdByUser: {
          select: {
            name: true,
            email: true
          }
        },
        matchedUser: {
          select: {
            name: true,
            email: true
          }
        },
        proposedCourt: {
          select: {
            name: true
          }
        }
      }
    }),
    prisma.chatMessage.findMany({
      take: 8,
      orderBy: { createdAt: "desc" },
      include: {
        senderUser: {
          select: {
            name: true,
            email: true
          }
        }
      }
    }),
    prisma.gameSearchMessage.findMany({
      take: 8,
      orderBy: { createdAt: "desc" },
      include: {
        senderUser: {
          select: {
            name: true,
            email: true
          }
        }
      }
    }),
    prisma.gameReport.findMany({
      take: 8,
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        status: true,
        comment: true,
        createdAt: true,
        createdByUser: {
          select: {
            name: true,
            email: true
          }
        }
      }
    }),
    prisma.courtSyncRun.findMany({
      take: 8,
      orderBy: { startedAt: "desc" },
      select: {
        id: true,
        sourceType: true,
        city: true,
        status: true,
        startedAt: true,
        finishedAt: true,
        fetchedCount: true,
        createdCount: true,
        updatedCount: true,
        proposedCount: true,
        websiteFailedCount: true,
        errorMessage: true
      }
    }),
    prisma.courtWebsiteCheck.findMany({
      take: 10,
      where: {
        OR: [
          { status: "failed" },
          { errorMessage: { not: null } },
          { analystStatus: "failed" },
          { analystErrorMessage: { not: null } },
          { screenshotStatus: "failed" },
          { screenshotErrorMessage: { not: null } }
        ]
      },
      orderBy: { checkedAt: "desc" },
      include: {
        court: {
          select: {
            name: true
          }
        }
      }
    }),
    prisma.pushDevice.findMany({
      take: 10,
      where: {
        lastFailureAt: {
          not: null
        }
      },
      orderBy: {
        lastFailureAt: "desc"
      },
      include: {
        user: {
          select: {
            name: true,
            email: true
          }
        }
      }
    }),
    prisma.authCode.count({
      where: {
        createdAt: {
          gte: since24h
        },
        consumedAt: null,
        expiresAt: {
          lt: now
        }
      }
    }),
    getDailyActivity(dailyStart, days),
    getPlayerRoadmaps(playerQuery, since7d)
  ]);

  const recentActivity = [
    ...recentUsers.map<AdminTimelineItem>((user) => ({
      id: `user:${user.id}`,
      kind: "user",
      title: user.onboardingCompleted ? "Новый завершенный профиль" : "Новая регистрация",
      subtitle: [user.email, user.city, user.district].filter(Boolean).join(" · "),
      occurredAt: user.createdAt,
      actorName: user.name
    })),
    ...recentSessions.map<AdminTimelineItem>((session) => ({
      id: `session:${session.id}`,
      kind: "session",
      title: "Новая сессия",
      subtitle: `Истекает ${formatDateForSubtitle(session.expiresAt)}`,
      occurredAt: session.createdAt,
      actorName: session.user.name ?? session.user.email
    })),
    ...recentGameSearches.map<AdminTimelineItem>((search) => ({
      id: `search:${search.id}`,
      kind: "search",
      title: search.searchType === "hot" ? "Срочный поиск" : "Поиск игры",
      subtitle: [search.status, search.sport, search.scheduledCourt?.name ?? search.preferredCourt?.name].filter(Boolean).join(" · "),
      occurredAt: search.createdAt,
      actorName: search.createdByUser.name ?? search.createdByUser.email
    })),
    ...recentGameRequests.map<AdminTimelineItem>((request) => ({
      id: `request:${request.id}`,
      kind: "request",
      title: "Предложение игры",
      subtitle: [
        request.status,
        request.proposedCourt?.name,
        `с ${request.matchedUser.name ?? request.matchedUser.email}`
      ].filter(Boolean).join(" · "),
      occurredAt: request.createdAt,
      actorName: request.createdByUser.name ?? request.createdByUser.email
    })),
    ...recentChatMessages.map<AdminTimelineItem>((message) => ({
      id: `chat:${message.id}`,
      kind: "message",
      title: "Сообщение в чате",
      subtitle: compactText(message.text),
      occurredAt: message.createdAt,
      actorName: message.senderUser.name ?? message.senderUser.email
    })),
    ...recentSearchMessages.map<AdminTimelineItem>((message) => ({
      id: `search-message:${message.id}`,
      kind: "message",
      title: "Сообщение в лобби",
      subtitle: compactText(message.text),
      occurredAt: message.createdAt,
      actorName: message.senderUser.name ?? message.senderUser.email
    })),
    ...recentReports.map<AdminTimelineItem>((report) => ({
      id: `report:${report.id}`,
      kind: "report",
      title: "Отчет по игре",
      subtitle: [report.status, compactText(report.comment ?? "")].filter(Boolean).join(" · "),
      occurredAt: report.createdAt,
      actorName: report.createdByUser.name ?? report.createdByUser.email
    }))
  ]
    .sort((a, b) => b.occurredAt.getTime() - a.occurredAt.getTime())
    .slice(0, 24);

  const operationalEvents: AdminOperationalEvent[] = [
    ...maintenanceRuns
      .filter((run) => run.errorMessage || run.status === "failed")
      .map<AdminOperationalEvent>((run) => ({
        id: `maintenance:${run.id}`,
        source: "maintenance",
        severity: "error",
        title: `Maintenance ${run.sourceType}`,
        message: run.errorMessage ?? `Run finished with status ${run.status}`,
        occurredAt: run.finishedAt ?? run.startedAt
      })),
    ...failedWebsiteChecks.map<AdminOperationalEvent>((check) => ({
      id: `website:${check.id}`,
      source: "website",
      severity: check.status === "failed" ? "error" : "warning",
      title: check.court.name,
      message:
        check.errorMessage ??
        check.analystErrorMessage ??
        check.screenshotErrorMessage ??
        `Website check status: ${check.status}`,
      occurredAt: check.checkedAt
    })),
    ...pushFailures.map<AdminOperationalEvent>((device) => ({
      id: `push:${device.id}`,
      source: "push",
      severity: "warning",
      title: device.user.name ?? device.user.email,
      message: device.lastFailureReason ?? "Push delivery failed",
      occurredAt: device.lastFailureAt ?? device.updatedAt
    })),
    ...(authWarnings24h > 0
      ? [
          {
            id: "auth:expired-codes-24h",
            source: "auth" as const,
            severity: "warning" as const,
            title: "Истекшие коды входа",
            message: `${authWarnings24h} кодов за 24 часа не были использованы до истечения срока`,
            occurredAt: now
          }
        ]
      : [])
  ]
    .sort((a, b) => b.occurredAt.getTime() - a.occurredAt.getTime())
    .slice(0, 20);

  const operationalErrors24h = operationalEvents.filter(
    (event) => event.occurredAt >= since24h && (event.severity === "error" || event.severity === "warning")
  ).length;

  return {
    generatedAt: now,
    playerQuery,
    metrics: {
      usersTotal,
      usersVerified,
      usersOnboarded,
      usersActive24h,
      usersActive7d,
      usersNew24h,
      usersNew7d,
      activeSessions,
      activeGameSearches,
      activeHotSearches,
      pendingGameRequests,
      activeMatches,
      messages24h: chatMessages24h + searchMessages24h,
      swipes24h,
      reportsPending,
      operationalErrors24h
    },
    dailyActivity,
    playerRoadmaps,
    searchStatusCounts,
    requestStatusCounts,
    authCodeStats,
    recentUsers,
    recentActivity,
    operationalEvents,
    maintenanceRuns
  };
}

async function getDailyActivity(start: Date, days: number): Promise<AdminDailyActivity[]> {
  const buckets = createDailyBuckets(start, days);

  const [
    users,
    lastSeenUsers,
    searches,
    gameRequests,
    matches,
    chatMessages,
    searchMessages,
    swipes,
    failedRuns,
    failedWebsiteChecks,
    pushFailures
  ] = await Promise.all([
    prisma.user.findMany({
      where: {
        createdAt: {
          gte: start
        }
      },
      select: {
        createdAt: true
      }
    }),
    prisma.user.findMany({
      where: {
        lastActiveAt: {
          gte: start
        }
      },
      select: {
        lastActiveAt: true
      }
    }),
    prisma.gameSearch.findMany({
      where: {
        createdAt: {
          gte: start
        }
      },
      select: {
        createdAt: true
      }
    }),
    prisma.gameRequest.findMany({
      where: {
        createdAt: {
          gte: start
        }
      },
      select: {
        createdAt: true
      }
    }),
    prisma.match.findMany({
      where: {
        createdAt: {
          gte: start
        }
      },
      select: {
        createdAt: true
      }
    }),
    prisma.chatMessage.findMany({
      where: {
        createdAt: {
          gte: start
        }
      },
      select: {
        createdAt: true
      }
    }),
    prisma.gameSearchMessage.findMany({
      where: {
        createdAt: {
          gte: start
        }
      },
      select: {
        createdAt: true
      }
    }),
    prisma.swipe.findMany({
      where: {
        createdAt: {
          gte: start
        }
      },
      select: {
        createdAt: true
      }
    }),
    prisma.courtSyncRun.findMany({
      where: {
        startedAt: {
          gte: start
        },
        OR: [
          {
            status: {
              in: ["failed", "error"]
            }
          },
          {
            errorMessage: {
              not: null
            }
          }
        ]
      },
      select: {
        startedAt: true
      }
    }),
    prisma.courtWebsiteCheck.findMany({
      where: {
        checkedAt: {
          gte: start
        },
        OR: [
          { status: "failed" },
          { errorMessage: { not: null } },
          { analystStatus: "failed" },
          { analystErrorMessage: { not: null } },
          { screenshotStatus: "failed" },
          { screenshotErrorMessage: { not: null } }
        ]
      },
      select: {
        checkedAt: true
      }
    }),
    prisma.pushDevice.findMany({
      where: {
        lastFailureAt: {
          gte: start
        }
      },
      select: {
        lastFailureAt: true
      }
    })
  ]);

  for (const user of users) {
    incrementDailyBucket(buckets, user.createdAt, "newUsers");
  }

  for (const user of lastSeenUsers) {
    if (user.lastActiveAt) {
      incrementDailyBucket(buckets, user.lastActiveAt, "lastSeenUsers");
    }
  }

  for (const search of searches) {
    incrementDailyBucket(buckets, search.createdAt, "searches");
  }

  for (const request of gameRequests) {
    incrementDailyBucket(buckets, request.createdAt, "gameRequests");
  }

  for (const match of matches) {
    incrementDailyBucket(buckets, match.createdAt, "matches");
  }

  for (const message of chatMessages) {
    incrementDailyBucket(buckets, message.createdAt, "messages");
  }

  for (const message of searchMessages) {
    incrementDailyBucket(buckets, message.createdAt, "messages");
  }

  for (const swipe of swipes) {
    incrementDailyBucket(buckets, swipe.createdAt, "swipes");
  }

  for (const run of failedRuns) {
    incrementDailyBucket(buckets, run.startedAt, "errors");
  }

  for (const check of failedWebsiteChecks) {
    incrementDailyBucket(buckets, check.checkedAt, "errors");
  }

  for (const device of pushFailures) {
    if (device.lastFailureAt) {
      incrementDailyBucket(buckets, device.lastFailureAt, "errors");
    }
  }

  return Array.from(buckets.values()).map((bucket) => ({
    ...bucket,
    total: bucket.searches + bucket.gameRequests + bucket.matches + bucket.messages + bucket.swipes
  }));
}

async function getPlayerRoadmaps(query: string, since7d: Date): Promise<AdminPlayerRoadmap[]> {
  const users = await prisma.user.findMany({
    where: buildPlayerSearchWhere(query),
    take: MAX_PLAYER_ROADMAPS,
    orderBy: [{ lastActiveAt: "desc" }, { createdAt: "desc" }],
    select: {
      id: true,
      name: true,
      email: true,
      city: true,
      district: true,
      preferredSports: true,
      createdAt: true,
      lastActiveAt: true,
      onboardingCompleted: true,
      isVerified: true
    }
  });
  const userIds = users.map((user) => user.id);

  if (userIds.length === 0) {
    return [];
  }

  const roadmaps = new Map<string, AdminPlayerRoadmap>(
    users.map((user) => [
      user.id,
      {
        id: user.id,
        name: user.name,
        email: user.email,
        city: user.city,
        district: user.district,
        preferredSports: toStringArray(user.preferredSports),
        createdAt: user.createdAt,
        lastActiveAt: user.lastActiveAt,
        onboardingCompleted: user.onboardingCompleted,
        isVerified: user.isVerified,
        matchesTotal: 0,
        matches7d: 0,
        proposalsSent: 0,
        proposalsReceived: 0,
        proposalsPending: 0,
        proposalsAccepted: 0,
        proposalsDeclined: 0,
        proposalsCanceled: 0,
        searchesTotal: 0,
        searchesActive: 0,
        messages7d: 0
      }
    ])
  );

  const [
    matches,
    sentRequests,
    receivedRequests,
    searches,
    chatMessages,
    searchMessages
  ] = await Promise.all([
    prisma.match.findMany({
      where: {
        OR: [
          {
            user1Id: {
              in: userIds
            }
          },
          {
            user2Id: {
              in: userIds
            }
          }
        ]
      },
      select: {
        user1Id: true,
        user2Id: true,
        createdAt: true
      }
    }),
    prisma.gameRequest.groupBy({
      by: ["createdByUserId", "status"],
      where: {
        createdByUserId: {
          in: userIds
        }
      },
      _count: {
        _all: true
      }
    }),
    prisma.gameRequest.groupBy({
      by: ["matchedUserId", "status"],
      where: {
        matchedUserId: {
          in: userIds
        }
      },
      _count: {
        _all: true
      }
    }),
    prisma.gameSearch.groupBy({
      by: ["createdByUserId", "status", "isActive"],
      where: {
        createdByUserId: {
          in: userIds
        }
      },
      _count: {
        _all: true
      }
    }),
    prisma.chatMessage.groupBy({
      by: ["senderUserId"],
      where: {
        senderUserId: {
          in: userIds
        },
        createdAt: {
          gte: since7d
        }
      },
      _count: {
        _all: true
      }
    }),
    prisma.gameSearchMessage.groupBy({
      by: ["senderUserId"],
      where: {
        senderUserId: {
          in: userIds
        },
        createdAt: {
          gte: since7d
        }
      },
      _count: {
        _all: true
      }
    })
  ]);

  for (const match of matches) {
    incrementMatchRoadmap(roadmaps, match.user1Id, match.createdAt, since7d);
    incrementMatchRoadmap(roadmaps, match.user2Id, match.createdAt, since7d);
  }

  for (const request of sentRequests) {
    const roadmap = roadmaps.get(request.createdByUserId);
    if (!roadmap) {
      continue;
    }

    roadmap.proposalsSent += request._count._all;
    incrementProposalStatus(roadmap, request.status, request._count._all);
  }

  for (const request of receivedRequests) {
    const roadmap = roadmaps.get(request.matchedUserId);
    if (!roadmap) {
      continue;
    }

    roadmap.proposalsReceived += request._count._all;
    incrementProposalStatus(roadmap, request.status, request._count._all);
  }

  for (const search of searches) {
    const roadmap = roadmaps.get(search.createdByUserId);
    if (!roadmap) {
      continue;
    }

    roadmap.searchesTotal += search._count._all;

    if (search.isActive && (search.status === "active" || search.status === "in_review")) {
      roadmap.searchesActive += search._count._all;
    }
  }

  for (const message of chatMessages) {
    roadmaps.get(message.senderUserId)!.messages7d += message._count._all;
  }

  for (const message of searchMessages) {
    roadmaps.get(message.senderUserId)!.messages7d += message._count._all;
  }

  return users.map((user) => roadmaps.get(user.id)!);
}

async function countGameSearchStatuses() {
  const entries = await Promise.all(
    gameSearchStatuses.map(async (status) => [
      status,
      await prisma.gameSearch.count({
        where: {
          status
        }
      })
    ] as const)
  );

  return Object.fromEntries(entries) as CountByStatus<GameSearchStatus>;
}

async function countGameRequestStatuses() {
  const entries = await Promise.all(
    gameRequestStatuses.map(async (status) => [
      status,
      await prisma.gameRequest.count({
        where: {
          status
        }
      })
    ] as const)
  );

  return Object.fromEntries(entries) as CountByStatus<GameRequestStatus>;
}

async function getAuthCodeStats(since24h: Date, since7d: Date, now: Date) {
  const [created24h, consumed24h, pending, expiredUnconsumed7d] = await Promise.all([
    prisma.authCode.count({
      where: {
        createdAt: {
          gte: since24h
        }
      }
    }),
    prisma.authCode.count({
      where: {
        consumedAt: {
          gte: since24h
        }
      }
    }),
    prisma.authCode.count({
      where: {
        consumedAt: null,
        expiresAt: {
          gte: now
        }
      }
    }),
    prisma.authCode.count({
      where: {
        createdAt: {
          gte: since7d
        },
        consumedAt: null,
        expiresAt: {
          lt: now
        }
      }
    })
  ]);

  return {
    created24h,
    consumed24h,
    pending,
    expiredUnconsumed7d
  };
}

function buildPlayerSearchWhere(query: string): Prisma.UserWhereInput {
  if (!query) {
    return {};
  }

  return {
    OR: [
      {
        id: {
          contains: query,
          mode: "insensitive"
        }
      },
      {
        email: {
          contains: query,
          mode: "insensitive"
        }
      },
      {
        name: {
          contains: query,
          mode: "insensitive"
        }
      },
      {
        city: {
          contains: query,
          mode: "insensitive"
        }
      },
      {
        district: {
          contains: query,
          mode: "insensitive"
        }
      }
    ]
  };
}

function normalizePlayerQuery(value: string | null | undefined) {
  return value?.replace(/\s+/g, " ").trim().slice(0, 120) ?? "";
}

function clampActivityDays(value: number | undefined) {
  if (!value || !Number.isFinite(value)) {
    return DEFAULT_ACTIVITY_DAYS;
  }

  return Math.min(45, Math.max(7, Math.round(value)));
}

function createDailyBuckets(start: Date, days: number) {
  const buckets = new Map<string, AdminDailyActivity>();

  for (let index = 0; index < days; index += 1) {
    const date = addDays(start, index);
    const day = formatDayKey(date);
    buckets.set(day, {
      day,
      label: date.toLocaleDateString("ru-RU", {
        day: "2-digit",
        month: "short"
      }),
      newUsers: 0,
      lastSeenUsers: 0,
      searches: 0,
      gameRequests: 0,
      matches: 0,
      messages: 0,
      swipes: 0,
      errors: 0,
      total: 0
    });
  }

  return buckets;
}

function incrementDailyBucket(
  buckets: Map<string, AdminDailyActivity>,
  date: Date,
  field: "newUsers" | "lastSeenUsers" | "searches" | "gameRequests" | "matches" | "messages" | "swipes" | "errors"
) {
  const bucket = buckets.get(formatDayKey(date));

  if (!bucket) {
    return;
  }

  bucket[field] += 1;
}

function incrementMatchRoadmap(roadmaps: Map<string, AdminPlayerRoadmap>, userId: string, createdAt: Date, since7d: Date) {
  const roadmap = roadmaps.get(userId);

  if (!roadmap) {
    return;
  }

  roadmap.matchesTotal += 1;

  if (createdAt >= since7d) {
    roadmap.matches7d += 1;
  }
}

function incrementProposalStatus(roadmap: AdminPlayerRoadmap, status: GameRequestStatus, count: number) {
  switch (status) {
    case "pending":
      roadmap.proposalsPending += count;
      break;
    case "accepted":
      roadmap.proposalsAccepted += count;
      break;
    case "declined":
      roadmap.proposalsDeclined += count;
      break;
    case "canceled":
      roadmap.proposalsCanceled += count;
      break;
  }
}

function toStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function startOfLocalDay(value: Date) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function addDays(value: Date, days: number) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate() + days);
}

function formatDayKey(value: Date) {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function compactText(value: string) {
  const normalized = value.replace(/\s+/g, " ").trim();

  if (normalized.length <= 96) {
    return normalized || "Без текста";
  }

  return `${normalized.slice(0, 93)}...`;
}

function formatDateForSubtitle(value: Date) {
  return value.toLocaleString("ru-RU", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });
}
