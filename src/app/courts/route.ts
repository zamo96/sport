import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { courtsQuerySchema } from "@/lib/validators";
import { DEFAULT_CITY } from "@/lib/constants";
import { getCourtsForUser } from "@/server/app-data";
import { serializeCourt } from "@/server/serializers";

export async function GET(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const query = courtsQuerySchema.parse(Object.fromEntries(request.nextUrl.searchParams));
    const enriched = await getCourtsForUser(user.id, {
      ...query,
      city: query.city ?? DEFAULT_CITY
    });

    return ok({
      courts: enriched.map(serializeCourt)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
