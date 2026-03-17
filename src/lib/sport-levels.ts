import { type Sport } from "@prisma/client";

import { SPORT_OPTIONS } from "@/lib/constants";

export type SportLevels = Partial<Record<Sport, number>>;

const DEFAULT_SPORT_LEVEL = 5;

export function normalizeSports(value: unknown): Sport[] {
  if (!Array.isArray(value)) {
    return ["tennis"];
  }

  const sports = value.filter((sport): sport is Sport =>
    typeof sport === "string" && SPORT_OPTIONS.includes(sport as Sport)
  );

  return sports.length > 0 ? sports : ["tennis"];
}

export function normalizeSportLevels(
  value: unknown,
  preferredSports: unknown,
  fallbackLevel = DEFAULT_SPORT_LEVEL
) {
  const sports = normalizeSports(preferredSports);
  const source =
    value && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  const normalized: SportLevels = {};

  for (const sport of sports) {
    const rawLevel = source[sport];
    const parsedLevel =
      typeof rawLevel === "number" && Number.isInteger(rawLevel) && rawLevel >= 1 && rawLevel <= 10
        ? rawLevel
        : sport === "tennis" && fallbackLevel >= 1 && fallbackLevel <= 10
          ? fallbackLevel
          : DEFAULT_SPORT_LEVEL;

    normalized[sport] = parsedLevel;
  }

  return normalized;
}

export function syncSportLevels(preferredSports: Sport[], currentLevels: unknown, fallbackLevel = DEFAULT_SPORT_LEVEL) {
  if (preferredSports.length === 0) {
    return {};
  }

  return normalizeSportLevels(currentLevels, preferredSports, fallbackLevel);
}

export function getSportLevel(
  sportLevels: unknown,
  sport: Sport,
  fallbackLevel = DEFAULT_SPORT_LEVEL
) {
  const levels = normalizeSportLevels(sportLevels, [sport], fallbackLevel);
  return levels[sport] ?? fallbackLevel;
}

export function getSportLevelEntries(
  preferredSports: unknown,
  sportLevels: unknown,
  fallbackLevel = DEFAULT_SPORT_LEVEL
) {
  const sports = normalizeSports(preferredSports);
  const levels = normalizeSportLevels(sportLevels, sports, fallbackLevel);

  return sports.map((sport) => ({
    sport,
    level: levels[sport] ?? fallbackLevel
  }));
}

export function getPrimarySport(preferredSports: unknown) {
  return normalizeSports(preferredSports)[0] ?? "tennis";
}

export function getPrimarySportLevel(
  preferredSports: unknown,
  sportLevels: unknown,
  fallbackLevel = DEFAULT_SPORT_LEVEL
) {
  const primarySport = getPrimarySport(preferredSports);

  return getSportLevel(sportLevels, primarySport, fallbackLevel);
}

export function getSharedSports(
  leftSports: unknown,
  rightSports: unknown,
  restrictedSports?: Sport[]
) {
  const left = normalizeSports(leftSports);
  const right = normalizeSports(rightSports);
  const shared = left.filter((sport) => right.includes(sport));

  if (!restrictedSports || restrictedSports.length === 0) {
    return shared;
  }

  return shared.filter((sport) => restrictedSports.includes(sport));
}

export function hasExplicitSportProfile(preferredSports: unknown, sportLevels: unknown, sport: Sport) {
  const sports = Array.isArray(preferredSports)
    ? preferredSports.filter((item): item is Sport => typeof item === "string" && SPORT_OPTIONS.includes(item as Sport))
    : [];
  const levels =
    sportLevels && typeof sportLevels === "object" && !Array.isArray(sportLevels)
      ? (sportLevels as Record<string, unknown>)
      : {};
  const rawLevel = levels[sport];

  return sports.includes(sport) && typeof rawLevel === "number" && Number.isInteger(rawLevel) && rawLevel >= 1 && rawLevel <= 10;
}
