import { cities, type WorldCitiesJsonRow } from "world-cities-json";

import russianCityNames from "@/server/data/simplemaps-ru-names.json";

export type CatalogCity = {
  id: string;
  city: string;
  cityAscii: string;
  country: string;
  countryCode: string;
  region: string | null;
  latitude: number;
  longitude: number;
  population: number;
};

let rowsByCountry: ReadonlyMap<string, readonly WorldCitiesJsonRow[]> | undefined;
const RUSSIAN_CITY_NAMES = russianCityNames as Record<string, string>;
const RUSSIAN_CITY_SEARCH_ALIASES: Readonly<Record<string, readonly string[]>> = {
  "1643013518": ["Rostov-on-Don", "Rostov on Don"],
  "1643640451": ["Kamensk-Uralsky", "Kamensk-Uralskiy", "Kamensk Uralsky", "Kamensk Uralskiy"]
};

export function catalogCountries() {
  const index = getCatalogIndex();
  return Array.from(index, ([countryCode, countryRows]) => ({
    countryCode,
    cityCount: countryRows.length
  }));
}

export function catalogCitiesForCountry(countryCode: string) {
  return (getCatalogIndex().get(countryCode.toUpperCase()) ?? []).flatMap((row) => {
    const city = parseRow(row);
    return city ? [city] : [];
  });
}

export function searchCatalogCities(countryCode: string, query: string, limit: number) {
  const normalizedQuery = normalizeCatalogText(query);
  const countryRows = getCatalogIndex().get(countryCode.toUpperCase()) ?? [];
  if (!normalizedQuery) return countryRows.slice(0, limit).flatMap((row) => {
    const city = parseRow(row);
    return city ? [city] : [];
  });

  return countryRows
    .flatMap((row) => {
      const names = [
        localizedCityName(row),
        row.city,
        row.city_ascii,
        ...(RUSSIAN_CITY_SEARCH_ALIASES[row.id] ?? [])
      ].map(normalizeCatalogText);
      const exact = names.some((name) => name === normalizedQuery);
      const prefix = names.some((name) => name.startsWith(normalizedQuery));
      const contains = names.some((name) => name.includes(normalizedQuery));
      return contains ? [{ row, matchRank: exact ? 0 : prefix ? 1 : 2 }] : [];
    })
    .sort((left, right) =>
      left.matchRank - right.matchRank ||
      population(right.row) - population(left.row) ||
      left.row.id.localeCompare(right.row.id)
    )
    .slice(0, limit)
    .flatMap(({ row }) => {
      const city = parseRow(row);
      return city ? [city] : [];
    });
}

export function normalizeCatalogText(value: string) {
  return value
    .trim()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("en-US")
    .replace(/ё/g, "е")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function getCatalogIndex() {
  if (rowsByCountry) return rowsByCountry;

  const mutableIndex = new Map<string, WorldCitiesJsonRow[]>();
  for (const row of cities) {
    if (!parseRow(row)) continue;
    const countryCode = row.iso2.trim().toUpperCase();
    const countryRows = mutableIndex.get(countryCode) ?? [];
    countryRows.push(row);
    mutableIndex.set(countryCode, countryRows);
  }
  for (const countryRows of mutableIndex.values()) {
    countryRows.sort((left, right) => population(right) - population(left) || left.id.localeCompare(right.id));
  }
  rowsByCountry = mutableIndex;
  return rowsByCountry;
}

function population(row: WorldCitiesJsonRow) {
  return Number(row.population) || 0;
}

function parseRow(row: WorldCitiesJsonRow): CatalogCity | null {
  const latitude = Number(row.lat);
  const longitude = Number(row.lng);
  const population = Number(row.population) || 0;
  const countryCode = row.iso2.trim().toUpperCase();
  if (!row.id || !row.city || !countryCode || !Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  return {
    id: row.id,
    city: localizedCityName(row),
    cityAscii: row.city_ascii || row.city,
    country: row.country,
    countryCode,
    region: row.admin_name || null,
    latitude,
    longitude,
    population
  };
}

function localizedCityName(row: WorldCitiesJsonRow) {
  return row.iso2.toUpperCase() === "RU" ? RUSSIAN_CITY_NAMES[row.id] ?? row.city : row.city;
}

export function findNearestCatalogCity(latitude: number, longitude: number, maxDistanceKm: number): CatalogCity | null {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

  // Latitude degrees are a constant distance apart, so a band around the point is a safe prefilter
  // that never discards a row inside the radius, including across the antimeridian.
  const latitudeWindow = maxDistanceKm / 111 + 0.01;
  let nearest: { city: CatalogCity; distance: number } | null = null;

  for (const countryRows of getCatalogIndex().values()) {
    for (const row of countryRows) {
      if (Math.abs(Number(row.lat) - latitude) > latitudeWindow) continue;
      const city = parseRow(row);
      if (!city) continue;
      const distance = catalogDistanceKm(latitude, longitude, city.latitude, city.longitude);
      if (distance > maxDistanceKm) continue;
      if (!nearest || distance < nearest.distance || (distance === nearest.distance && city.population > nearest.city.population)) {
        nearest = { city, distance };
      }
    }
  }

  return nearest?.city ?? null;
}

function catalogDistanceKm(fromLat: number, fromLng: number, toLat: number, toLng: number) {
  const toRadians = (value: number) => (value * Math.PI) / 180;
  const latDelta = toRadians(toLat - fromLat);
  const lngDelta = toRadians(toLng - fromLng);
  const a =
    Math.sin(latDelta / 2) ** 2 +
    Math.cos(toRadians(fromLat)) * Math.cos(toRadians(toLat)) * Math.sin(lngDelta / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
