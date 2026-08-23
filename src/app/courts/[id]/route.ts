import { NextRequest } from "next/server";

import { getSessionUser } from "@/lib/auth";
import { haversineDistanceKm } from "@/lib/geo";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { emptyCourtActiveSearchSummary, getCourtActiveSearchSummaries } from "@/server/app-data";
import { serializeCourt } from "@/server/serializers";

export async function GET(_: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await getSessionUser();
    const court = await prisma.court.findUnique({
      where: { id: params.id },
      include: {
        nearestMetro: true,
        metroLinks: {
          include: {
            metro: true
          },
          orderBy: {
            position: "asc"
          }
        },
        members: {
          ...(user
            ? {
                where: {
                  userId: {
                    not: user.id
                  }
                }
              }
            : {}),
          include: {
            user: true
          },
          orderBy: {
            updatedAt: "desc"
          },
          take: 12
        },
        _count: {
          select: {
            members: true
          }
        }
      }
    });

    if (!court) {
      return fail("Корт не найден", 404);
    }
    const membership = user
      ? await prisma.userCourt.findUnique({
          where: {
            userId_courtId: {
              userId: user.id,
              courtId: court.id
            }
          },
          select: {
            id: true
          }
        })
      : null;

    const distanceKm = haversineDistanceKm(
      user && user.homeLat != null && user.homeLng != null ? { lat: user.homeLat, lng: user.homeLng } : null,
      { lat: court.locationLat, lng: court.locationLng }
    );
    const activeSearchSummaries = await getCourtActiveSearchSummaries([court.id]);

    return ok({
      court: serializeCourt({
        ...court,
        isMember: membership != null,
        distanceKm,
        ...(activeSearchSummaries.get(court.id) ?? emptyCourtActiveSearchSummary())
      })
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
