import type { Sport } from "@prisma/client";

import { SPORT_OPTIONS } from "@/lib/constants";

export function normalizeCourtSports(value: unknown): Sport[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(
    (sport): sport is Sport => typeof sport === "string" && SPORT_OPTIONS.includes(sport as Sport)
  );
}

export function courtSupportsSport(value: unknown, sport?: Sport | null) {
  if (!sport) {
    return true;
  }

  return normalizeCourtSports(value).includes(sport);
}

export function getPrimaryCourtSport(value: unknown) {
  return normalizeCourtSports(value)[0] ?? null;
}
