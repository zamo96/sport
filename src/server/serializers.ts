import type { Court, GameRequest, Match, Metro, User } from "@prisma/client";

import { formatDistanceKm } from "@/lib/utils";

export function serializeUserPreview(user: Partial<User> & { distanceKm?: number | null; score?: number | null }) {
  return {
    id: user.id,
    name: user.name,
    age: user.age,
    city: user.city,
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
    score: user.score ?? null
  };
}

export function serializeCourt(court: Court & { distanceKm?: number | null; nearestMetro?: Metro | null }) {
  return {
    ...court,
    nearestMetroName: court.nearestMetro?.name ?? null,
    distanceKm: court.distanceKm ?? null,
    distanceLabel: formatDistanceKm(court.distanceKm)
  };
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
