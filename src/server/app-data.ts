import { prisma } from "@/lib/prisma";
import { haversineDistanceKm } from "@/lib/geo";
import { scoreCandidates, type DiscoverFilters } from "@/lib/scoring";
import { courtSupportsSport } from "@/lib/courts";
import { getDiscoverCandidates } from "@/server/discover";
import { normalizeSports } from "@/lib/sport-levels";

async function closeExpiredHotSearches() {
  await prisma.gameSearch.updateMany({
    where: {
      searchType: "hot",
      isActive: true,
      hotStartsAt: {
        lte: new Date()
      }
    },
    data: {
      isActive: false,
      status: "closed"
    }
  });
}

export async function getViewerWithGuard(userId: string) {
  return prisma.user.findUnique({
    where: { id: userId }
  });
}

export async function getDiscoverPageData(userId: string, filters: DiscoverFilters = {}) {
  const [viewer, candidates] = await Promise.all([
    getViewerWithGuard(userId),
    getDiscoverCandidates(userId, filters)
  ]);

  return {
    viewer,
    candidates
  };
}

export async function getSeekingPlayers(userId: string, filters: DiscoverFilters = {}) {
  await closeExpiredHotSearches();
  return getDiscoverCandidates(userId, {
    ...filters,
    view: "seeking"
  });
}

