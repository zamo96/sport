import { CITY_PRESETS, DISTRICT_MAP_AREAS, KAZAN_DISTRICT_OPTIONS, MOSCOW_DISTRICT_OPTIONS, SAINT_PETERSBURG_DISTRICT_OPTIONS } from "@/lib/constants";

export type PublicPlayerMapArea = {
  id: string;
  cityId: string;
  cityName: string;
  kind: "district" | "city";
  districtId: string | null;
  label: string;
  latitude: number;
  longitude: number;
};

type PublicCityLocation = {
  id: string;
  city: string;
  countryCode: string;
  latitude: number;
  longitude: number;
  serviceArea?: { isActive: boolean; districtsEnabled: boolean; legacyCity: string | null } | null;
};

type MapAreaProfile = {
  showOnMap?: boolean;
  city?: string | null;
  locationPlaceId?: string | null;
  location?: PublicCityLocation | null;
  preferredDistricts?: unknown;
};

const cityCatalogue = [
  { id: "legacy:ru:saint-petersburg", name: "Санкт-Петербург", aliases: ["санкт-петербург", "санкт петербург", "петербург", "спб", "saint petersburg", "st. petersburg", "st petersburg"], districts: SAINT_PETERSBURG_DISTRICT_OPTIONS },
  { id: "legacy:ru:moscow", name: "Москва", aliases: ["москва", "moscow"], districts: MOSCOW_DISTRICT_OPTIONS },
  // Whether these shapes can be used is decided by canonical coverage below.
  { id: "legacy:ru:kazan", name: "Казань", aliases: ["казань", "kazan"], districts: KAZAN_DISTRICT_OPTIONS }
] as const;

function validCenter(latitude: number, longitude: number) {
  return Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180;
}

function cityByName(value?: string | null) {
  const name = value?.trim().toLowerCase();
  return cityCatalogue.find((city) => (city.aliases as readonly string[]).includes(name ?? ""));
}

function resolvePublicCity(profile: MapAreaProfile) {
  if (profile.location) {
    const location = profile.location;
    if (!location.id || !location.city.trim() || !location.countryCode ||
        (profile.locationPlaceId && profile.locationPlaceId !== location.id) ||
        !validCenter(location.latitude, location.longitude)) return null;
    const coverage = location.serviceArea;
    const catalogue = location.countryCode === "RU" && coverage?.isActive && coverage.districtsEnabled
      ? cityByName(coverage.legacyCity) : undefined;
    // A same-named settlement in another country never borrows Russian areas.
    const matchingCatalogue = catalogue && cityByName(location.city)?.id === catalogue.id ? catalogue : undefined;
    return { id: location.id, name: location.city, latitude: location.latitude, longitude: location.longitude,
      districts: matchingCatalogue?.districts ?? [] };
  }

  // Never recover an unresolved canonical place by guessing from its display name.
  const catalogue = profile.locationPlaceId
    ? cityCatalogue.find((city) => city.id === profile.locationPlaceId)
    : cityByName(profile.city);
  if (!catalogue) return null;
  const center = CITY_PRESETS[catalogue.name];
  return { id: catalogue.id, name: catalogue.name, latitude: center.lat, longitude: center.lng, districts: catalogue.id === "legacy:ru:kazan" ? [] : catalogue.districts };
}

/** Only canonical city/district catalogue centers may become public map points.
 * Profile coordinates and the legacy primary district are deliberately absent
 * from this function's input contract. Membership does not alter ranking.
 */
export function publicPlayerMapAreas(profile: MapAreaProfile): PublicPlayerMapArea[] {
  if (profile.showOnMap !== true) return [];
  const city = resolvePublicCity(profile);
  if (!city) return [];

  if (!city.districts.length) {
    return [{ id: `${city.id}:city`, cityId: city.id, cityName: city.name, kind: "city", districtId: null,
      label: city.name, latitude: city.latitude, longitude: city.longitude }];
  }

  const preferred = profile.preferredDistricts;
  // A stored null means the player has not chosen districts, so the city applies.
  // An omitted projection is unknown; malformed values must not broaden visibility.
  if (preferred !== null && !Array.isArray(preferred)) return [];
  const requested = new Set((preferred ?? []).filter((value: unknown): value is string => typeof value === "string"));
  // An invalid, nonempty selection must not silently expand to the entire city.
  const wholeCity = preferred === null || preferred.length === 0;
  return (city.districts as readonly string[]).filter((id) => wholeCity || requested.has(id)).flatMap((districtId) => {
    const area = DISTRICT_MAP_AREAS[districtId];
    if (!area || !validCenter(area.center.lat, area.center.lng)) return [];
    return [{ id: `${city.id}:district:${districtId}`, cityId: city.id, cityName: city.name, kind: "district" as const,
      districtId, label: area.label, latitude: area.center.lat, longitude: area.center.lng }];
  });
}
