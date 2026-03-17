import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { courtSupportsSport } from "@/lib/courts";
import { haversineDistanceKm } from "@/lib/geo";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { courtsQuerySchema } from "@/lib/validators";
import { serializeCourt } from "@/server/serializers";

export async function GET(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const query = courtsQuerySchema.parse(Object.fromEntries(request.nextUrl.searchParams));
    const courts = await prisma.court.findMany({
      where: {
        city: query.city ?? undefined,
        surface: query.surface,
        setting: query.setting
      },
      orderBy: [{ city: "asc" }, { rating: "desc" }]
    });

    const enriched = courts
      .map((court) => {
        const distanceKm = haversineDistanceKm(
          user.homeLat != null && user.homeLng != null ? { lat: user.homeLat, lng: user.homeLng } : null,
          { lat: court.locationLat, lng: court.locationLng }
        );

        return {
          ...court,
          distanceKm
        };
      })
      .filter((court) => courtSupportsSport(court.supportedSports, query.sport))
      .filter((court) => (query.maxDistanceKm && court.distanceKm != null ? court.distanceKm <= query.maxDistanceKm : true))
      .sort((left, right) => (left.distanceKm ?? 999) - (right.distanceKm ?? 999));

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
