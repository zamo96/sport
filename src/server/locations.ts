import type { GeoPlace, ServiceArea } from "@prisma/client";

import {
  DEFAULT_LOCALE,
  normalizeSupportedLocale,
  recommendLocaleForConfirmedCountry,
  type SupportedLocale
} from "@/lib/locales";
import { prisma } from "@/lib/prisma";
import {
  type CatalogCity,
  catalogCountries,
  searchCatalogCities
} from "@/server/world-city-catalog";

const CONFIGURED_PROVIDER_URL = process.env.LOCATION_PROVIDER_URL?.trim();
const NOMINATIM_URL = CONFIGURED_PROVIDER_URL || "https://nominatim.openstreetmap.org";
const PROVIDER_TIMEOUT_MS = 4_500;
const PROVIDER_CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const PROVIDER_MIN_INTERVAL_MS = 1_100;

export const LOCATION_CATALOG_ATTRIBUTION = {
  name: "SimpleMaps World Cities Database",
  license: "CC BY 4.0",
  url: "https://simplemaps.com/data/world-cities",
  localization: {
    name: "GeoNames",
    license: "CC BY 4.0",
    url: "https://www.geonames.org/"
  }
} as const;

const ISO_COUNTRY_CODES = [
  "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT", "AU", "AW", "AX", "AZ",
  "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV", "BW", "BY", "BZ",
  "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN", "CO", "CR", "CU", "CV", "CW", "CX", "CY", "CZ",
  "DE", "DJ", "DK", "DM", "DO", "DZ", "EC", "EE", "EG", "EH", "ER", "ES", "ET", "FI", "FJ", "FK", "FM", "FO", "FR",
  "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY",
  "HK", "HM", "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR", "IS", "IT", "JE", "JM", "JO", "JP",
  "KE", "KG", "KH", "KI", "KM", "KN", "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY",
  "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT", "MU", "MV", "MW", "MX", "MY", "MZ",
  "NA", "NC", "NE", "NF", "NG", "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF", "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY",
  "QA", "RE", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SY", "SZ",
  "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ", "UA", "UG", "UM", "US", "UY", "UZ",
  "VA", "VC", "VE", "VG", "VI", "VN", "VU", "WF", "WS", "YE", "YT", "ZA", "ZM", "ZW"
] as const;

type Coverage = {
  isSupported: boolean;
  clubsEnabled: boolean;
  districtsEnabled: boolean;
  legacyCity: string | null;
};

export type SerializedGeoPlace = {
  id: string;
  provider: string;
  countryCode: string;
  countryName: string;
  region: string | null;
  city: string;
  latitude: number;
  longitude: number;
  recommendedLocale: SupportedLocale;
  coverage: Coverage;
};

type PlaceWithCoverage = GeoPlace & { serviceArea: ServiceArea | null };

export type NominatimResult = {
  osm_id?: number | string;
  osm_type?: string;
  place_id?: number | string;
  class?: string;
  category?: string;
  type?: string;
  addresstype?: string;
  place_rank?: number;
  name?: string;
  lat?: string;
  lon?: string;
  display_name?: string;
  address?: Record<string, string | undefined>;
};

const LEGACY_PLACES = [
  {
    id: "legacy:ru:saint-petersburg",
    providerPlaceId: "ru:saint-petersburg",
    aliases: ["санкт-петербург", "санкт петербург", "петербург", "спб", "saint petersburg", "st. petersburg", "st petersburg"],
    countryCode: "RU",
    countryName: "Россия",
    region: "Санкт-Петербург",
    city: "Санкт-Петербург",
    latitude: 59.9386,
    longitude: 30.3141,
    coverage: { isSupported: true, clubsEnabled: true, districtsEnabled: true, legacyCity: "Санкт-Петербург" }
  },
  {
    id: "legacy:ru:moscow",
    providerPlaceId: "ru:moscow",
    aliases: ["москва", "moscow"],
    countryCode: "RU",
    countryName: "Россия",
    region: "Москва",
    city: "Москва",
    latitude: 55.7558,
    longitude: 37.6173,
    coverage: { isSupported: true, clubsEnabled: true, districtsEnabled: true, legacyCity: "Москва" }
  },
  {
    id: "legacy:ru:kazan",
    providerPlaceId: "ru:kazan",
    aliases: ["казань", "kazan"],
    countryCode: "RU",
    countryName: "Россия",
    region: "Республика Татарстан",
    city: "Казань",
    latitude: 55.7961,
    longitude: 49.1064,
    coverage: { isSupported: false, clubsEnabled: false, districtsEnabled: false, legacyCity: null }
  }
] as const;

