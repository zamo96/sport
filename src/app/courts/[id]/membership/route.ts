import { NextRequest } from "next/server";
import { z } from "zod";

import { requireSessionUser } from "@/lib/auth";
import { haversineDistanceKm } from "@/lib/geo";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { emptyCourtActiveSearchSummary, getCourtActiveSearchSummaries } from "@/server/app-data";
import { serializeCourt } from "@/server/serializers";
import { assertActiveCourtIds } from "@/server/court-status";

const courtMembershipSchema = z.object({
  isMember: z.boolean()
});

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = courtMembershipSchema.parse(await request.json());
    const court = await prisma.court.findUnique({
      where: { id: params.id },
      select: { id: true, status: true }
    });

    if (!court) {
      return fail("Клуб не найден", 404);
    }

    if (body.isMember && court.status !== "active") {
      return fail("Клуб временно недоступен", 409);
    }

    if (body.isMember) {
      await prisma.$transaction(async (tx) => {
        await assertActiveCourtIds(tx, [params.id]);
        await tx.userCourt.upsert({
          where: {
            userId_courtId: {
              userId: user.id,
              courtId: params.id
            }
          },
          create: {
            userId: user.id,
            courtId: params.id
          },
          update: {}
        });
      });
    } else {
      await prisma.userCourt.deleteMany({
        where: {
          userId: user.id,
          courtId: params.id
        }
      });
    }

    const refreshed = await prisma.court.findUnique({
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
            userId: {
              not: user.id
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

    if (!refreshed) {
      return fail("Клуб не найден", 404);
    }
    const activeSearchSummaries = await getCourtActiveSearchSummaries([refreshed.id]);

    return ok({
      court: serializeCourt({
        ...refreshed,
        isMember: body.isMember,
        distanceKm: haversineDistanceKm(
          user.homeLat != null && user.homeLng != null ? { lat: user.homeLat, lng: user.homeLng } : null,
          { lat: refreshed.locationLat, lng: refreshed.locationLng }
        ),
        ...(activeSearchSummaries.get(refreshed.id) ?? emptyCourtActiveSearchSummary())
      })
    });
  } catch (error) {
    if (getErrorMessage(error) === "COURT_UNAVAILABLE") {
      return fail("Клуб временно недоступен", 409);
    }
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