export async function getIncomingLikePlayers(userId: string, filters: DiscoverFilters = {}) {
  const viewer = await prisma.user.findUnique({
    where: { id: userId }
  });

  if (!viewer) {
    return [];
  }

  const likes = await prisma.swipe.findMany({
    where: {
      toUserId: userId,
      action: {
        in: ["like", "superlike"]
      },
      fromUser: {
        onboardingCompleted: true,
        isVerified: true,
        blockedUsers: {
          none: {
            blockedUserId: userId
          }
        },
        blockingUsers: {
          none: {
            blockerUserId: userId
          }
        }
      }
    },
    include: {
      fromUser: {
        include: {
          swipesReceived: {
            where: {
              fromUserId: userId
            },
            select: {
              id: true,
              fromUserId: true
            }
          },
          gameSearches: {
            where: {
              isActive: true
            },
            include: {
              preferredCourt: true,
              responses: {
                where: {
                  responderUserId: userId
                }
              }
            },
            orderBy: {
              createdAt: "desc"
            },
            take: 1
          }
        }
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });

  const incomingUsers = likes
    .filter((like) => !like.fromUser.swipesReceived.some((swipe) => swipe.fromUserId === userId))
    .map((like) => like.fromUser);

  const scored = getDiscoverCandidatesFromUsers(viewer, incomingUsers, {
    ...filters,
    view: undefined
  });

  return scored;
}

export async function getHotPlayers(userId: string, filters: DiscoverFilters = {}) {
  await closeExpiredHotSearches();
  return getDiscoverCandidates(userId, {
    ...filters,
    view: "hot"
  });
}

export async function getGameSearchesForUser(userId: string) {
  await closeExpiredHotSearches();
  return prisma.gameSearch.findMany({
    where: {
      createdByUserId: userId
    },
    include: {
      preferredCourt: true,
      responses: {
        include: {
          responderUser: true
        },
        orderBy: [
          { status: "asc" },
          { createdAt: "asc" }
        ]
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });
}

export async function getActiveSearchesCount(userId: string) {
  await closeExpiredHotSearches();

  return prisma.gameSearch.count({
    where: {
      createdByUserId: userId,
      isActive: true
    }
  });
}

export async function getIncomingLikesCount(userId: string) {
  const incomingLikes = await prisma.swipe.findMany({
    where: {
      toUserId: userId,
      action: {
        in: ["like", "superlike"]
      }
    },
    select: {
      fromUserId: true,
      fromUser: {
        select: {
          blockedUsers: {
            where: {
              blockedUserId: userId
            },
            select: { id: true }
          },
          blockingUsers: {
            where: {
              blockerUserId: userId
            },
            select: { id: true }
          }
        }
      }
    }
  });

  const outgoing = await prisma.swipe.findMany({
    where: {
      fromUserId: userId
    },
    select: {
      toUserId: true
    }
  });

  const respondedIds = new Set(outgoing.map((swipe) => swipe.toUserId));

  return incomingLikes.filter(
    (like) =>
      !respondedIds.has(like.fromUserId) &&
      like.fromUser.blockedUsers.length === 0 &&
      like.fromUser.blockingUsers.length === 0
  ).length;
}

export async function getHotNotificationsCount(userId: string) {
  await closeExpiredHotSearches();

  const viewer = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      preferredSports: true
    }
  });

  if (!viewer) {
    return 0;
  }

  const viewerSports = normalizeSports(viewer.preferredSports);

  return prisma.gameSearch.count({
    where: {
      isActive: true,
      searchType: "hot",
      hotStartsAt: {
        gt: new Date()
      },
      sport: {
        in: viewerSports
      },
      createdByUserId: {
        not: userId
      },
      responses: {
        none: {
          responderUserId: userId
        }
      }
    }
  });
}

export async function getNotificationsForUser(userId: string) {
  await closeExpiredHotSearches();

  const viewer = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      preferredSports: true
    }
  });

  if (!viewer) {
    return [];
  }

  const viewerSports = normalizeSports(viewer.preferredSports);

  const [incomingLikes, searchResponsesToMySearches, myApplicationUpdates, hotEvents] = await Promise.all([
    prisma.swipe.findMany({
      where: {
        toUserId: userId,
        action: {
          in: ["like", "superlike"]
        },
        fromUser: {
          onboardingCompleted: true,
          isVerified: true
        }
      },
      include: {
        fromUser: true
      },
      orderBy: {
        createdAt: "desc"
      },
      take: 20
    }),
    prisma.gameSearchResponse.findMany({
      where: {
        gameSearch: {
          createdByUserId: userId
        },
        status: "pending"
      },
      include: {
        responderUser: true,
        gameSearch: true
      },
      orderBy: {
        createdAt: "desc"
      },
      take: 20
    }),
    prisma.gameSearchResponse.findMany({
      where: {
        responderUserId: userId,
        status: {
          in: ["approved", "rejected"]
        }
      },
      include: {
        gameSearch: {
          include: {
            createdByUser: true
          }
        }
      },
      orderBy: {
        updatedAt: "desc"
      },
      take: 20
    }),
    prisma.gameSearch.findMany({
      where: {
        isActive: true,
        searchType: "hot",
        hotStartsAt: {
          gt: new Date()
        },
        sport: {
          in: viewerSports
        },
        createdByUserId: {
          not: userId
        },
        responses: {
          none: {
            responderUserId: userId
          }
        }
      },
      include: {
        createdByUser: true,
        preferredCourt: true
      },
      orderBy: {
        createdAt: "desc"
      },
      take: 20
    })
  ]);

  const outgoingSwipes = await prisma.swipe.findMany({
    where: {
      fromUserId: userId
    },
    select: {
      toUserId: true
    }
  });

  const respondedIds = new Set(outgoingSwipes.map((swipe) => swipe.toUserId));

  const notifications = [
    ...incomingLikes
      .filter((like) => !respondedIds.has(like.fromUserId))
      .map((like) => ({
        id: `like-${like.id}`,
        type: "incoming_like" as const,
        createdAt: like.createdAt,
        title: `${like.fromUser.name ?? "Игрок"} хочет с тобой сыграть`,
        description: "Открой вкладку «Хотят с тобой», чтобы ответить лайком или пропустить.",
        href: "/discover?view=likes"
      })),
    ...searchResponsesToMySearches.map((response) => ({
      id: `response-${response.id}`,
      type: "search_response" as const,
      createdAt: response.createdAt,
      title: `${response.responderUser.name ?? "Игрок"} откликнулся на твой поиск`,
      description: "Можно открыть свои поиски и решить, подтверждать ли отклик.",
      href: "/play/searches"
    })),
    ...myApplicationUpdates.map((response) => ({
      id: `application-${response.id}`,
      type: "application_result" as const,
      createdAt: response.updatedAt,
      title:
        response.status === "approved"
          ? `Твой отклик одобрен: ${response.gameSearch.createdByUser.name ?? "организатор"}`
          : `Твой отклик отклонён: ${response.gameSearch.createdByUser.name ?? "организатор"}`,
      description:
        response.status === "approved"
          ? "Проверь чат или страницу игры: организатор подтвердил участие."
          : "Можешь открыть поиск и откликнуться на другие активности.",
      href: response.status === "approved" ? "/inbox" : "/discover?view=seeking"
    })),
    ...hotEvents.map((search) => ({
      id: `hot-${search.id}`,
      type: "hot_event" as const,
      createdAt: search.createdAt,
      title: `${search.createdByUser.name ?? "Игрок"} ищет срочно ${search.sport}`,
      description: search.preferredCourt
        ? `Есть площадка: ${search.preferredCourt.name}. Проверь вкладку «Срочно».`
        : "Новое срочное событие по одному из твоих видов спорта.",
      href: "/discover?view=hot"
    }))
  ];

  return notifications.sort((left, right) => right.createdAt.getTime() - left.createdAt.getTime()).slice(0, 30);
}

