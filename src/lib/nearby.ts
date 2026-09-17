import type { Coordinates } from "@/lib/geo";

export type NearbyMetadata = { originCity: string; radiusKm: number; distanceKm: number };
export const NEARBY_MAX_RADIUS_KM = 200;

export function validCoordinates(value: Coordinates | null | undefined): value is Coordinates {
  return Boolean(value && Number.isFinite(value.lat) && Number.isFinite(value.lng) &&
    Math.abs(value.lat) <= 90 && Math.abs(value.lng) <= 180);
}

/** An explicit radius is the starting point, never silently reduced. */
export function nearbyRadiusStages(initialRadius?: number) {
  const initial = Number.isFinite(initialRadius) && initialRadius! > 0
    ? Math.min(initialRadius!, NEARBY_MAX_RADIUS_KM) : 25;
  return Array.from(new Set([initial, 25, 50, 100, 200].filter((radius) => radius >= initial)))
    .sort((left, right) => left - right);
}

export function selectNearby<T extends { id: string; distanceKm: number | null }>(
  candidates: T[], originCity: string, limit: number, initialRadius?: number,
  tieBreak: (left: T, right: T) => number = () => 0
): Array<T & { nearby: NearbyMetadata }> {
  const measured = candidates.filter((candidate) => candidate.distanceKm != null &&
    Number.isFinite(candidate.distanceKm) && candidate.distanceKm >= 0);
  for (const radiusKm of nearbyRadiusStages(initialRadius)) {
    const within = measured.filter((candidate) => candidate.distanceKm! <= radiusKm);
    if (within.length === 0) continue;
    return within.sort((left, right) => left.distanceKm! - right.distanceKm! ||
      tieBreak(left, right) || left.id.localeCompare(right.id))
      .slice(0, limit)
      .map((candidate) => ({ ...candidate, nearby: { originCity, radiusKm, distanceKm: candidate.distanceKm! } }));
  }
  return [];
}
