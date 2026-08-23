import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createPersonalActivitySchema } from "@/lib/validators";
import { serializePersonalActivity } from "@/server/serializers";
import { assertActiveCourtIds } from "@/server/court-status";

export async function GET() {
  try {
    const user = await requireSessionUser();
    const activities = await prisma.personalActivity.findMany({
      where: {
        userId: user.id
      },
      include: {
        court: true,
        photos: {
          orderBy: {
            position: "asc"
          }
        }
      },
      orderBy: {
        scheduledAt: "asc"
      }
    });

    return ok({
      personalActivities: activities.map(serializePersonalActivity)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

export async function POST(request: Request) {
  try {
    const user = await requireSessionUser();
    const body = createPersonalActivitySchema.parse(await request.json());
    const court = await prisma.court.findUnique({
      where: {
        id: body.courtId
      }
    });

    if (!court) {
      return fail("Клуб не найден", 404);
    }

    if (court.status !== "active") {
      return fail("Клуб временно недоступен", 409);
    }

    if (!courtSupportsSport(court.supportedSports, body.sport)) {
      return fail("Этот вид спорта недоступен в выбранном клубе");
    }

    const activity = await prisma.$transaction(async (tx) => {
      await assertActiveCourtIds(tx, [court.id]);
      return tx.personalActivity.create({
        data: {
          userId: user.id,
          courtId: court.id,
          sport: body.sport,
          scheduledAt: new Date(body.scheduledAt),
          durationMinutes: body.durationMinutes ?? null,
          comment: body.comment || null
        },
        include: {
          court: true,
          photos: {
            orderBy: {
              position: "asc"
            }
          }
        }
      });
    });

    return ok({
      personalActivity: serializePersonalActivity(activity)
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

function courtSupportsSport(value: unknown, sport: string) {
  if (!Array.isArray(value) || value.length === 0) {
    return true;
  }

  return value.includes(sport);
}
