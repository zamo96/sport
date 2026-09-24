import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { updatePersonalActivitySchema } from "@/lib/validators";
import { isOwnedPersonalActivityVideoUrl } from "@/lib/uploads";
import { personalActivityVideoUrls } from "@/lib/personal-activity-media";
import { validatePersonalActivityUpdate } from "@/server/personal-activities";
import { serializePersonalActivity } from "@/server/serializers";

export async function PATCH(request: Request, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = updatePersonalActivitySchema.parse(await request.json());
    const existing = await prisma.personalActivity.findFirst({
      where: {
        id: params.id,
        userId: user.id
      },
      include: { photos: true }
    });

    if (!existing) {
      return fail("Визит не найден", 404);
    }

    validatePersonalActivityUpdate(existing, body);
    const savedVideos = new Set(personalActivityVideoUrls(existing.videoUrls));
    if (body.videoUrls?.some((url) => !savedVideos.has(url) && !isOwnedPersonalActivityVideoUrl(url, existing.id, user.id))) {
      return fail("Видео не относится к этому визиту");
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
          id: existing.id,
          userId: user.id,
          updatedAt: existing.updatedAt
        },
        data: {
          scheduledAt: body.scheduledAt ? new Date(body.scheduledAt) : undefined,
          durationMinutes: body.durationMinutes === undefined ? undefined : body.durationMinutes,
          comment: body.comment === undefined ? undefined : body.comment || null,
          status: body.status,
          reportComment: body.reportComment === undefined ? undefined : body.reportComment || null,
          videoUrls: body.videoUrls
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
