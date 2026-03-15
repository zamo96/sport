import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { haversineDistanceKm } from "@/lib/geo";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { serializeCourt } from "@/server/serializers";

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const court = await prisma.court.findUnique({
      where: { id: params.id }
    });

    if (!court) {
      return fail("Корт не найден", 404);
    }

    const distanceKm = haversineDistanceKm(
      user.homeLat != null && user.homeLng != null ? { lat: user.homeLat, lng: user.homeLng } : null,
      { lat: court.locationLat, lng: court.locationLng }
    );

    return ok({
      court: serializeCourt({
        ...court,
        distanceKm
      })
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