export async function getUpcomingGamesForUser(userId: string) {
  return prisma.gameRequest.findMany({
    where: {
      status: "accepted",
      proposedDatetime: {
        gte: new Date()
      },
      OR: [{ createdByUserId: userId }, { matchedUserId: userId }]
    },
    include: {
      proposedCourt: true,
      createdByUser: true,
      matchedUser: true,
      match: true
    },
    orderBy: {
      proposedDatetime: "asc"
    },
    take: 5
  });
}

export async function getMatchesForUser(userId: string) {
  return prisma.match.findMany({
    where: {
      status: "active",
      OR: [{ user1Id: userId }, { user2Id: userId }]
    },
    include: {
      user1: true,
      user2: true,
      messages: {
        include: {
          senderUser: true
        },
        where: {
          gameRequestId: null
        },
        orderBy: {
          createdAt: "desc"
        },
        take: 1
      },
      gameRequests: {
        include: {
          proposedCourt: true,
          createdByUser: true,
          matchedUser: true
        },
        orderBy: {
          createdAt: "desc"
        },
        take: 1
      }
    },
    orderBy: {
      updatedAt: "desc"
    }
  });
}

export async function getMatchDetail(matchId: string, userId: string) {
  return prisma.match.findFirst({
    where: {
      id: matchId,
      status: "active",
      OR: [{ user1Id: userId }, { user2Id: userId }]
    },
    include: {
      user1: true,
      user2: true,
      messages: {
        include: {
          senderUser: true
        },
        where: {
          gameRequestId: null
        },
        orderBy: {
          createdAt: "asc"
        }
      },
      gameRequests: {
        include: {
          proposedCourt: true,
          createdByUser: true,
          matchedUser: true
        },
        orderBy: {
          createdAt: "desc"
        }
      }
    }
  });
}

export async function getGameRequestDetail(gameRequestId: string, userId: string) {
  return prisma.gameRequest.findFirst({
    where: {
      id: gameRequestId,
      OR: [{ createdByUserId: userId }, { matchedUserId: userId }]
    },
    include: {
      proposedCourt: true,
      messages: {
        include: {
          senderUser: true
        },
        orderBy: {
          createdAt: "asc"
        }
      },
      createdByUser: true,
      matchedUser: true,
      match: {
        include: {
          user1: true,
          user2: true,
          messages: {
            include: {
              senderUser: true
            },
            where: {
              gameRequestId: null
            },
            orderBy: {
              createdAt: "asc"
            }
          },
          gameRequests: {
            include: {
              proposedCourt: true,
              createdByUser: true,
              matchedUser: true
            },
            orderBy: {
              createdAt: "desc"
            }
          }
        }
      }
    }
  });
}

