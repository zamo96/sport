import { Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";
import { parseSports, type DiscoverFilters, scoreCandidates } from "@/lib/scoring";

export async function getDiscoverCandidates(userId: string, filters: DiscoverFilters = {}) {
  const viewer = await prisma.user.findUnique({
    where: { id: userId }
  });

  if (!viewer) {
    return [];
  }

  const candidates = await prisma.user.findMany({
    where: {
      id: { not: userId },
      onboardingCompleted: true,
      isVerified: true,
      ...(filters.view === "hot"
        ? {
            gameSearches: {
              some: {
                isActive: true,
                searchType: "hot",
                hotStartsAt: {
                  gt: new Date()
                }
              }
            }
          }
        : filters.view === "seeking"
        ? {
            OR: [
              { isLookingForGame: true },
              {
                gameSearches: {
                  some: {
                    isActive: true
                  }
                }
              }
            ]
          }
        : {}),
      swipesReceived: {
        none: {
          fromUserId: userId
        }
      }
    },
    select: {
      id: true,
      name: true,
      age: true,
      gender: true,
      city: true,
      bio: true,
      avatarUrl: true,
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
      isLookingForGame: true,
      gameSearches: {
        where: {
          isActive: true,
          ...(filters.view === "hot"
            ? {
                searchType: "hot",
                hotStartsAt: {
                  gt: new Date()
                }
              }
            : {})
        },
        include: {
          preferredCourt: true,
          responses: {
            where: {
              responderUserId: userId
            },
            include: {
              responderUser: true
            }
          }
        },
        orderBy: {
          createdAt: "desc"
        },
        take: 1
      }
    }
  });

  const filteredCandidates = candidates.filter((candidate) => {
    const latestSearch = Array.isArray(candidate.gameSearches) ? candidate.gameSearches[0] : null;
    const viewerSports = parseSports(viewer.preferredSports);

    if (filters.view === "seeking" || filters.view === "hot") {
      if (!latestSearch?.sport) {
        return false;
      }

      if (filters.sport && filters.sport.length > 0 && !filters.sport.includes(latestSearch.sport)) {
        return false;
      }

      return viewerSports.includes(latestSearch.sport);
    }

    return true;
  });

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
    filteredCandidates,
    filters
  );
}

export const matchWithRelations = Prisma.validator<Prisma.MatchDefaultArgs>()({
  include: {
    user1: true,
    user2: true,
    messages: {
      orderBy: {
        createdAt: "desc"
      },
      take: 1
    },
    gameRequests: {
      include: {
        proposedCourt: true
      },
      orderBy: {
        createdAt: "desc"
      },
      take: 1
    }
  }
});

export type MatchWithRelations = Prisma.MatchGetPayload<typeof matchWithRelations>;
