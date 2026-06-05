import { Prisma } from "@prisma/client";

import { resolveLocationFromCity, resolveLocationFromDistrict } from "@/lib/geo";
import { prisma } from "@/lib/prisma";
import { getPrimarySportLevel, normalizeSportLevels } from "@/lib/sport-levels";
import {
  buildDiscoverExplainabilityReasons,
  parseSports,
  type CandidateUser,
  type DiscoverFilters,
  scoreCandidates
} from "@/lib/scoring";
import type { GuestOnboardingDraft } from "@/lib/guest-draft";

const candidateBaseSelect = {
  id: true,
  name: true,
  age: true,
  gender: true,
  city: true,
  district: true,
  preferredDistricts: true,
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
  isLookingForGame: true
} satisfies Prisma.UserSelect;

async function fetchCandidatePool(viewerId: string | null, filters: DiscoverFilters = {}) {
  const keepsSearchCandidatesVisible = filters.view === "seeking" || filters.view === "hot";
  const candidates = await prisma.user.findMany({
    where: {
      ...(viewerId ? { id: { not: viewerId } } : {}),
      onboardingCompleted: true,
      isVerified: true,
      ...(viewerId
        ? {
            blockedUsers: {
              none: {
                blockedUserId: viewerId
              }
            },
            blockingUsers: {
              none: {
                blockerUserId: viewerId
              }
            },
            ...(!keepsSearchCandidatesVisible
              ? {
                  swipesReceived: {
                    none: {
                      fromUserId: viewerId
                    }
                  }
                }
              : {})
          }
        : {}),
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
              gameSearches: {
                some: {
                  isActive: true,
                  searchType: "regular"
                }
              }
            }
        : {})
    },
    select: {
      ...candidateBaseSelect,
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
            : filters.view === "seeking"
              ? {
                  searchType: "regular"
                }
            : {})
        },
        include: {
          preferredCourt: true,
          regularPair: {
            include: {
              partnerUser: true,
              preferredCourt: true
            }
          },
          responses: viewerId
            ? {
                where: {
                  OR: [
                    {
                      responderUserId: viewerId
                    },
                    {
                      status: "approved"
                    }
                  ]
                },
                include: {
                  responderUser: true
                }
              }
            : {
                where: {
                  responderUserId: "__guest__"
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

  if (!viewerId) {
    return candidates;
  }

  return candidates.map((candidate) => ({
    ...candidate,
    gameSearches: candidate.gameSearches.map((search) => ({
      ...search,
      responses: [...search.responses].sort((left, right) => {
        const leftIsViewer = left.responderUserId === viewerId;
        const rightIsViewer = right.responderUserId === viewerId;
        if (leftIsViewer == rightIsViewer) {
          return 0;
        }
        return leftIsViewer ? -1 : 1;
      })
    }))
  }));
}

type DiscoverCandidateRecord = Awaited<ReturnType<typeof fetchCandidatePool>>[number];

function filterCandidatesForView(
  viewer: CandidateUser,
  candidates: DiscoverCandidateRecord[],
  filters: DiscoverFilters = {}
) {
  const viewerSports = parseSports(viewer.preferredSports);

  return candidates.filter((candidate) => {
    const latestSearch = Array.isArray(candidate.gameSearches) ? candidate.gameSearches[0] : null;

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
}

function toCandidateViewer(viewer: CandidateUser) {
  return {
    id: viewer.id,
    name: viewer.name,
    age: viewer.age,
    gender: viewer.gender,
    city: viewer.city,
    district: viewer.district,
    preferredDistricts: viewer.preferredDistricts,
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
  } satisfies CandidateUser;
}

async function scoreCandidatesForViewer(viewer: CandidateUser, viewerId: string | null, filters: DiscoverFilters = {}) {
  const candidates = await fetchCandidatePool(viewerId, filters);
  const filteredCandidates = filterCandidatesForView(viewer, candidates, filters);

  const viewerProfile = toCandidateViewer(viewer);
  const scored = scoreCandidates(viewerProfile, filteredCandidates, filters);

  return scored.map((candidate) => ({
    ...candidate,
    explainabilityReasons: buildDiscoverExplainabilityReasons(viewerProfile, candidate, filters)
  }));
}

export async function getDiscoverCandidates(userId: string, filters: DiscoverFilters = {}) {
  const viewer = await prisma.user.findUnique({
    where: { id: userId }
  });

  if (!viewer) {
    return [];
  }

  return scoreCandidatesForViewer(toCandidateViewer(viewer), userId, filters);
}

export async function getDiscoverCandidatesForGuestDraft(draft: GuestOnboardingDraft, filters: DiscoverFilters = {}) {
  const primaryDistrict = draft.preferredDistricts[0] ?? draft.district ?? null;
  const location = resolveLocationFromDistrict(primaryDistrict) ?? (await resolveLocationFromCity(draft.city));
  const sportLevels = normalizeSportLevels(draft.sportLevels, draft.preferredSports, 5);
  const tennisLevel = getPrimarySportLevel(draft.preferredSports, sportLevels, 5);
  const availabilityByDay = Object.fromEntries(
    Object.entries(draft.availabilityByDay ?? {}).filter(([, ranges]) => Array.isArray(ranges) && ranges.length > 0)
  ) as Record<string, string[]>;
  const availabilityEntries = Object.entries(availabilityByDay);
  const availableDays =
    availabilityEntries.length > 0 ? availabilityEntries.map(([day]) => day) : draft.availableDays;
  const availableTimeRanges =
    availabilityEntries.length > 0
      ? Array.from(new Set(availabilityEntries.flatMap(([, ranges]) => ranges)))
      : draft.availableTimeRanges;

  const viewer: CandidateUser = {
    id: "guest",
    name: draft.name,
    age: draft.age,
    gender: draft.gender ?? null,
    city: draft.city,
    district: primaryDistrict,
    preferredDistricts: draft.preferredDistricts,
    bio: null,
    avatarUrl: null,
    homeLat: location?.lat ?? null,
    homeLng: location?.lng ?? null,
    tennisLevel,
    preferredSports: draft.preferredSports,
    sportLevels,
    preferredPlayFormat: draft.preferredPlayFormat,
    preferredSurface: draft.preferredSurface,
    availableDays,
    availableTimeRanges,
    availableTimeSlots: availableDays.flatMap((day) =>
      (availabilityByDay[day] ?? availableTimeRanges).map((timeRange) => `${day}-${timeRange}`)
    ),
    searchRadiusKm: draft.searchRadiusKm,
    isLookingForGame: draft.isLookingForGame
  };

  return scoreCandidatesForViewer(viewer, null, filters);
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
