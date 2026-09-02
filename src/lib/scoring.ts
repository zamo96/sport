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
  locationPlaceId?: User["locationPlaceId"] | null;
  district?: User["district"] | null;
  preferredDistricts?: User["preferredDistricts"] | null;
  lastActiveAt?: User["lastActiveAt"] | null;
  createdAt?: User["createdAt"] | null;
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
  exactTimeSlotOverlapCount: number;
  ageGap: number | null;
  /** Игрок из другого города, показан из-за нехватки кандидатов рядом. */
  isNearbyFallback?: boolean;
};

export type ScoringOptions = {
  /**
   * Пускать игроков из других городов, если они ближе этого расстояния.
   * Нужно для холодного старта: в городе с полутора десятками профилей
   * изоляция по городу оставляет человека перед пустым экраном.
   */
  nearbyRadiusKm?: number;
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

const CITY_ALIASES: Record<string, string> = {
  "санкт-петербург": "saint-petersburg",
  "санкт петербург": "saint-petersburg",
  петербург: "saint-petersburg",
  спб: "saint-petersburg",
  "saint petersburg": "saint-petersburg",
  "st. petersburg": "saint-petersburg",
  "st petersburg": "saint-petersburg",
  москва: "moscow",
  moscow: "moscow",
  казань: "kazan",
  kazan: "kazan"
};

function canonicalCity(value?: string | null) {
  const normalized = value?.trim().toLowerCase().replace(/\s+/g, " ") ?? "";
  return CITY_ALIASES[normalized] ?? normalized;
}

function isSameCanonicalCity(left?: string | null, right?: string | null) {
  const leftCity = canonicalCity(left);
  return leftCity.length > 0 && leftCity === canonicalCity(right);
}

function isSameLocation(left: CandidateUser, right: CandidateUser) {
  return isLocationIdentityCompatible(left.city, left.locationPlaceId, right.city, right.locationPlaceId);
}

function isLocationIdentityCompatible(
  leftCity?: string | null,
  leftLocationPlaceId?: string | null,
  rightCity?: string | null,
  rightLocationPlaceId?: string | null
) {
  if (leftLocationPlaceId && rightLocationPlaceId) return leftLocationPlaceId === rightLocationPlaceId;
  if (leftLocationPlaceId || rightLocationPlaceId) {
    const trustedLegacyId = leftLocationPlaceId ?? rightLocationPlaceId;
    const cityWithoutId = leftLocationPlaceId ? rightCity : leftCity;
    const legacyCityById: Record<string, string> = {
      "legacy:ru:saint-petersburg": "saint-petersburg",
      "legacy:ru:moscow": "moscow",
      "legacy:ru:kazan": "kazan"
    };
    return Boolean(trustedLegacyId && legacyCityById[trustedLegacyId] === canonicalCity(cityWithoutId));
  }
  return isSameCanonicalCity(leftCity, rightCity);
}

function isCityEligible(
  viewerCity: string | null | undefined,
  candidateCity: string | null | undefined,
  filters: DiscoverFilters,
  viewerLocationPlaceId?: string | null,
  candidateLocationPlaceId?: string | null
) {
  const candidateCanonicalCity = canonicalCity(candidateCity);

  if (filters.city) {
    const filterCanonicalCity = canonicalCity(filters.city);
    if (!filterCanonicalCity || candidateCanonicalCity !== filterCanonicalCity) {
      return false;
    }
  }

  const isolatesViewerCity =
    filters.view == null ||
    filters.view === "swipe" ||
    filters.view === "hot" ||
    filters.view === "seeking";
  const viewerCanonicalCity = canonicalCity(viewerCity);

  if (!isolatesViewerCity) return true;
  if (viewerLocationPlaceId || candidateLocationPlaceId) {
    return isLocationIdentityCompatible(viewerCity, viewerLocationPlaceId, candidateCity, candidateLocationPlaceId);
  }
  return !viewerCanonicalCity || candidateCanonicalCity === viewerCanonicalCity;
}

function ageCompatibilityScore(viewerAge?: number | null, candidateAge?: number | null) {
  if (typeof viewerAge !== "number" || typeof candidateAge !== "number") {
    return { score: 3, gap: null };
  }

  const gap = Math.abs(viewerAge - candidateAge);

  if (gap <= 5) {
    return { score: 10, gap };
  }

  if (gap <= 10) {
    return { score: 7, gap };
  }

  if (gap <= 15) {
    return { score: 4, gap };
  }

  return { score: 1, gap };
}

function cityCompatibilityScore(
  viewerCity?: string | null,
  candidateCity?: string | null,
  viewerLocationPlaceId?: string | null,
  candidateLocationPlaceId?: string | null
) {
  if (viewerLocationPlaceId || candidateLocationPlaceId) {
    return isLocationIdentityCompatible(viewerCity, viewerLocationPlaceId, candidateCity, candidateLocationPlaceId) ? 10 : -18;
  }
  const viewerNormalizedCity = canonicalCity(viewerCity);
  const candidateNormalizedCity = canonicalCity(candidateCity);

  if (!viewerNormalizedCity || !candidateNormalizedCity) {
    return 2;
  }

  return viewerNormalizedCity === candidateNormalizedCity ? 10 : -18;
}

function availabilityCompatibilityScore(viewer: CandidateUser, candidate: CandidateUser) {
  const exactTimeSlotOverlapCount = overlapStrings(viewer.availableTimeSlots, candidate.availableTimeSlots);
  const dayOverlapCount = overlapStrings(viewer.availableDays, candidate.availableDays);
  const timeOverlapCount = overlapStrings(viewer.availableTimeRanges, candidate.availableTimeRanges);
  const viewerHasExactSlots = parseStringArray(viewer.availableTimeSlots).length > 0;
  const candidateHasExactSlots = parseStringArray(candidate.availableTimeSlots).length > 0;

  if (viewerHasExactSlots && candidateHasExactSlots) {
    return {
      exactTimeSlotOverlapCount,
      dayOverlapCount,
      timeOverlapCount,
      score: Math.min(20, exactTimeSlotOverlapCount * 10 + dayOverlapCount * 2 + timeOverlapCount)
    };
  }

  return {
    exactTimeSlotOverlapCount,
    dayOverlapCount,
    timeOverlapCount,
    score: Math.min(14, dayOverlapCount * 3 + timeOverlapCount * 4)
  };
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

  const sameCity = isSameLocation(viewer, candidate);
  const viewerDistricts = sameCity ? resolveUserDistricts(viewer.preferredDistricts, viewer.district) : [];
  const candidateDistricts = sameCity ? resolveUserDistricts(candidate.preferredDistricts, candidate.district) : [];
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
  filters: DiscoverFilters = {},
  options: ScoringOptions = {}
) {
  return candidates
    .map((candidate) => scoreCandidate(viewer, candidate, filters, options))
    .filter((candidate): candidate is T & ScoredCandidate => candidate !== null)
    .sort((left, right) => right.score - left.score || (left.distanceKm ?? 999) - (right.distanceKm ?? 999));
}

export function scoreCandidate<T extends CandidateUser>(
  viewer: CandidateUser,
  candidate: T,
  filters: DiscoverFilters = {},
  options: ScoringOptions = {}
) {
  const distanceKm = haversineDistanceKm(
    viewer.homeLat != null && viewer.homeLng != null ? { lat: viewer.homeLat, lng: viewer.homeLng } : null,
    candidate.homeLat != null && candidate.homeLng != null ? { lat: candidate.homeLat, lng: candidate.homeLng } : null
  );
  const cityEligible = isCityEligible(
    viewer.city,
    candidate.city,
    filters,
    viewer.locationPlaceId,
    candidate.locationPlaceId
  );
  // Явный фильтр по городу не ослабляем: человек выбрал его сам.
  const isNearbyFallback =
    !cityEligible &&
    !filters.city &&
    options.nearbyRadiusKm != null &&
    distanceKm != null &&
    distanceKm <= options.nearbyRadiusKm;

  if (!cityEligible && !isNearbyFallback) {
    return null;
  }

  const viewerSports = normalizeSports(viewer.preferredSports);
  const candidateSports = normalizeSports(candidate.preferredSports);
  const relevantSports = getSharedSports(viewerSports, candidateSports, filters.sport);

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
  const { score: ageScore, gap: ageGap } = ageCompatibilityScore(viewer.age, candidate.age);
  const cityScore = cityCompatibilityScore(viewer.city, candidate.city, viewer.locationPlaceId, candidate.locationPlaceId);
  const sameCity = isSameLocation(viewer, candidate);
  const viewerDistricts = sameCity ? resolveUserDistricts(viewer.preferredDistricts, viewer.district) : [];
  const candidateDistricts = sameCity ? resolveUserDistricts(candidate.preferredDistricts, candidate.district) : [];
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
  const availability = availabilityCompatibilityScore(viewer, candidate);
  const seekingBoost = candidate.isLookingForGame ? 8 : 0;

  return {
    ...candidate,
    distanceKm,
    ...(isNearbyFallback ? { isNearbyFallback: true } : {}),
    sportsOverlapCount,
    dayOverlapCount: availability.dayOverlapCount,
    timeOverlapCount: availability.timeOverlapCount,
    exactTimeSlotOverlapCount: availability.exactTimeSlotOverlapCount,
    ageGap,
    score:
      sportScore +
      formatScore +
      surfaceScore +
      levelScore +
      ageScore +
      cityScore +
      distanceScore +
      availability.score +
      seekingBoost
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