const providerCache = new Map<string, { expiresAt: number; value: NominatimResult[] }>();
let lastProviderRequestAt = 0;
let providerQueue: Promise<unknown> = Promise.resolve();

export function listCountries(locale: string = DEFAULT_LOCALE, query = "") {
  const safeLocale = normalizeSupportedLocale(locale) ?? DEFAULT_LOCALE;
  const names = new Intl.DisplayNames([safeLocale, DEFAULT_LOCALE], { type: "region" });
  const normalizedQuery = normalizeText(query);
  const catalogCounts = new Map(catalogCountries().map((country) => [country.countryCode, country.cityCount]));
  for (const place of LEGACY_PLACES) {
    if (!catalogCounts.has(place.countryCode)) catalogCounts.set(place.countryCode, 1);
  }

  return ISO_COUNTRY_CODES.flatMap((code) => {
    const cityCount = catalogCounts.get(code) ?? 0;
    return cityCount > 0 ? [{ code, name: names.of(code) ?? code, cityCount }] : [];
  })
    .filter((country) => !normalizedQuery || normalizeText(country.name).includes(normalizedQuery) || country.code.toLowerCase().includes(normalizedQuery))
    .sort((left, right) => left.name.localeCompare(right.name, safeLocale));
}

export async function searchCities(input: { countryCode: string; query: string; locale?: string; limit?: number }) {
  const countryCode = input.countryCode.trim().toUpperCase();
  const query = input.query.trim();
  const limit = Math.min(Math.max(input.limit ?? 20, 1), 20);
  if (!ISO_COUNTRY_CODES.includes(countryCode as (typeof ISO_COUNTRY_CODES)[number])) throw new Error("Некорректный код страны");
  if (!query) return listKnownCities(countryCode, limit);
  if (query.length < 2) return [];

  const legacyMatches = LEGACY_PLACES.filter(
    (place) => place.countryCode === countryCode && place.aliases.some((alias) => alias.includes(normalizeText(query)))
  );

  const serializedLegacyMatches = legacyMatches.map(serializeLegacyPlace);
  const catalogMatches = searchCatalogCities(countryCode, query, limit + LEGACY_PLACES.length);
  const catalogPlaces = await persistReturnedCatalogPlaces(
    catalogMatches,
    Math.max(0, limit - serializedLegacyMatches.length),
    new Set(serializedLegacyMatches.map((place) => place.id))
  );
  const localPlaces = dedupePlaces([
    ...serializedLegacyMatches,
    ...catalogPlaces
  ]).slice(0, limit);
  if (localPlaces.length > 0) return localPlaces;

  try {
    const url = buildSettlementSearchUrl(countryCode, query, input.locale, limit);
    const results = await fetchProvider(url);
    const canonicalResults = canonicalizeNominatimSearchResults(results);
    const places = await Promise.all(canonicalResults.map((result) => persistNominatimPlace(result)));
    return dedupePlaces(places.filter(Boolean) as SerializedGeoPlace[]).slice(0, limit);
  } catch {
    return [];
  }
}

async function listKnownCities(countryCode: string, limit: number) {
  const supportedLegacy = LEGACY_PLACES.filter(
    (place) => place.countryCode === countryCode && place.coverage.isSupported
  ).map(serializeLegacyPlace);
  const catalogMatches = searchCatalogCities(countryCode, "", limit + supportedLegacy.length + LEGACY_PLACES.length);
  const catalogPlaces = await persistReturnedCatalogPlaces(
    catalogMatches,
    Math.max(0, limit - supportedLegacy.length),
    new Set(supportedLegacy.map((place) => place.id))
  );
  return dedupePlaces([...supportedLegacy, ...catalogPlaces]).slice(0, limit);
}

async function persistReturnedCatalogPlaces(candidates: CatalogCity[], limit: number, excludedIds = new Set<string>()) {
  if (limit <= 0) return [];
  const selected: Array<{ city: CatalogCity; legacy: (typeof LEGACY_PLACES)[number] | null }> = [];
  const selectedIds = new Set(excludedIds);
  for (const city of candidates) {
    const legacy = findLegacyCatalogPlace(city);
    const id = legacy?.id ?? `simplemaps:${city.id}`;
    if (selectedIds.has(id)) continue;
    selectedIds.add(id);
    selected.push({ city, legacy: legacy ?? null });
    if (selected.length >= limit) break;
  }

  return Promise.all(selected.map(async ({ city, legacy }) => {
    if (legacy) {
      await ensureLegacyLocation(legacy.city);
      return serializeLegacyPlace(legacy);
    }
    return persistCatalogPlace(city);
  }));
}

