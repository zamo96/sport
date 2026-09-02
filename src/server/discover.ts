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
import { getLocationPlace } from "@/server/locations";
import { recordDiscoverImpressions, rerankDiscoverCandidates } from "@/server/recommendations";

const candidateBaseSelect = {
  id: true,
  name: true,
  age: true,
  gender: true,
  city: true,
  locationPlaceId: true,
  location: { include: { serviceArea: true } },
  district: true,
  preferredDistricts: true,
  bio: true,
  avatarUrl: true,
  profilePhotoUrls: true,
  profileVideoUrls: true,
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
  lastActiveAt: true,
  createdAt: true
} satisfies Prisma.UserSelect;

async function fetchCandidatePool(viewerId: string | null, filters: DiscoverFilters = {}) {
  const keepsSearchCandidatesVisible = filters.view === "seeking" || filters.view === "hot";
  const candidates = await prisma.user.findMany({
    where: {
      accountStatus: "active",
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
                  },
                  matchesAsUser1: {
                    none: {
                      user2Id: viewerId,
                      status: "active"
                    }
                  },
                  matchesAsUser2: {
                    none: {
                      user1Id: viewerId,
                      status: "active"
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
        orderBy:
          filters.view === "hot"
            ? [
                {
                  hotStartsAt: "asc"
                },
                {
                  createdAt: "desc"
                }
              ]
            : {
                createdAt: "desc"
              }
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
    const gameSearches = Array.isArray(candidate.gameSearches) ? candidate.gameSearches : [];

    if (filters.view === "seeking" || filters.view === "hot") {
      const hasMatchingSearch = gameSearches.some((search) => {
        if (!search.sport) {
          return false;
        }

        if (filters.sport && filters.sport.length > 0 && !filters.sport.includes(search.sport)) {
          return false;
        }

        if (viewer.locationPlaceId && search.locationPlaceId && viewer.locationPlaceId !== search.locationPlaceId) {
          return false;
        }

        return viewerSports.includes(search.sport);
      });

      if (!hasMatchingSearch) {
        return false;
      }

      return true;
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
    locationPlaceId: viewer.locationPlaceId,
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
    isLookingForGame: viewer.isLookingForGame,
    lastActiveAt: viewer.lastActiveAt,
    createdAt: viewer.createdAt
  } satisfies CandidateUser;
}

/**
 * Ступени расширения для холодного старта. Пока кандидатов меньше порога,
 * пускаем игроков из соседних городов — сначала ближних, потом дальних.
 * Показать человека в сорока километрах честнее, чем пустой экран.
 */
const NEARBY_RADIUS_STEPS_KM = [60, 200] as const;
const MIN_CANDIDATES_BEFORE_WIDENING = 5;

export function widenCandidateSearch<T extends { length: number }>(
  scoreWith: (nearbyRadiusKm?: number) => T
): T {
  let result = scoreWith();

  for (const radiusKm of NEARBY_RADIUS_STEPS_KM) {
    if (result.length >= MIN_CANDIDATES_BEFORE_WIDENING) {
      return result;
    }

    result = scoreWith(radiusKm);
  }

  return result;
}

async function scoreCandidatesForViewer(viewer: CandidateUser, viewerId: string | null, filters: DiscoverFilters = {}) {
  const candidates = await fetchCandidatePool(viewerId, filters);
  const filteredCandidates = filterCandidatesForView(viewer, candidates, filters);

  const viewerProfile = toCandidateViewer(viewer);
  const scored = widenCandidateSearch((nearbyRadiusKm) =>
    scoreCandidates(viewerProfile, filteredCandidates, filters, { nearbyRadiusKm })
  );
  const ranked = viewerId ? await rerankDiscoverCandidates(viewerId, scored, filters) : scored;
  const source = filters.view ?? "discover";

  if (viewerId) {
    await recordDiscoverImpressions(viewerId, ranked, source);
  }

  return ranked.map((candidate) => ({
    ...candidate,
    explainabilityReasons: buildDiscoverExplainabilityReasons(viewerProfile, candidate, filters)
  }));
}

/**
 * Сколько кандидатов игрок увидел бы в поиске — всего и появившихся недавно.
 * Намеренно не идёт через `getDiscoverCandidates`: тот пишет
 * `DiscoverImpression`, а показа здесь нет — это проверка перед отправкой пуша,
 * и фальшивые показы испортили бы разметку.
 */
export async function summarizeDiscoverCandidates(
  userId: string,
  options: { filters?: DiscoverFilters; newerThan?: Date | null } = {}
) {
  const filters = options.filters ?? {};
  const viewer = await prisma.user.findUnique({
    where: { id: userId }
  });

  if (!viewer) {
    return { total: 0, fresh: 0 };
  }

  const pool = await fetchCandidatePool(userId, filters);
  const filtered = filterCandidatesForView(viewer, pool, filters);
  // Тот же каскад, что и в самом поиске: иначе кампания насчитает меньше
  // кандидатов, чем игрок увидит на экране, и промолчит без причины.
  const scored = widenCandidateSearch((nearbyRadiusKm) =>
    scoreCandidates(toCandidateViewer(viewer), filtered, filters, { nearbyRadiusKm })
  );
  const newerThan = options.newerThan;

  return {
    total: scored.length,
    fresh: newerThan
      ? scored.filter((candidate) => candidate.createdAt != null && candidate.createdAt > newerThan).length
      : 0
  };
}

export async function countDiscoverCandidates(userId: string, filters: DiscoverFilters = {}) {
  return (await summarizeDiscoverCandidates(userId, { filters })).total;
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
  const canonicalPlace = draft.locationPlaceId ? await getLocationPlace(draft.locationPlaceId) : null;
  if (draft.locationPlaceId && !canonicalPlace) {
    throw new Error("Выбранный город не найден. Выполните поиск города ещё раз");
  }
  const preferredDistricts = canonicalPlace && !canonicalPlace.coverage.districtsEnabled ? [] : draft.preferredDistricts;
  const primaryDistrict = preferredDistricts[0] ?? (canonicalPlace && !canonicalPlace.coverage.districtsEnabled ? null : draft.district) ?? null;
  const districtLocation = resolveLocationFromDistrict(primaryDistrict);
  const location = canonicalPlace
    ? { lat: canonicalPlace.latitude, lng: canonicalPlace.longitude }
    : districtLocation ?? (await resolveLocationFromCity(draft.city));
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
    city: canonicalPlace?.city ?? draft.city,
    locationPlaceId: canonicalPlace?.id ?? null,
    district: primaryDistrict,
    preferredDistricts,
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
