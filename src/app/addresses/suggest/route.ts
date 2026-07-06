import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";

const MIN_QUERY_LENGTH = 3;
const MAX_QUERY_LENGTH = 160;
const MAX_RESULTS = 6;

type YandexAddressFeature = {
  geometry?: {
    coordinates?: [number, number];
  };
  properties?: {
    name?: string;
    description?: string;
    uri?: string;
    GeocoderMetaData?: {
      text?: string;
      kind?: string;
      Address?: {
        formatted?: string;
      };
    };
    CompanyMetaData?: {
      id?: string;
      name?: string;
      address?: string;
    };
  };
};

type YandexAddressResponse = {
  features?: YandexAddressFeature[];
};

type AddressSuggestion = {
  id: string;
  title: string;
  address: string;
  subtitle: string | null;
  lat: number | null;
  lng: number | null;
};

function getYandexAddressApiKey() {
  return (
    process.env.YANDEX_PLACES_API_KEY?.trim() ||
    process.env.YANDEX_GEOCODER_API_KEY?.trim() ||
    process.env.NEXT_PUBLIC_YANDEX_MAPS_API_KEY?.trim() ||
    ""
  );
}

function normalizeQuery(value: string | null) {
  return (value ?? "").trim().replace(/\s+/g, " ").slice(0, MAX_QUERY_LENGTH);
}

function buildSearchText(query: string, city: string) {
  if (!city) {
    return query;
  }

  const lowerQuery = query.toLocaleLowerCase("ru-RU");
  const lowerCity = city.toLocaleLowerCase("ru-RU");
  return lowerQuery.includes(lowerCity) ? query : `${city}, ${query}`;
}

function featureToSuggestion(feature: YandexAddressFeature): AddressSuggestion | null {
  const properties = feature.properties ?? {};
  const company = properties.CompanyMetaData;
  const geocoder = properties.GeocoderMetaData;
  const coordinates = feature.geometry?.coordinates;
  const lng = typeof coordinates?.[0] === "number" ? coordinates[0] : null;
  const lat = typeof coordinates?.[1] === "number" ? coordinates[1] : null;
  const address = company?.address?.trim() || geocoder?.Address?.formatted?.trim() || geocoder?.text?.trim() || properties.name?.trim() || "";

  if (!address) {
    return null;
  }

  const title = company?.name?.trim() || properties.name?.trim() || address;
  const subtitle = properties.description?.trim() || geocoder?.kind?.trim() || null;
  const id = company?.id?.trim() || properties.uri?.trim() || `${address}:${lat ?? "na"}:${lng ?? "na"}`;

  return {
    id,
    title,
    address,
    subtitle,
    lat,
    lng
  };
}

export async function GET(request: NextRequest) {
  try {
    await requireSessionUser();

    const query = normalizeQuery(request.nextUrl.searchParams.get("q"));
    const city = normalizeQuery(request.nextUrl.searchParams.get("city"));

    if (query.length < MIN_QUERY_LENGTH) {
      return ok({ suggestions: [] });
    }

    const apiKey = getYandexAddressApiKey();
    if (!apiKey) {
      return ok({ suggestions: [] });
    }

    const url = new URL("https://search-maps.yandex.ru/v1/");
    url.searchParams.set("apikey", apiKey);
    url.searchParams.set("text", buildSearchText(query, city));
    url.searchParams.set("type", "geo");
    url.searchParams.set("lang", "ru_RU");
    url.searchParams.set("results", String(MAX_RESULTS));

    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) {
      return ok({ suggestions: [] });
    }

    const payload = (await response.json()) as YandexAddressResponse;
    const suggestions = Array.from(
      new Map(
        (payload.features ?? [])
          .map(featureToSuggestion)
          .filter((suggestion): suggestion is AddressSuggestion => suggestion !== null)
          .map((suggestion) => [suggestion.address.toLocaleLowerCase("ru-RU"), suggestion])
      ).values()
    ).slice(0, MAX_RESULTS);

    return ok({ suggestions });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