async function persistCatalogPlace(city: CatalogCity): Promise<SerializedGeoPlace> {
  const id = `simplemaps:${city.id}`;
  const place = await prisma.geoPlace.upsert({
    where: { id },
    update: {
      countryName: city.country,
      region: city.region,
      city: city.city,
      normalizedCity: normalizeText(city.city),
      latitude: city.latitude,
      longitude: city.longitude
    },
    create: {
      id,
      provider: "simplemaps",
      providerPlaceId: city.id,
      countryCode: city.countryCode,
      countryName: city.country,
      region: city.region,
      city: city.city,
      normalizedCity: normalizeText(city.city),
      latitude: city.latitude,
      longitude: city.longitude
    },
    include: { serviceArea: true }
  });
  return serializePlace(place);
}

export async function reverseGeocode(input: { latitude: number; longitude: number; locale?: string }) {
  assertCoordinates(input.latitude, input.longitude);
  try {
    const url = new URL("/reverse", NOMINATIM_URL);
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("addressdetails", "1");
    url.searchParams.set("lat", String(input.latitude));
    url.searchParams.set("lon", String(input.longitude));
    url.searchParams.set("zoom", "10");
    url.searchParams.set("accept-language", normalizeLocale(input.locale));
    const [result] = await fetchProvider(url);
    const canonicalResult = result ? await resolveCanonicalSettlement(result, input.locale) : null;
    const place = canonicalResult ? await persistNominatimPlace(canonicalResult) : null;
    if (place) return place;
  } catch {
    // A nearby built-in place is a safe availability fallback; arbitrary client labels are never accepted.
  }

  const nearest = LEGACY_PLACES.map((place) => ({ place, distance: distanceKm(input, place) }))
    .sort((left, right) => left.distance - right.distance)[0];
  return nearest && nearest.distance <= 80 ? serializeLegacyPlace(nearest.place) : null;
}

export async function getLocationPlace(id: string) {
  const place = await prisma.geoPlace.findUnique({ where: { id }, include: { serviceArea: true } });
  return place ? serializePlace(place) : null;
}

export async function ensureLegacyLocation(city: string) {
  const preset = findLegacyPlace(city);
  if (!preset) return null;
  await prisma.geoPlace.upsert({
    where: { id: preset.id },
    update: {},
    create: {
      id: preset.id,
      provider: "legacy",
      providerPlaceId: preset.providerPlaceId,
      countryCode: preset.countryCode,
      countryName: preset.countryName,
      region: preset.region,
      city: preset.city,
      normalizedCity: normalizeText(preset.city),
      latitude: preset.latitude,
      longitude: preset.longitude
    }
  });
  if (preset.coverage.isSupported) {
    await prisma.serviceArea.upsert({
      where: { locationPlaceId: preset.id },
      update: {},
      create: {
        locationPlaceId: preset.id,
        legacyCity: preset.coverage.legacyCity,
        clubsEnabled: preset.coverage.clubsEnabled,
        districtsEnabled: preset.coverage.districtsEnabled
      }
    });
  }
  return getLocationPlace(preset.id);
}

export function serializeLocationRelation(location?: PlaceWithCoverage | null) {
  return location ? serializePlace(location) : null;
}

export const emptyCoverage = (): Coverage => ({
  isSupported: false,
  clubsEnabled: false,
  districtsEnabled: false,
  legacyCity: null
});

export function shouldPreserveCurrentGlobalLocation(
  requestedLocationPlaceId: string | null | undefined,
  currentLocationPlaceId: string | null | undefined
) {
  return !requestedLocationPlaceId && Boolean(currentLocationPlaceId && !currentLocationPlaceId.startsWith("legacy:"));
}

