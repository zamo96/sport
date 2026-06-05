import { Gender, PlayFormat, Sport, Surface, type User } from "@prisma/client";

import { SPORT_LABELS } from "@/lib/constants";
import { haversineDistanceKm } from "@/lib/geo";
import { getSharedSports, getSportLevel, normalizeSports } from "@/lib/sport-levels";

export type CandidateUser = Pick<
  User,
  | "id"
  | "name"
  | "age"
  | "gender"
  | "city"
  | "bio"
  | "avatarUrl"
  | "homeLat"
  | "homeLng"
  | "tennisLevel"
  | "preferredSports"
  | "sportLevels"
  | "preferredPlayFormat"
  | "preferredSurface"
  | "availableDays"
  | "availableTimeRanges"
  | "availableTimeSlots"
  | "searchRadiusKm"
  | "isLookingForGame"
> & {
  district?: User["district"] | null;
  preferredDistricts?: User["preferredDistricts"] | null;
};

export type DiscoverFilters = {
  levelMin?: number;
  levelMax?: number;
  distanceKm?: number;
  city?: string;
  gender?: Gender[];
  sport?: Sport[];
  format?: PlayFormat[];
  surface?: Surface[];
  day?: string[];
  timeRange?: string[];
  view?: "upcoming" | "swipe" | "likes" | "seeking" | "hot";
};

export type ScoredCandidate = CandidateUser & {
  score: number;
  distanceKm: number | null;
  sportsOverlapCount: number;
  dayOverlapCount: number;
  timeOverlapCount: number;
};

function isSport(value: unknown): value is Sport {
  return (
    typeof value === "string" &&
    Object.prototype.hasOwnProperty.call(SPORT_LABELS, value)
  );
}

function resolveExplainabilitySport(
  sharedSports: Sport[],
  candidate: unknown,
  filters: DiscoverFilters
) {
  const primarySearchSport =
    filters.view === "seeking" || filters.view === "hot"
      ? (() => {
          if (!candidate || typeof candidate !== "object") {
            return null;
          }

          const gameSearches = (candidate as { gameSearches?: unknown }).gameSearches;
          if (!Array.isArray(gameSearches)) {
            return null;
          }

          const sport = (gameSearches[0] as { sport?: unknown } | undefined)?.sport;
          return isSport(sport) ? sport : null;
        })()
      : null;

  if (primarySearchSport && sharedSports.includes(primarySearchSport)) {
    return primarySearchSport;
  }

  return sharedSports[0] ?? "tennis";
}

function formatExplainabilityDistance(distanceKm: number) {
  if (distanceKm < 1) {
    return `${Math.round(distanceKm * 1000)} м`;
  }

  return `${distanceKm.toFixed(1)} км`;
}

function resolveUserDistricts(preferredDistricts: unknown, district?: string | null) {
  const preferred = parseStringArray(preferredDistricts);
  if (preferred.length > 0) {
    return preferred;
  }

  return district ? [district] : [];
}

export function buildDiscoverExplainabilityReasons<T extends CandidateUser>(
  viewer: CandidateUser,
  candidate: T & { distanceKm?: number | null; gameSearches?: unknown },
  filters: DiscoverFilters = {}
): string[] {
  const viewerSports = normalizeSports(viewer.preferredSports);
  const candidateSports = normalizeSports(candidate.preferredSports);
  const sharedSports = getSharedSports(viewerSports, candidateSports, filters.sport);
  const sport = resolveExplainabilitySport(sharedSports, candidate, filters);
  const reasons: string[] = [`Совпадает спорт: ${SPORT_LABELS[sport] ?? sport}`];

  const viewerLevel = getSportLevel(viewer.sportLevels, sport, viewer.tennisLevel ?? 5);
  const candidateLevel = getSportLevel(candidate.sportLevels, sport, candidate.tennisLevel ?? 5);
  const minLevel = Math.min(viewerLevel, candidateLevel);
  const maxLevel = Math.max(viewerLevel, candidateLevel);
  reasons.push(`Уровень рядом: ${minLevel === maxLevel ? `${minLevel}` : `${minLevel}–${maxLevel}`}`);

  const viewerDistricts = resolveUserDistricts(viewer.preferredDistricts, viewer.district);
  const candidateDistricts = resolveUserDistricts(candidate.preferredDistricts, candidate.district);
  const districtOverlapCount = viewerDistricts.filter((district) => candidateDistricts.includes(district)).length;
  const computedDistanceKm =
    typeof candidate.distanceKm === "number"
      ? candidate.distanceKm
      : haversineDistanceKm(
          viewer.homeLat != null && viewer.homeLng != null ? { lat: viewer.homeLat, lng: viewer.homeLng } : null,
          candidate.homeLat != null && candidate.homeLng != null ? { lat: candidate.homeLat, lng: candidate.homeLng } : null
        );

  if (computedDistanceKm != null && !Number.isNaN(computedDistanceKm)) {
    reasons.push(`Недалеко: ${formatExplainabilityDistance(computedDistanceKm)}`);
  } else if (districtOverlapCount > 0) {
    reasons.push("Рядом по району");
  }

  const dayOverlapCount = overlapStrings(viewer.availableDays, candidate.availableDays);
  const timeOverlapCount = overlapStrings(viewer.availableTimeRanges, candidate.availableTimeRanges);
  if (dayOverlapCount > 0 || timeOverlapCount > 0) {
    reasons.push("Пересекается расписание");
  }

  return reasons.slice(0, 4);
}

export function scoreCandidates<T extends CandidateUser>(
  viewer: CandidateUser,
  candidates: T[],
  filters: DiscoverFilters = {}
) {
  return candidates
    .map((candidate) => scoreCandidate(viewer, candidate, filters))
    .filter((candidate): candidate is T & ScoredCandidate => candidate !== null)
    .sort((left, right) => right.score - left.score || (left.distanceKm ?? 999) - (right.distanceKm ?? 999));
}

