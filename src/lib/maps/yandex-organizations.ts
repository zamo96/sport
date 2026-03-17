import type { CourtSetting, Sport, Surface } from "@prisma/client";

import { DEFAULT_CITY } from "@/lib/constants";

const YANDEX_ORG_SEARCH_URL = "https://search-maps.yandex.ru/v1/";
const YANDEX_PAGE_SIZE = 50;
const YANDEX_MAX_PAGES = 3;

const SPORT_SEARCH_QUERIES: Record<Sport, string> = {
  table_tennis: "Клуб настольного тенниса",
  tennis: "Теннисный клуб",
  padel: "Падел-клуб",
  squash: "Сквош-клуб",
  badminton: "Клуб бадминтона",
  volleyball: "Волейбольный клуб",
  fitness: "Спортзал",
  boxing: "Боксерский клуб",
  yoga: "Йога-студия",
  football: "Футбольный клуб"
};

type YandexFeature = {
  geometry?: {
    coordinates?: [number, number];
  };
  properties?: {
    name?: string;
    description?: string;
    CompanyMetaData?: {
      id?: string;
      name?: string;
      address?: string;
      url?: string;
    };
  };
};

type YandexSearchResponse = {
  features?: YandexFeature[];
};

export type ExternalCourt = {
  id: string;
  name: string;
  address: string;
  city: string;
  locationLat: number;
  locationLng: number;
  surface: Surface;
  setting: CourtSetting;
  supportedSports: Sport[];
  priceRange: string;
  rating: number | null;
  sourceType: string;
  bookingUrl: string | null;
  createdAt: Date;
  updatedAt: Date;
};

export function getYandexOrgSearchApiKey() {
  return process.env.YANDEX_MAPS_SEARCH_API_KEY?.trim() || "";
}

export function buildYandexOrganizationQuery(city: string, sport: Sport) {
  return `${city || DEFAULT_CITY} ${SPORT_SEARCH_QUERIES[sport]}`.trim();
}

export async function fetchYandexOrganizations(city: string, sport: Sport) {
  const apiKey = getYandexOrgSearchApiKey();

  if (!apiKey) {
    return [];
  }

  try {
    const query = buildYandexOrganizationQuery(city, sport);
    const now = new Date();
    const features: YandexFeature[] = [];

    for (let page = 0; page < YANDEX_MAX_PAGES; page += 1) {
      const url = new URL(YANDEX_ORG_SEARCH_URL);
      url.searchParams.set("apikey", apiKey);
      url.searchParams.set("text", query);
      url.searchParams.set("lang", "ru_RU");
      url.searchParams.set("type", "biz");
      url.searchParams.set("results", String(YANDEX_PAGE_SIZE));
      url.searchParams.set("skip", String(page * YANDEX_PAGE_SIZE));

      const response = await fetch(url, {
        next: {
          revalidate: 1800
        }
      });

      if (!response.ok) {
        throw new Error(`Yandex org search failed: ${response.status}`);
      }

      const data = (await response.json()) as YandexSearchResponse;
      const batch = data.features ?? [];
      features.push(...batch);

      if (batch.length < YANDEX_PAGE_SIZE) {
        break;
      }
    }

    const mappedFeatures = features
      .map((feature) => mapFeatureToExternalCourt(feature, city, sport, now))
      .filter((feature): feature is ExternalCourt => feature !== null);

    return dedupeExternalCourts(mappedFeatures);
  } catch (error) {
    console.error("Failed to fetch Yandex organizations", error);
    return [];
  }
}

function mapFeatureToExternalCourt(feature: YandexFeature, city: string, sport: Sport, now: Date): ExternalCourt | null {
  const coordinates = feature.geometry?.coordinates;

  if (!coordinates || coordinates.length < 2) {
    return null;
  }

  const [lng, lat] = coordinates;
  const company = feature.properties?.CompanyMetaData;
  const name = company?.name ?? feature.properties?.name;
  const address = company?.address ?? feature.properties?.description;

  if (!name || !address) {
    return null;
  }

  return {
    id: `yandex-${sport}-${company?.id ?? `${lat.toFixed(5)}-${lng.toFixed(5)}`}`,
    name,
    address,
    city,
    locationLat: lat,
    locationLng: lng,
    surface: "any" as Surface,
    setting: getFallbackSettingBySport(sport),
    supportedSports: [sport],
    priceRange: "Источник: Яндекс Карты",
    rating: null,
    sourceType: "yandex_org_search",
    bookingUrl: company?.url ?? null,
    createdAt: now,
    updatedAt: now
  } satisfies ExternalCourt;
}

function dedupeExternalCourts(courts: ExternalCourt[]) {
  const seen = new Set<string>();

  return courts.filter((court) => {
    const key = `${court.name.toLowerCase()}::${court.address.toLowerCase()}`;

    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
}

function getFallbackSettingBySport(sport: Sport): CourtSetting {
  if (sport === "football" || sport === "volleyball" || sport === "tennis") {
    return "outdoor";
  }

  return "indoor";
}
