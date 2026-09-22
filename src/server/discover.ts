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
import { scoreCandidate } from "@/lib/scoring";
import { selectNearby, type NearbyMetadata, validCoordinates } from "@/lib/nearby";
import { resolveNearbyOrigin } from "@/server/nearby-location";

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
  showOnMap: true,
  bio: true,
  avatarUrl: true,
  profilePhotoUrls: true,
  profileVideoUrls: true,
  profileMediaOrder: true,
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
              partnerUser: { include: { location: { include: { serviceArea: true } } } },
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
                  responderUser: { include: { location: { include: { serviceArea: true } } } }
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
    isLookingForGame: viewer.isLookingForGame,
    lastActiveAt: viewer.lastActiveAt,
    createdAt: viewer.createdAt
  } satisfies CandidateUser;
}

async function scoreCandidatesForViewer(viewer: CandidateUser, viewerId: string | null, filters: DiscoverFilters = {}) {
  const candidates = await fetchCandidatePool(viewerId, filters);
  const { scored, viewerProfile } = await selectDiscoverCandidates(viewer, candidates, filters);
  const ranked = viewerId ? await rerankDiscoverCandidates(viewerId, scored, filters) : scored;
  if (scored[0]?.nearby) ranked.sort((left, right) => left.distanceKm! - right.distanceKm! ||
    (right.recommendationScore ?? right.score) - (left.recommendationScore ?? left.score) || left.id.localeCompare(right.id));
  const source = filters.view ?? "discover";

  if (viewerId) {
    await recordDiscoverImpressions(viewerId, ranked, source);
  }

  return ranked.map((candidate) => ({
    ...candidate,
    explainabilityReasons: buildDiscoverExplainabilityReasons(viewerProfile, candidate, filters)
  }));
}

/** Same eligible result set for presentation and notification counts; no impressions here. */
async function selectDiscoverCandidates(viewer: CandidateUser, candidates: DiscoverCandidateRecord[], filters: DiscoverFilters) {
  const isPrimary = filters.view == null || filters.view === "swipe";
  const origin = isPrimary ? await resolveNearbyOrigin(viewer, filters.city, filters.locationPlaceId) : null;
  const viewerProfile = toCandidateViewer(viewer);
  if (isPrimary && (filters.city || filters.locationPlaceId) && origin) {
    viewerProfile.city = origin.city;
    viewerProfile.locationPlaceId = origin.locationPlaceId;
    viewerProfile.homeLat = origin.coordinates.lat;
    viewerProfile.homeLng = origin.coordinates.lng;
  }
  const filtered = filterCandidatesForView(viewerProfile, candidates, filters);
  type Scored = ReturnType<typeof scoreCandidates<DiscoverCandidateRecord>>[number] & { nearby?: NearbyMetadata; recommendationScore?: number };
  if (isPrimary && filters.locationPlaceId && !origin) return { scored: [] as Scored[], viewerProfile };
  const local: Scored[] = scoreCandidates(viewerProfile, filtered, filters);
  if (local.length || !isPrimary || !origin) return { scored: local, viewerProfile };
  const nearbyViewer = { ...viewerProfile, homeLat: origin.coordinates.lat, homeLng: origin.coordinates.lng };
  const measured = filtered.flatMap((candidate) => {
    const home = candidate.homeLat != null && candidate.homeLng != null
      ? { lat: candidate.homeLat, lng: candidate.homeLng } : null;
    const center = candidate.location ? { lat: candidate.location.latitude, lng: candidate.location.longitude } : null;
    const coordinates = validCoordinates(home) ? home : validCoordinates(center) ? center : null;
    if (!coordinates) return [];
    const scored = scoreCandidate(nearbyViewer, { ...candidate, homeLat: coordinates.lat, homeLng: coordinates.lng },
      { ...filters, distanceKm: undefined }, "nearby");
    return scored ? [scored] : [];
  });
  const nearby: Scored[] = selectNearby(measured, origin.city, 12, filters.distanceKm, (left, right) => right.score - left.score);
  return { scored: nearby, viewerProfile: nearbyViewer };
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
  const { scored } = await selectDiscoverCandidates(viewer, pool, filters);
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
