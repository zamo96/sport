import { NextRequest } from "next/server";
import { z } from "zod";

import { fail, getErrorMessage, ok } from "@/lib/http";
import { resolveRequestLocale } from "@/lib/locales";
import { allowLocationRequest, locationRequestIdentifier } from "@/server/location-rate-limit";
import { reverseGeocode } from "@/server/locations";

const schema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  locale: z.string().trim().max(12).optional()
});

export async function POST(request: NextRequest) {
  try {
    if (!allowLocationRequest(locationRequestIdentifier(request), 15)) return fail("Слишком много запросов", 429);
    const body = schema.parse(await request.json());
    const locale = resolveRequestLocale({
      explicitLocale: body.locale,
      acceptLanguage: request.headers.get("accept-language")
    });
    const place = await reverseGeocode({ ...body, locale });
    if (!place) return fail("Не удалось определить город. Выберите его вручную", 404);
    return ok({ place });
  } catch (error) {
    return fail(getErrorMessage(error));
  }
}
