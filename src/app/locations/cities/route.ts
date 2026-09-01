import { NextRequest } from "next/server";

import { fail, getErrorMessage, ok } from "@/lib/http";
import { resolveRequestLocale } from "@/lib/locales";
import { allowLocationRequest, locationRequestIdentifier } from "@/server/location-rate-limit";
import { LOCATION_CATALOG_ATTRIBUTION, searchCities } from "@/server/locations";

export async function GET(request: NextRequest) {
  try {
    if (!allowLocationRequest(locationRequestIdentifier(request))) return fail("Слишком много запросов", 429);
    const countryCode = request.nextUrl.searchParams.get("countryCode") ?? "";
    const query = request.nextUrl.searchParams.get("q") ?? "";
    const locale = resolveRequestLocale({
      explicitLocale: request.nextUrl.searchParams.get("locale"),
      acceptLanguage: request.headers.get("accept-language")
    });
    const limit = Number(request.nextUrl.searchParams.get("limit") ?? "20");
    const places = await searchCities({ countryCode, query, locale, limit: Number.isFinite(limit) ? limit : 20 });
    return ok({ places, attribution: LOCATION_CATALOG_ATTRIBUTION });
  } catch (error) {
    return fail(getErrorMessage(error));
  }
}
