import { createHash } from "node:crypto";

import type { Sport } from "@prisma/client";

import { DISTRICT_MAP_AREAS, SPORT_OPTIONS, type DistrictOption } from "@/lib/constants";
import { haversineDistanceKm } from "@/lib/geo";

const MAX_PHOTO_URLS = 8;
const MAX_AMENITIES = 12;
const EARTH_COORDINATE_PRECISION = 6;
const VALID_SPORTS = new Set<string>(SPORT_OPTIONS);

const SPORT_ALIASES: Record<string, Sport> = {
  table_tennis: "table_tennis",
  "table tennis": "table_tennis",
  "ping pong": "table_tennis",
  "настольный теннис": "table_tennis",
  "пинг понг": "table_tennis",
  tennis: "tennis",
  "большой теннис": "tennis",
  "теннис": "tennis",
  padel: "padel",
  "падел": "padel",
  squash: "squash",
  "сквош": "squash",
  badminton: "badminton",
  "бадминтон": "badminton",
  volleyball: "volleyball",
  "волейбол": "volleyball",
  fitness: "fitness",
  "фитнес": "fitness",
  "фитнесс": "fitness",
  "спортзал": "fitness",
  boxing: "boxing",
  "бокс": "boxing",
  yoga: "yoga",
  "йога": "yoga",
  football: "football",
  "футбол": "football",
  running: "running",
  run: "running",
  "бег": "running",
  "пробежка": "running"
};

const CLUB_NAME_STOP_WORDS = new Set([
  "ooo",
  "ооо",
  "zao",
  "зао",
  "oao",
  "оао",
  "ao",
  "ао",
  "ip",
  "ип",
  "llc",
  "клуб",
  "центр",
  "спортивный",
  "теннисный",
  "фитнес",
  "академия",
  "школа"
]);

const ADDRESS_STOP_WORDS = new Set([
  "санкт",
  "петербург",
  "спб",
  "город",
  "г",
  "улица",
  "ул",
  "проспект",
  "пр",
  "площадь",
  "пл",
  "набережная",
  "наб",
  "дом",
  "д",
  "корпус",
  "к",
  "строение",
  "стр"
]);

export type ClubSyncSourceRecord = {
  sourceType: string;
  sourceExternalId?: string | null;
  sourceUrl?: string | null;
  name?: string | null;
  address?: string | null;
  city?: string | null;
  district?: string | null;
  sports?: unknown;
  phone?: string | null;
  workingHours?: string | null;
  yandexMapsUrl?: string | null;
  websiteUrl?: string | null;
  bookingUrl?: string | null;
  about?: string | null;
  amenities?: unknown;
  messengerType?: string | null;
  messengerUrl?: string | null;
  photoUrl?: string | null;
  photoUrls?: unknown;
  metroNames?: unknown;
  locationLat?: number | string | null;
  locationLng?: number | string | null;
  lat?: number | string | null;
  lng?: number | string | null;
  rating?: number | string | null;
  raw?: unknown;
};

export type NormalizedClubSyncRecord = {
  sourceType: string;
  sourceExternalId: string | null;
  sourceUrl: string | null;
  name: string;
  address: string;
  city: string;
  district: DistrictOption | null;
  sports: Sport[];
  phone: string | null;
  workingHours: string | null;
  yandexMapsUrl: string | null;
  websiteUrl: string | null;
  bookingUrl: string | null;
  about: string | null;
  amenities: string[];
  messengerType: string | null;
  messengerUrl: string | null;
  photoUrl: string | null;
  photoUrls: string[];
  metroNames: string[];
  locationLat: number;
  locationLng: number;
  rating: number | null;
  normalizedName: string;
  normalizedAddress: string;
  syncHash: string;
  raw: unknown;
};

export type ClubCourtMatchCandidate = {
  id: string;
  name: string;
  address: string;
  city: string;
  phone?: string | null;
  websiteUrl?: string | null;
  sourceType: string;
  sourceExternalId?: string | null;
  normalizedName?: string | null;
  normalizedAddress?: string | null;
  locationLat: number;
  locationLng: number;
};

