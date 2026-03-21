import { prisma } from "@/lib/prisma";
import { haversineDistanceKm } from "@/lib/geo";
import { type DiscoverFilters } from "@/lib/scoring";
import { courtSupportsSport } from "@/lib/courts";
import { getDiscoverCandidates } from "@/server/discover";

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
