import type { Court, GameRequest, Match, Metro, User, UserCourt } from "@prisma/client";

import { getDistrictLabel } from "@/lib/constants";
import { formatDistanceKm } from "@/lib/utils";

export function serializeUserPreview(
  user: Partial<User> & {
    distanceKm?: number | null;
    score?: number | null;
    explainabilityReasons?: string[] | null;
  }
) {
  return {
    id: user.id,
    name: user.name,
    age: user.age,
    city: user.city,
    district: "district" in user ? (user as Partial<User> & { district?: string | null }).district ?? null : null,
    districtLabel:
      "district" in user
        ? getDistrictLabel((user as Partial<User> & { district?: string | null }).district ?? null)
        : null,
    preferredDistricts:
      "preferredDistricts" in user && Array.isArray((user as Partial<User> & { preferredDistricts?: unknown }).preferredDistricts)
        ? ((user as Partial<User> & { preferredDistricts?: unknown }).preferredDistricts as unknown[]).filter(
            (district): district is string => typeof district === "string"
          )
        : [],
    bio: user.bio,
    avatarUrl: user.avatarUrl,
    tennisLevel: user.tennisLevel,
    preferredSports: user.preferredSports,
    sportLevels: "sportLevels" in user ? (user as Partial<User> & { sportLevels?: unknown }).sportLevels : undefined,
    preferredPlayFormat: user.preferredPlayFormat,
    preferredSurface: user.preferredSurface,
    availableDays: user.availableDays,
    availableTimeRanges: user.availableTimeRanges,
    availableTimeSlots: user.availableTimeSlots,
    isLookingForGame: user.isLookingForGame,
    gameSearches: "gameSearches" in user ? (user as Partial<User> & { gameSearches?: unknown }).gameSearches : undefined,
    distanceKm: user.distanceKm ?? null,
    distanceLabel: formatDistanceKm(user.distanceKm),
    score: user.score ?? null,
    explainabilityReasons: user.explainabilityReasons ?? []
  };
}

export function serializeCourt(
  court: Court & {
    distanceKm?: number | null;
    nearestMetro?: Metro | null;
    members?: Array<UserCourt & { user: User }>;
    _count?: { members?: number };
    isMember?: boolean;
  }
) {
  const photoUrls = normalizeCourtPhotoUrls(court.photoUrls, court.photoUrl);

  return {
    ...court,
    photoUrl: court.photoUrl ?? photoUrls[0] ?? null,
    photoUrls,
    nearestMetroName: court.nearestMetro?.name ?? null,
    distanceKm: court.distanceKm ?? null,
    distanceLabel: formatDistanceKm(court.distanceKm),
    isMember: court.isMember ?? false,
    memberCount: court._count?.members ?? court.members?.length ?? 0,
    members: court.members?.map((member) => serializeUserPreview(member.user)) ?? []
  };
}

function normalizeCourtPhotoUrls(value: unknown, fallbackPhotoUrl?: string | null) {
  const rawUrls = Array.isArray(value) ? value : [];
  const urls = rawUrls.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
  if (fallbackPhotoUrl) {
    urls.unshift(fallbackPhotoUrl);
  }

  return Array.from(new Set(urls.map((url) => url.trim()).filter(Boolean))).slice(0, 8);
}

export function serializeGameRequest(gameRequest: GameRequest & { proposedCourt?: Court | null }) {
  return {
    ...gameRequest,
    proposedDatetime: gameRequest.proposedDatetime.toISOString(),
    durationMinutes: gameRequest.durationMinutes ?? null,
    outcomeUpdatedAt: gameRequest.outcomeUpdatedAt?.toISOString() ?? null
  };
}

export function otherUserFromMatch(match: Match & { user1: User; user2: User }, currentUserId: string) {
  return match.user1Id === currentUserId ? match.user2 : match.user1;
}
