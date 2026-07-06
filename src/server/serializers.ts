import type {
  Court,
  CourtMetro,
  GameReport,
  GameReportConfirmation,
  GameReportPhoto,
  GameRequest,
  Match,
  Metro,
  PersonalActivity,
  PersonalActivityPhoto,
  User,
  UserCourt
} from "@prisma/client";

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
    profilePhotoUrls:
      "profilePhotoUrls" in user
        ? normalizeStringArray((user as Partial<User> & { profilePhotoUrls?: unknown }).profilePhotoUrls, 6)
        : [],
    profileVideoUrls:
      "profileVideoUrls" in user
        ? normalizeStringArray((user as Partial<User> & { profileVideoUrls?: unknown }).profileVideoUrls, 4)
        : [],
    lastActiveAt:
      "lastActiveAt" in user
        ? (user as Partial<User> & { lastActiveAt?: Date | null }).lastActiveAt?.toISOString() ?? null
        : null,
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
    metroLinks?: Array<CourtMetro & { metro: Metro }>;
    members?: Array<UserCourt & { user: User }>;
    _count?: { members?: number };
    isMember?: boolean;
  }
) {
  const photoUrls = normalizeCourtPhotoUrls(court.photoUrls, court.photoUrl);
  const amenities = normalizeStringArray(court.amenities, 12);
  const metroNames = normalizeCourtMetroNames(court.metroLinks, court.nearestMetro);

  return {
    ...court,
    photoUrl: court.photoUrl ?? photoUrls[0] ?? null,
    photoUrls,
    amenities,
    nearestMetroName: court.nearestMetro?.name ?? metroNames[0] ?? null,
    metroNames,
    distanceKm: court.distanceKm ?? null,
    distanceLabel: formatDistanceKm(court.distanceKm),
    isMember: court.isMember ?? false,
    memberCount: court._count?.members ?? court.members?.length ?? 0,
    members: court.members?.map((member) => serializeUserPreview(member.user)) ?? []
  };
}

function normalizeCourtMetroNames(metroLinks?: Array<CourtMetro & { metro: Metro }>, nearestMetro?: Metro | null) {
  const names = [
    ...(metroLinks
      ?.slice()
      .sort((left, right) => left.position - right.position)
      .map((link) => link.metro.name) ?? []),
    nearestMetro?.name
  ].filter((name): name is string => Boolean(name));

  return Array.from(new Set(names.map((name) => name.trim()).filter(Boolean))).slice(0, 8);
}

function normalizeCourtPhotoUrls(value: unknown, fallbackPhotoUrl?: string | null) {
  const rawUrls = Array.isArray(value) ? value : [];
  const urls = rawUrls.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
  if (fallbackPhotoUrl) {
    urls.unshift(fallbackPhotoUrl);
  }

  return Array.from(new Set(urls.map((url) => url.trim()).filter(Boolean))).slice(0, 8);
}

function normalizeStringArray(value: unknown, limit: number) {
  const rawItems = Array.isArray(value) ? value : [];
  return Array.from(
    new Set(
      rawItems
        .filter((item): item is string => typeof item === "string" && item.trim().length > 0)
        .map((item) => item.trim())
    )
  ).slice(0, limit);
}

type GameReportWithRelations = GameReport & {
  createdByUser?: User | null;
  photos?: GameReportPhoto[];
  confirmations?: Array<GameReportConfirmation & { user?: User | null }>;
};

export function serializeGameReport(report?: GameReportWithRelations | null) {
  if (!report) {
    return null;
  }

  return {
    id: report.id,
    gameRequestId: report.gameRequestId,
    createdByUserId: report.createdByUserId,
    comment: report.comment ?? null,
    visibility: report.visibility,
    status: report.status,
    createdAt: report.createdAt.toISOString(),
    updatedAt: report.updatedAt.toISOString(),
    createdByUser: report.createdByUser ? serializeUserPreview(report.createdByUser) : null,
    photos:
      report.photos
        ?.slice()
        .sort((left, right) => left.position - right.position)
        .map((photo) => ({
          id: photo.id,
          url: photo.url,
          position: photo.position
        })) ?? [],
    confirmations:
      report.confirmations?.map((confirmation) => ({
        id: confirmation.id,
        userId: confirmation.userId,
        status: confirmation.status,
        user: confirmation.user ? serializeUserPreview(confirmation.user) : null
      })) ?? []
  };
}

export function serializeGameRequest(gameRequest: GameRequest & { proposedCourt?: Court | null; report?: GameReportWithRelations | null }) {
  return {
    ...gameRequest,
    proposedDatetime: gameRequest.proposedDatetime.toISOString(),
    durationMinutes: gameRequest.durationMinutes ?? null,
    outcomeUpdatedAt: gameRequest.outcomeUpdatedAt?.toISOString() ?? null,
    report: serializeGameReport(gameRequest.report)
  };
}

export function serializePersonalActivity(
  activity: PersonalActivity & {
    court?: Court | null;
    photos?: PersonalActivityPhoto[];
  }
) {
  return {
    id: activity.id,
    userId: activity.userId,
    courtId: activity.courtId,
    sport: activity.sport,
    scheduledAt: activity.scheduledAt.toISOString(),
    durationMinutes: activity.durationMinutes ?? null,
    comment: activity.comment ?? null,
    status: activity.status,
    reportComment: activity.reportComment ?? null,
    createdAt: activity.createdAt.toISOString(),
    updatedAt: activity.updatedAt.toISOString(),
    court: activity.court ? serializeCourt(activity.court) : null,
    photos:
      activity.photos
        ?.slice()
        .sort((left, right) => left.position - right.position)
        .map((photo) => ({
          id: photo.id,
          url: photo.url,
          position: photo.position
        })) ?? []
  };
}

export function otherUserFromMatch(match: Match & { user1: User; user2: User }, currentUserId: string) {
  return match.user1Id === currentUserId ? match.user2 : match.user1;
}
