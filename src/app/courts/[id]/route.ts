import { NextRequest } from "next/server";

import { getSessionUser } from "@/lib/auth";
import { haversineDistanceKm } from "@/lib/geo";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { publicProfileWhere } from "@/lib/profile-visibility";
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
          where: {
            ...(user ? { userId: { not: user.id } } : {}),
            user: {
              accountStatus: "active",
              isVerified: true,
              onboardingCompleted: true,
              ...publicProfileWhere(user ? "registered" : "guest"),
              ...(user
                ? {
                    blockedUsers: { none: { blockedUserId: user.id } },
                    blockingUsers: { none: { blockerUserId: user.id } }
                  }
                : {})
            }
          },
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

    if (!court || court.status !== "active") {
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
    const activeSearchSummaries = await getCourtActiveSearchSummaries([court.id], user?.id);

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
