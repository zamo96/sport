import { prisma } from "@/lib/prisma";
import { haversineDistanceKm } from "@/lib/geo";
import { type DiscoverFilters } from "@/lib/scoring";
import { getDiscoverCandidates } from "@/server/discover";

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
  return getDiscoverCandidates(userId, {
    ...filters,
    view: "seeking"
  });
}

export async function getHotPlayers(userId: string, filters: DiscoverFilters = {}) {
  return getDiscoverCandidates(userId, {
    ...filters,
    view: "hot"
  });
}

export async function getGameSearchesForUser(userId: string) {
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

export async function getMatchesForUser(userId: string) {
  return prisma.match.findMany({
    where: {
      OR: [{ user1Id: userId }, { user2Id: userId }]
    },
    include: {
      user1: true,
      user2: true,
      messages: {
        include: {
          senderUser: true
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
      OR: [{ user1Id: userId }, { user2Id: userId }]
    },
    include: {
      user1: true,
      user2: true,
      messages: {
        include: {
          senderUser: true
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
  surface?: "hard" | "clay" | "grass" | "any";
  setting?: "indoor" | "outdoor";
  maxDistanceKm?: number;
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
      surface: filters.surface,
      setting: filters.setting
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
      filters.maxDistanceKm && court.distanceKm != null
        ? court.distanceKm <= filters.maxDistanceKm
        : true
    );
}