export function scoreCandidate<T extends CandidateUser>(
  viewer: CandidateUser,
  candidate: T,
  filters: DiscoverFilters = {}
) {
  const viewerSports = normalizeSports(viewer.preferredSports);
  const candidateSports = normalizeSports(candidate.preferredSports);
  const relevantSports = getSharedSports(viewerSports, candidateSports, filters.sport);
  const distanceKm = haversineDistanceKm(
    viewer.homeLat != null && viewer.homeLng != null ? { lat: viewer.homeLat, lng: viewer.homeLng } : null,
    candidate.homeLat != null && candidate.homeLng != null ? { lat: candidate.homeLat, lng: candidate.homeLng } : null
  );

  if (relevantSports.length === 0) {
    return null;
  }

  const sportsAfterLevelFilter =
    filters.levelMin || filters.levelMax
      ? relevantSports.filter((sport) => {
          const level = getSportLevel(candidate.sportLevels, sport, candidate.tennisLevel ?? 5);

          if (filters.levelMin && level < filters.levelMin) {
            return false;
          }

          if (filters.levelMax && level > filters.levelMax) {
            return false;
          }

          return true;
        })
      : relevantSports;

  if (sportsAfterLevelFilter.length === 0) {
    return null;
  }

  if (filters.distanceKm && distanceKm != null && distanceKm > filters.distanceKm) {
    return null;
  }

  if (
    filters.city &&
    candidate.city &&
    candidate.city.trim().toLowerCase() !== filters.city.trim().toLowerCase()
  ) {
    return null;
  }

  if (filters.city && !candidate.city) {
    return null;
  }

  if (filters.gender && filters.gender.length > 0 && (!candidate.gender || !filters.gender.includes(candidate.gender))) {
    return null;
  }

  if (
    filters.format &&
    filters.format.length > 0 &&
    !filters.format.includes(candidate.preferredPlayFormat)
  ) {
    return null;
  }

  if (
    filters.surface &&
    filters.surface.length > 0 &&
    !filters.surface.includes(candidate.preferredSurface)
  ) {
    return null;
  }

  const candidateDays = parseStringArray(candidate.availableDays);
  const candidateTimeRanges = parseStringArray(candidate.availableTimeRanges);

  if (filters.day && filters.day.length > 0 && !filters.day.some((day) => candidateDays.includes(day))) {
    return null;
  }

  if (
    filters.timeRange &&
    filters.timeRange.length > 0 &&
    !filters.timeRange.some((timeRange) => candidateTimeRanges.includes(timeRange))
  ) {
    return null;
  }

  const sportsOverlapCount = relevantSports.length;
  const levelGap = Math.min(
    ...sportsAfterLevelFilter.map((sport) =>
      Math.abs(
        getSportLevel(viewer.sportLevels, sport, viewer.tennisLevel ?? 5) -
          getSportLevel(candidate.sportLevels, sport, candidate.tennisLevel ?? 5)
      )
    )
  );

  const formatScore = formatCompatible(viewer.preferredPlayFormat, candidate.preferredPlayFormat) ? 22 : 0;
  const surfaceScore = surfaceCompatible(viewer.preferredSurface, candidate.preferredSurface) ? 18 : 0;
  const sportScore = Math.min(24, sportsOverlapCount * 12);
  const levelScore = Math.max(0, 28 - levelGap * 7);
  const viewerDistricts = resolveUserDistricts(viewer.preferredDistricts, viewer.district);
  const candidateDistricts = resolveUserDistricts(candidate.preferredDistricts, candidate.district);
  const districtOverlapCount = viewerDistricts.filter((district) => candidateDistricts.includes(district)).length;
  const hasDistrictPreference = viewerDistricts.length > 0 || candidateDistricts.length > 0;
  const distanceScore =
    districtOverlapCount > 0
      ? 28 + Math.min(6, districtOverlapCount * 2)
      : hasDistrictPreference
        ? distanceKm == null
          ? 4
          : Math.max(1, 6 - Math.min(distanceKm, 25) / 6)
        : distanceKm == null
          ? 8
          : Math.max(2, 12 - Math.min(distanceKm, 25) / 3);
  const dayOverlapCount = overlapStrings(viewer.availableDays, candidate.availableDays);
  const timeOverlapCount = overlapStrings(viewer.availableTimeRanges, candidate.availableTimeRanges);
  const availabilityScore = Math.min(12, dayOverlapCount * 2 + timeOverlapCount * 4);
  const seekingBoost = candidate.isLookingForGame ? 8 : 0;

  return {
    ...candidate,
    distanceKm,
    sportsOverlapCount,
    dayOverlapCount,
    timeOverlapCount,
    score: sportScore + formatScore + surfaceScore + levelScore + distanceScore + availabilityScore + seekingBoost
  };
}

export function overlapSlots(left: unknown, right: unknown) {
  return overlapStrings(left, right);
}

export function parseStringArray(value: unknown) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((slot): slot is string => typeof slot === "string");
}

export function parseSlots(value: unknown) {
  return parseStringArray(value);
}

export function parseSports(value: unknown) {
  return normalizeSports(value);
}

export function overlapStrings(left: unknown, right: unknown) {
  const leftSlots = parseStringArray(left);
  const rightSlots = parseStringArray(right);

  return leftSlots.filter((slot) => rightSlots.includes(slot)).length;
}

export function formatCompatible(first: PlayFormat, second: PlayFormat) {
  return first === "both" || second === "both" || first === second;
}

export function surfaceCompatible(first: Surface, second: Surface) {
  return first === "any" || second === "any" || first === second;
}