export type ClubMatchResult = {
  confidence: number;
  reason: string;
};

export function normalizeClubSyncRecord(
  input: ClubSyncSourceRecord,
  fallbackCity: string
): NormalizedClubSyncRecord | null {
  const sourceType = normalizeToken(input.sourceType);
  const name = normalizeText(input.name);
  const address = normalizeAddress(input.address);
  const sports = normalizeClubSports(input.sports);
  const locationLat = parseCoordinate(input.locationLat ?? input.lat);
  const locationLng = parseCoordinate(input.locationLng ?? input.lng);

  if (!sourceType || !name || !address || sports.length === 0 || locationLat == null || locationLng == null) {
    return null;
  }

  const city = normalizeText(input.city) ?? fallbackCity;
  const photoUrls = normalizeUrlValues(input.photoUrls);
  const photoUrl = normalizeUrl(input.photoUrl) ?? photoUrls[0] ?? null;
  const normalizedName = normalizeClubIdentityText(name);
  const normalizedAddress = normalizeClubAddressIdentity(address);
  const district = normalizeDistrict(input.district) ?? inferDistrictFromCoordinates(locationLat, locationLng);
  const result = {
    sourceType,
    sourceExternalId: normalizeText(input.sourceExternalId),
    sourceUrl: normalizeUrl(input.sourceUrl),
    name,
    address,
    city,
    district,
    sports,
    phone: normalizePhone(input.phone),
    workingHours: normalizeText(input.workingHours),
    yandexMapsUrl: normalizeUrl(input.yandexMapsUrl),
    websiteUrl: normalizeUrl(input.websiteUrl),
    bookingUrl: normalizeUrl(input.bookingUrl),
    about: normalizeText(input.about),
    amenities: normalizeTextArray(input.amenities).slice(0, MAX_AMENITIES),
    messengerType: normalizeToken(input.messengerType),
    messengerUrl: normalizeUrl(input.messengerUrl),
    photoUrl,
    photoUrls: uniqueNonEmpty([photoUrl, ...photoUrls].filter((value): value is string => Boolean(value))).slice(0, MAX_PHOTO_URLS),
    metroNames: normalizeTextArray(input.metroNames),
    locationLat,
    locationLng,
    rating: parseRating(input.rating),
    normalizedName,
    normalizedAddress,
    syncHash: "",
    raw: input.raw ?? input
  } satisfies NormalizedClubSyncRecord;

  return {
    ...result,
    syncHash: buildClubSyncHash(result)
  };
}

export function normalizeClubSports(value: unknown): Sport[] {
  const values = normalizeTextArray(value);
  const sports = values
    .flatMap((item) => item.split(/[|,/]+/))
    .map((item) => item.trim().toLowerCase())
    .map((item) => SPORT_ALIASES[item] ?? (VALID_SPORTS.has(item) ? (item as Sport) : null))
    .filter((item): item is Sport => Boolean(item));

  return Array.from(new Set(sports));
}

export function normalizeClubIdentityText(value: string) {
  return normalizeComparableText(value)
    .split(" ")
    .filter((token) => !CLUB_NAME_STOP_WORDS.has(token))
    .join(" ")
    .trim();
}

export function normalizeClubAddressIdentity(value: string) {
  return normalizeComparableText(value)
    .split(" ")
    .filter((token) => !ADDRESS_STOP_WORDS.has(token))
    .join(" ")
    .trim();
}

