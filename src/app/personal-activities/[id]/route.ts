import { PersonalActivityStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updatePersonalActivitySchema } from "@/lib/validators";
import { serializePersonalActivity } from "@/server/serializers";

export async function PATCH(request: Request, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = updatePersonalActivitySchema.parse(await request.json());
    const existing = await prisma.personalActivity.findFirst({
      where: {
        id: params.id,
        userId: user.id
      }
    });

    if (!existing) {
      return fail("Визит не найден", 404);
    }

    const nextScheduledAt = body.scheduledAt ? new Date(body.scheduledAt) : existing.scheduledAt;
    const nextDurationMinutes = body.durationMinutes ?? existing.durationMinutes ?? 60;

    if (body.scheduledAt && body.status !== PersonalActivityStatus.completed && nextScheduledAt.getTime() <= Date.now()) {
      return fail("Выбери будущую дату и время");
    }

    if (body.status === PersonalActivityStatus.completed && !hasPersonalActivityEnded(nextScheduledAt, nextDurationMinutes)) {
      return fail("Фотоотчёт можно добавить после завершения визита");
    }

    const activity = await prisma.$transaction(async (tx) => {
      if (body.photoUrls) {
        await tx.personalActivityPhoto.deleteMany({
          where: {
            activityId: existing.id
          }
        });
        await tx.personalActivityPhoto.createMany({
          data: body.photoUrls.map((url, index) => ({
            activityId: existing.id,
            url,
            position: index
          }))
        });
      }

      return tx.personalActivity.update({
        where: {
          id: existing.id
        },
        data: {
          scheduledAt: body.scheduledAt ? new Date(body.scheduledAt) : undefined,
          durationMinutes: body.durationMinutes === undefined ? undefined : body.durationMinutes,
          comment: body.comment === undefined ? undefined : body.comment || null,
          status: body.status,
          reportComment: body.reportComment === undefined ? undefined : body.reportComment || null
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
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

function hasPersonalActivityEnded(scheduledAt: Date, durationMinutes: number) {
  return Date.now() >= scheduledAt.getTime() + durationMinutes * 60 * 1000;
}
