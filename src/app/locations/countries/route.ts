import { NextRequest } from "next/server";

import { fail, ok } from "@/lib/http";
import { resolveRequestLocale } from "@/lib/locales";
import { allowLocationRequest, locationRequestIdentifier } from "@/server/location-rate-limit";
import { LOCATION_CATALOG_ATTRIBUTION, listCountries } from "@/server/locations";

export async function GET(request: NextRequest) {
  if (!allowLocationRequest(locationRequestIdentifier(request), 60)) return fail("Слишком много запросов", 429);
  const query = request.nextUrl.searchParams.get("q") ?? "";
  const locale = resolveRequestLocale({
    explicitLocale: request.nextUrl.searchParams.get("locale"),
    acceptLanguage: request.headers.get("accept-language")
  });
  return ok(
    { countries: listCountries(locale, query), attribution: LOCATION_CATALOG_ATTRIBUTION },
    { headers: { "Cache-Control": "public, max-age=86400" } }
  );
}