export function scoreClubCourtMatch(
  court: ClubCourtMatchCandidate,
  incoming: Pick<
    NormalizedClubSyncRecord,
    | "sourceType"
    | "sourceExternalId"
    | "normalizedName"
    | "normalizedAddress"
    | "phone"
    | "websiteUrl"
    | "locationLat"
    | "locationLng"
  >
): ClubMatchResult {
  const isSameSource = court.sourceType === incoming.sourceType;
  if (isSameSource && incoming.sourceExternalId && court.sourceExternalId) {
    if (court.sourceExternalId === incoming.sourceExternalId) {
      return { confidence: 1, reason: "external_id" };
    }

    // IDs from the same provider are authoritative. In particular, shared
    // reception phones and corporate websites must not merge distinct clubs.
    return { confidence: 0, reason: "external_id_conflict" };
  }

  const courtPhone = normalizePhone(court.phone);
  const courtWebsite = normalizeUrl(court.websiteUrl);
  if (incoming.phone && courtPhone && incoming.phone === courtPhone) {
    return { confidence: 0.94, reason: "phone" };
  }

  if (incoming.websiteUrl && courtWebsite && normalizeUrlHost(incoming.websiteUrl) === normalizeUrlHost(courtWebsite)) {
    return { confidence: 0.92, reason: "website" };
  }

  const courtName = court.normalizedName || normalizeClubIdentityText(court.name);
  const courtAddress = court.normalizedAddress || normalizeClubAddressIdentity(court.address);
  const nameSimilarity = diceSimilarity(courtName, incoming.normalizedName);
  const addressSimilarity = diceSimilarity(courtAddress, incoming.normalizedAddress);
  const distanceKm = haversineDistanceKm(
    { lat: court.locationLat, lng: court.locationLng },
    { lat: incoming.locationLat, lng: incoming.locationLng }
  );

  if (courtName === incoming.normalizedName && courtAddress === incoming.normalizedAddress) {
    return { confidence: 0.95, reason: "name_address" };
  }

  if (nameSimilarity >= 0.86 && addressSimilarity >= 0.78) {
    return { confidence: 0.88, reason: "similar_name_address" };
  }

  if (nameSimilarity >= 0.9 && distanceKm != null && distanceKm <= 0.2) {
    return { confidence: 0.84, reason: "similar_name_nearby" };
  }

  if (addressSimilarity >= 0.9 && distanceKm != null && distanceKm <= 0.1) {
    return { confidence: 0.72, reason: "same_address_needs_review" };
  }

  return {
    confidence: Math.max(nameSimilarity * 0.5 + addressSimilarity * 0.35, 0),
    reason: "weak_similarity"
  };
}

export function buildClubSyncHash(record: Omit<NormalizedClubSyncRecord, "syncHash">) {
  return createHash("sha256")
    .update(
      stableJson({
        name: record.name,
        address: record.address,
        city: record.city,
        district: record.district,
        sports: record.sports,
        phone: record.phone,
        workingHours: record.workingHours,
        yandexMapsUrl: record.yandexMapsUrl,
        websiteUrl: record.websiteUrl,
        bookingUrl: record.bookingUrl,
        about: record.about,
        amenities: record.amenities,
        messengerType: record.messengerType,
        messengerUrl: record.messengerUrl,
        photoUrl: record.photoUrl,
        photoUrls: record.photoUrls,
        metroNames: record.metroNames,
        locationLat: roundCoordinate(record.locationLat),
        locationLng: roundCoordinate(record.locationLng),
        rating: record.rating
      })
    )
    .digest("hex");
}

export function inferDistrictFromCoordinates(lat: number, lng: number): DistrictOption | null {
  const candidates = Object.entries(DISTRICT_MAP_AREAS).filter(([, area]) => pointInPolygon([lng, lat], area.polygon));

  return candidates
    .map(([district, area]) => ({
      district: district as DistrictOption,
      distanceKm: haversineDistanceKm({ lat, lng }, area.center) ?? Number.POSITIVE_INFINITY
    }))
    .sort((left, right) => left.distanceKm - right.distanceKm)[0]?.district ?? null;
}

export function normalizePhone(value: unknown) {
  const text = normalizeText(value);
  if (!text) {
    return null;
  }

  const digits = text.replace(/\D+/g, "");
  if (digits.length === 11 && digits.startsWith("8")) {
    return `7${digits.slice(1)}`;
  }

  return digits.length >= 10 ? digits : null;
}