export type CourtsFilters = {
  sport?: import("@prisma/client").Sport;
  q?: string;
  district?: string;
  maxDistanceKm?: number;
  city?: string;
};

export async function getCourtsForUser(
  userId: string,
  filters: CourtsFilters = {}
) {
  const user = await prisma.user.findUnique({
    where: { id: userId }
  });

  if (!user) {
    return [];
  }

  const courts = await prisma.court.findMany({
    where: {
      city: filters.city,
      ...(filters.district ? { district: filters.district } : {}),
      ...(filters.q
        ? {
            OR: [
              {
                name: {
                  contains: filters.q,
                  mode: "insensitive"
                }
              },
              {
                address: {
                  contains: filters.q,
                  mode: "insensitive"
                }
              },
              {
                district: {
                  contains: filters.q,
                  mode: "insensitive"
                }
              }
            ]
          }
        : {})
    },
    include: {
      nearestMetro: true
    },
    orderBy: [{ rating: "desc" }, { name: "asc" }]
  });

  return courts
    .map((court) => ({
      ...court,
      distanceKm: haversineDistanceKm(
        user.homeLat != null && user.homeLng != null ? { lat: user.homeLat, lng: user.homeLng } : null,
        { lat: court.locationLat, lng: court.locationLng }
      )
    }))
    .filter((court) =>
      courtSupportsSport(court.supportedSports, filters.sport) &&
      (filters.maxDistanceKm && court.distanceKm != null
        ? court.distanceKm <= filters.maxDistanceKm
        : true
      )
    )
    .sort((first, second) => {
      const firstDistance = first.distanceKm ?? Number.POSITIVE_INFINITY;
      const secondDistance = second.distanceKm ?? Number.POSITIVE_INFINITY;

      if (firstDistance !== secondDistance) {
        return firstDistance - secondDistance;
      }

      return (second.rating ?? 0) - (first.rating ?? 0);
    });
}

function getDiscoverCandidatesFromUsers(
  viewer: Awaited<ReturnType<typeof prisma.user.findUnique>>,
  users: Array<{
    id: string;
    name: string | null;
    age: number | null;
    gender: import("@prisma/client").Gender | null;
    city: string | null;
    bio: string | null;
    avatarUrl: string | null;
    homeLat: number | null;
    homeLng: number | null;
    tennisLevel: number | null;
    preferredSports: unknown;
    sportLevels: unknown;
    preferredPlayFormat: import("@prisma/client").PlayFormat;
    preferredSurface: import("@prisma/client").Surface;
    availableDays: unknown;
    availableTimeRanges: unknown;
    availableTimeSlots: unknown;
    searchRadiusKm: number;
    isLookingForGame: boolean;
    gameSearches?: unknown;
  }>,
  filters: DiscoverFilters
) {
  if (!viewer) {
    return [];
  }

  return scoreCandidates(
    {
      id: viewer.id,
      name: viewer.name,
      age: viewer.age,
      gender: viewer.gender,
      city: viewer.city,
      bio: viewer.bio,
      avatarUrl: viewer.avatarUrl,
      homeLat: viewer.homeLat,
      homeLng: viewer.homeLng,
      tennisLevel: viewer.tennisLevel,
      preferredSports: viewer.preferredSports,
      sportLevels: viewer.sportLevels,
      preferredPlayFormat: viewer.preferredPlayFormat,
      preferredSurface: viewer.preferredSurface,
      availableDays: viewer.availableDays,
      availableTimeRanges: viewer.availableTimeRanges,
      availableTimeSlots: viewer.availableTimeSlots,
      searchRadiusKm: viewer.searchRadiusKm,
      isLookingForGame: viewer.isLookingForGame
    },
    users as Array<any>,
    filters
  );
}
