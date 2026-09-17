import type {
  Court,
  CourtMetro,
  GeoPlace,
  GameReport,
  GameReportConfirmation,
  GameReportPhoto,
  GameRequest,
  Match,
  Metro,
  PersonalActivity,
  PersonalActivityPhoto,
  ServiceArea,
  User,
  UserCourt
} from "@prisma/client";

import { getDistrictLabel } from "@/lib/constants";
import { publicPlayerMapAreas } from "@/lib/player-map-areas";
import { DEFAULT_LOCALE, type SupportedLocale } from "@/lib/locales";
import { formatDistanceKm } from "@/lib/utils";
import { emptyCoverage, serializeLocationRelation } from "@/server/locations";
import type { NearbyMetadata } from "@/lib/nearby";

export function serializeMe<
  T extends {
    localeOverride?: string | null;
    showOnMap?: boolean;
    location?: Parameters<typeof serializeLocationRelation>[0];
  }
>(user: T, requestLocale: SupportedLocale = DEFAULT_LOCALE) {
  const { location, ...legacyUser } = user;
  const serializedLocation = serializeLocationRelation(location);
  const localeOverride = user.localeOverride === "en" || user.localeOverride === "ru" ? user.localeOverride : null;
  return {
    ...legacyUser,
    showOnMap: user.showOnMap === true,
    localeOverride,
    effectiveLocale: localeOverride ?? requestLocale,
    location: serializedLocation,
    coverage: serializedLocation?.coverage ?? emptyCoverage()
  };
}

type PreviewUserInput = Partial<User> & {
    location?: (GeoPlace & { serviceArea: ServiceArea | null }) | null;
    distanceKm?: number | null;
    nearby?: NearbyMetadata;
    score?: number | null;
    explainabilityReasons?: string[] | null;
  };

export function serializeUserPreview(user: PreviewUserInput) {
  return {
    ...serializeUserPreviewFields(user),
    gameSearches: "gameSearches" in user ? serializePreviewGameSearches((user as PreviewUserInput & { gameSearches?: unknown }).gameSearches) : undefined
  };
}

function serializeUserPreviewFields(user: PreviewUserInput) {
  return {
    id: user.id,
    showOnMap: user.showOnMap === true,
    mapAreas: publicPlayerMapAreas(user),
    name: user.name,
    age: user.age,
    city: user.city,
    locationPlaceId: user.locationPlaceId,
    location: "location" in user ? serializeLocationRelation(user.location) : null,
    coverage:
      "location" in user
        ? serializeLocationRelation(user.location)?.coverage ?? emptyCoverage()
        : emptyCoverage(),
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
    distanceKm: user.distanceKm ?? null,
    ...(user.nearby ? { nearby: user.nearby } : {}),
    distanceLabel: formatDistanceKm(user.distanceKm),
    score: user.score ?? null,
    explainabilityReasons: user.explainabilityReasons ?? []
  };
}

export function serializeCourt(
  court: Court & {
    distanceKm?: number | null;
    nearby?: NearbyMetadata;
    nearestMetro?: Metro | null;
    metroLinks?: Array<CourtMetro & { metro: Metro }>;
    members?: Array<UserCourt & { user: User }>;
    _count?: { members?: number };
    isMember?: boolean;
    activeSearchesCount?: number;
    activeSearchPlayersCount?: number;
    activeSearchPreviewUsers?: ReturnType<typeof serializeUserPreview>[];
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
    members: court.members?.map((member) => serializeUserPreview(member.user)) ?? [],
    activeSearchesCount: court.activeSearchesCount ?? 0,
    activeSearchPlayersCount: court.activeSearchPlayersCount ?? 0,
    activeSearchPreviewUsers: court.activeSearchPreviewUsers ?? []
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
  return serializeUserPreview(match.user1Id === currentUserId ? match.user2 : match.user1);
}

// Related users never inherit relation graphs or private fields from a raw
// Prisma include. Each relation below terminates at the public user projection.
function record(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function pickPublic(value: Record<string, unknown>, keys: readonly string[]) {
  return Object.fromEntries(keys.filter((key) => key in value).map((key) => [key, value[key]]));
}

function publicRelatedUser(value: unknown) {
  const user = record(value);
  return user ? serializeUserPreviewFields(user as PreviewUserInput) : null;
}

function publicRelatedCourt(value: unknown) {
  const court = record(value);
  return court ? pickPublic(court, ["id", "name", "address", "city", "district", "nearestMetroId", "locationLat", "locationLng",
    "surface", "setting", "status", "supportedSports", "phone", "workingHours", "yandexMapsUrl", "websiteUrl", "about",
    "amenities", "messengerType", "messengerUrl", "photoUrl", "photoUrls", "priceRange", "rating", "bookingUrl"]) : null;
}

function serializePreviewGameSearches(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    const search = record(entry);
    if (!search) return [];
    const pair = record(search.regularPair);
    return [{
      ...pickPublic(search, ["id", "inviteSlug", "createdByUserId", "locationPlaceId", "locationCountryCode", "locationCity",
        "preferredCourtId", "customVenueTitle", "customVenueAddress", "runningRoute", "runningRoutePoints", "preferredDistricts",
        "scheduledCourtId", "preferredDays", "preferredTimeRanges", "searchType", "hotWindow", "hotStartsAt", "durationMinutes",
        "scheduledAt", "scheduledDurationMinutes", "hasCourtBooked", "sport", "selfLevel", "selfLevelUnknown", "desiredLevelMin",
        "desiredLevelMax", "format", "playersNeeded", "comment", "status", "isActive", "createdAt", "updatedAt"]),
      preferredCourt: publicRelatedCourt(search.preferredCourt),
      scheduledCourt: publicRelatedCourt(search.scheduledCourt),
      createdByUser: publicRelatedUser(search.createdByUser),
      regularPair: pair ? {
        ...pickPublic(pair, ["id", "gameSearchId", "matchId", "createdByUserId", "partnerUserId", "preferredCourtId", "sport", "format",
          "preferredDays", "preferredTimeRanges", "comment", "status", "createdAt", "updatedAt"]),
        preferredCourt: publicRelatedCourt(pair.preferredCourt),
        partnerUser: publicRelatedUser(pair.partnerUser),
        createdByUser: publicRelatedUser(pair.createdByUser)
      } : null,
      responses: Array.isArray(search.responses) ? search.responses.flatMap((entry) => {
        const response = record(entry);
        return response ? [{
          ...pickPublic(response, ["id", "gameSearchId", "responderUserId", "message", "status", "createdAt", "updatedAt"]),
          responderUser: publicRelatedUser(response.responderUser)
        }] : [];
      }) : []
    }];
  });
}