async function persistNominatimPlace(result: NominatimResult): Promise<SerializedGeoPlace | null> {
  if (!isNominatimSettlementResult(result)) return null;
  const address = result.address ?? {};
  const city = getNominatimSettlementName(result);
  const countryCode = address.country_code?.toUpperCase();
  const latitude = Number(result.lat);
  const longitude = Number(result.lon);
  if (!city || !countryCode || !Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

  const legacy =
    countryCode === "RU"
      ? findLegacyPlace(city) ??
        LEGACY_PLACES.find((place) => distanceKm({ latitude, longitude }, place) <= 3)
      : null;
  if (legacy) {
    await ensureLegacyLocation(legacy.city);
    return serializeLegacyPlace(legacy);
  }

  const providerPlaceId = nominatimProviderPlaceId(result);
  if (!providerPlaceId) return null;
  const id = `nominatim:${providerPlaceId}`;
  const place = await prisma.geoPlace.upsert({
    where: { id },
    update: {
      countryName: address.country || countryCode,
      region: address.state || address.region || null,
      city,
      normalizedCity: normalizeText(city),
      latitude,
      longitude
    },
    create: {
      id,
      provider: "nominatim",
      providerPlaceId,
      countryCode,
      countryName: address.country || countryCode,
      region: address.state || address.region || null,
      city,
      normalizedCity: normalizeText(city),
      latitude,
      longitude
    },
    include: { serviceArea: true }
  });
  return serializePlace(place);
}

async function resolveCanonicalSettlement(result: NominatimResult, locale?: string) {
  const city = getNominatimSettlementName(result);
  const countryCode = result.address?.country_code?.toUpperCase();
  if (!city || !countryCode) return null;

  try {
    const candidates = await fetchProvider(buildSettlementSearchUrl(countryCode, city, locale, 10));
    return selectCanonicalNominatimSettlement(result, candidates) ?? (isNominatimSettlementResult(result) ? result : null);
  } catch {
    return isNominatimSettlementResult(result) ? result : null;
  }
}

export function isNominatimSettlementResult(result: NominatimResult) {
  const addressType = (result.addresstype ?? result.type ?? "").toLowerCase();
  const category = (result.class ?? result.category ?? "").toLowerCase();
  const settlementTypes = new Set(["city", "town", "village", "municipality"]);
  if (!settlementTypes.has(addressType)) return false;
  return category === "place" || category === "boundary";
}

export function selectCanonicalNominatimSettlement(source: NominatimResult, candidates: NominatimResult[]) {
  const sourceCity = normalizeText(getNominatimSettlementName(source) ?? "");
  const sourceCountry = source.address?.country_code?.toUpperCase();
  const sourceRegion = normalizeText(source.address?.state || source.address?.region || "");
  const sourceLatitude = Number(source.lat);
  const sourceLongitude = Number(source.lon);

  const matches = candidates.filter((candidate) => {
    if (!isNominatimSettlementResult(candidate)) return false;
    if (candidate.address?.country_code?.toUpperCase() !== sourceCountry) return false;
    if (normalizeText(getNominatimSettlementName(candidate) ?? "") !== sourceCity) return false;
    const candidateRegion = normalizeText(candidate.address?.state || candidate.address?.region || "");
    return !sourceRegion || !candidateRegion || sourceRegion === candidateRegion;
  });

  return matches.sort((left, right) => {
    const relationDelta = Number(right.osm_type === "relation") - Number(left.osm_type === "relation");
    if (relationDelta) return relationDelta;
    if (!Number.isFinite(sourceLatitude) || !Number.isFinite(sourceLongitude)) return 0;
    return (
      distanceKm(
        { latitude: sourceLatitude, longitude: sourceLongitude },
        { latitude: Number(left.lat), longitude: Number(left.lon) }
      ) -
      distanceKm(
        { latitude: sourceLatitude, longitude: sourceLongitude },
        { latitude: Number(right.lat), longitude: Number(right.lon) }
      )
    );
  })[0] ?? null;
}

export function canonicalizeNominatimSearchResults(results: NominatimResult[]) {
  const groups = new Map<string, NominatimResult[]>();
  for (const result of results.filter(isNominatimSettlementResult)) {
    const address = result.address ?? {};
    const key = [
      address.country_code?.toUpperCase() ?? "",
      normalizeText(address.state || address.region || ""),
      normalizeText(address.county || address.state_district || ""),
      normalizeText(getNominatimSettlementName(result) ?? "")
    ].join(":");
    const group = groups.get(key) ?? [];
    group.push(result);
    groups.set(key, group);
  }

  return Array.from(groups.values()).map((group) =>
    group.slice().sort((left, right) => Number(right.osm_type === "relation") - Number(left.osm_type === "relation"))[0]
  );
}

export function nominatimProviderPlaceId(result: NominatimResult) {
  const identifier = result.osm_id ?? result.place_id;
  return identifier == null ? null : `${result.osm_type ?? "place"}:${identifier}`;
}

function getNominatimSettlementName(result: NominatimResult) {
  const address = result.address ?? {};
  return address.city || address.town || address.village || address.municipality || (isNominatimSettlementResult(result) ? result.name : undefined);
}

function buildSettlementSearchUrl(countryCode: string, city: string, locale?: string, limit = 20) {
  const url = new URL("/search", NOMINATIM_URL);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("countrycodes", countryCode.toLowerCase());
  url.searchParams.set("city", city);
  url.searchParams.set("featureType", "settlement");
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("accept-language", normalizeLocale(locale));
  return url;
}

async function fetchProvider(url: URL) {
  if (process.env.NODE_ENV === "production" && !CONFIGURED_PROVIDER_URL) {
    throw new Error("Для глобального поиска городов требуется настроенный геокодер");
  }
  const key = url.toString();
  const cached = providerCache.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const request = providerQueue.then(async () => {
    const queuedCache = providerCache.get(key);
    if (queuedCache && queuedCache.expiresAt > Date.now()) return queuedCache.value;
    const waitMs = Math.max(0, lastProviderRequestAt + PROVIDER_MIN_INTERVAL_MS - Date.now());
    if (waitMs) await new Promise((resolve) => setTimeout(resolve, waitMs));
    lastProviderRequestAt = Date.now();
    const response = await fetch(url, {
      headers: {
        "Accept-Language": url.searchParams.get("accept-language") ?? "ru",
        "User-Agent": process.env.LOCATION_PROVIDER_USER_AGENT?.trim() || "TennisSearch/1.0 (https://sportsearch.app)"
      },
      signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
      cache: "no-store"
    });
    if (!response.ok) throw new Error("Сервис определения города временно недоступен");
    const payload = await response.json();
    const value = Array.isArray(payload) ? payload as NominatimResult[] : [payload as NominatimResult];
    providerCache.set(key, { expiresAt: Date.now() + PROVIDER_CACHE_TTL_MS, value });
    return value;
  });
  providerQueue = request.then(() => undefined, () => undefined);
  return request;
}

function serializePlace(place: PlaceWithCoverage): SerializedGeoPlace {
  const coverage = place.serviceArea && place.serviceArea.isActive
    ? {
        isSupported: true,
        clubsEnabled: place.serviceArea.clubsEnabled,
        districtsEnabled: place.serviceArea.districtsEnabled,
        legacyCity: place.serviceArea.legacyCity
      }
    : emptyCoverage();
  return {
    id: place.id,
    provider: place.provider,
    countryCode: place.countryCode,
    countryName: place.countryName,
    region: place.region,
    city: place.city,
    latitude: place.latitude,
    longitude: place.longitude,
    recommendedLocale: recommendLocaleForConfirmedCountry(place.countryCode),
    coverage
  };
}

function serializeLegacyPlace(place: (typeof LEGACY_PLACES)[number]): SerializedGeoPlace {
  return {
    id: place.id,
    provider: "legacy",
    countryCode: place.countryCode,
    countryName: place.countryName,
    region: place.region,
    city: place.city,
    latitude: place.latitude,
    longitude: place.longitude,
    recommendedLocale: recommendLocaleForConfirmedCountry(place.countryCode),
    coverage: { ...place.coverage }
  };
}

function findLegacyPlace(city: string) {
  const normalized = normalizeText(city);
  return LEGACY_PLACES.find((place) => place.aliases.some((alias) => alias === normalized));
}

function findLegacyCatalogPlace(city: CatalogCity) {
  if (city.countryCode !== "RU") return undefined;
  return findLegacyPlace(city.city) ?? findLegacyPlace(city.cityAscii) ??
    LEGACY_PLACES.find((place) => distanceKm(city, place) <= 3);
}

function normalizeText(value: string) {
  return value.trim().toLocaleLowerCase("ru-RU").replace(/ё/g, "е").replace(/\s+/g, " ");
}

function normalizeLocale(locale?: string) {
  return normalizeSupportedLocale(locale) ?? DEFAULT_LOCALE;
}

function assertCoordinates(latitude: number, longitude: number) {
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new Error("Некорректные координаты");
  }
}

function dedupePlaces(places: SerializedGeoPlace[]) {
  return Array.from(new Map(places.map((place) => [place.id, place])).values());
}

function distanceKm(left: { latitude: number; longitude: number }, right: { latitude: number; longitude: number }) {
  const toRadians = (value: number) => (value * Math.PI) / 180;
  const latDelta = toRadians(right.latitude - left.latitude);
  const lngDelta = toRadians(right.longitude - left.longitude);
  const a = Math.sin(latDelta / 2) ** 2 + Math.cos(toRadians(left.latitude)) * Math.cos(toRadians(right.latitude)) * Math.sin(lngDelta / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
