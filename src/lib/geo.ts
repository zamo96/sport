import { CITY_PRESETS, DISTRICT_MAP_AREAS, type DistrictOption } from "@/lib/constants";

export type Coordinates = { lat: number; lng: number };

export interface GeoProvider {
  resolveCity(city: string): Promise<Coordinates | null>;
}

class StaticGeoProvider implements GeoProvider {
  async resolveCity(city: string) {
    const normalized = city.trim().toLowerCase();
    const entry = Object.entries(CITY_PRESETS).find(([key]) => key.toLowerCase() === normalized);
    return entry?.[1] ?? null;
  }
}

const provider: GeoProvider = new StaticGeoProvider();

export async function resolveLocationFromCity(city: string | null | undefined) {
  if (!city) {
    return null;
  }

  return provider.resolveCity(city.trim());
}

export function resolveLocationFromDistrict(district: string | null | undefined) {
  if (!district) {
    return null;
  }

  return DISTRICT_MAP_AREAS[district as DistrictOption]?.center ?? null;
}

export function haversineDistanceKm(
  first: Coordinates | null | undefined,
  second: Coordinates | null | undefined
) {
  if (!first || !second) {
    return null;
  }

  const earthRadius = 6371;
  const dLat = degToRad(second.lat - first.lat);
  const dLng = degToRad(second.lng - first.lng);
  const lat1 = degToRad(first.lat);
  const lat2 = degToRad(second.lat);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return earthRadius * c;
}

function degToRad(value: number) {
  return value * (Math.PI / 180);
}