export function normalizeUrl(value: unknown) {
  const text = normalizeText(value);
  if (!text || !/^https?:\/\//i.test(text)) {
    return null;
  }

  try {
    const url = new URL(text);
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function normalizeUrlHost(value: string) {
  try {
    return new URL(value).hostname.replace(/^www\./i, "").toLowerCase();
  } catch {
    return value.toLowerCase();
  }
}

function normalizeComparableText(value: string) {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/ё/g, "е")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeText(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.replace(/\s+/g, " ").trim();
  return normalized.length > 0 ? normalized : null;
}

function normalizeToken(value: unknown) {
  return normalizeText(value)?.toLowerCase().replace(/\s+/g, "_") ?? null;
}

function normalizeAddress(value: unknown) {
  return normalizeText(value)?.replace(/^Санкт-Петербург\s*;\s*/i, "") ?? null;
}

function normalizeTextArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return uniqueNonEmpty(value.flatMap(normalizeTextArray));
  }

  const text = normalizeText(value);
  if (!text) {
    return [];
  }

  return uniqueNonEmpty(
    text
      .split(/[\n;,|]+/)
      .map((item) => item.trim())
      .filter(Boolean)
  );
}

function normalizeUrlValues(value: unknown) {
  return normalizeTextArray(value)
    .map(normalizeUrl)
    .filter((item): item is string => Boolean(item));
}

function normalizeDistrict(value: unknown): DistrictOption | null {
  const token = normalizeToken(value);
  if (!token) {
    return null;
  }

  return token in DISTRICT_MAP_AREAS ? (token as DistrictOption) : null;
}

function parseCoordinate(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value !== "string") {
    return null;
  }

  const parsed = Number(value.replace(",", ".").trim());
  return Number.isFinite(parsed) ? parsed : null;
}

function parseRating(value: unknown) {
  const parsed = parseCoordinate(value);
  return parsed != null && parsed >= 0 && parsed <= 5 ? parsed : null;
}

function roundCoordinate(value: number) {
  return Number(value.toFixed(EARTH_COORDINATE_PRECISION));
}

function uniqueNonEmpty(values: string[]) {
  return values.reduce<string[]>((result, value) => {
    const normalized = value.trim();
    if (normalized && !result.includes(normalized)) {
      result.push(normalized);
    }
    return result;
  }, []);
}

function pointInPolygon(point: [number, number], polygon: [number, number][]) {
  const [x, y] = point;
  let inside = false;

  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i][0];
    const yi = polygon[i][1];
    const xj = polygon[j][0];
    const yj = polygon[j][1];
    const intersects = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;

    if (intersects) {
      inside = !inside;
    }
  }

  return inside;
}

function diceSimilarity(left: string, right: string) {
  if (left === right) {
    return 1;
  }

  if (!left || !right) {
    return 0;
  }

  const leftBigrams = bigrams(left);
  const rightBigrams = bigrams(right);
  if (leftBigrams.length === 0 || rightBigrams.length === 0) {
    return left === right ? 1 : 0;
  }

  const rightCounts = new Map<string, number>();
  for (const bigram of rightBigrams) {
    rightCounts.set(bigram, (rightCounts.get(bigram) ?? 0) + 1);
  }

  let intersection = 0;
  for (const bigram of leftBigrams) {
    const count = rightCounts.get(bigram) ?? 0;
    if (count > 0) {
      intersection += 1;
      rightCounts.set(bigram, count - 1);
    }
  }

  return (2 * intersection) / (leftBigrams.length + rightBigrams.length);
}

function bigrams(value: string) {
  const compact = value.replace(/\s+/g, " ");
  if (compact.length < 2) {
    return compact ? [compact] : [];
  }

  return Array.from({ length: compact.length - 1 }, (_, index) => compact.slice(index, index + 2));
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(",")}]`;
  }

  if (value && typeof value === "object") {
    return `{${Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`)
      .join(",")}}`;
  }

  return JSON.stringify(value);
}
