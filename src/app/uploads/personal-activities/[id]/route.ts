import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { uploadPersonalActivityPhoto, uploadPersonalActivityVideo } from "@/lib/uploads";
import { PERSONAL_ACTIVITY_VIDEO_MAX_BYTES } from "@/lib/personal-activity-media";
import { assertPersonalActivityReportAvailable } from "@/server/personal-activities";

export async function POST(request: Request, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const activity = await prisma.personalActivity.findFirst({
      where: {
        id: params.id,
        userId: user.id
      }
    });

    if (!activity) {
      return fail("Визит не найден", 404);
    }

    assertPersonalActivityReportAvailable(activity);

    const contentLength = Number(request.headers.get("content-length"));
    if (Number.isFinite(contentLength) && contentLength > PERSONAL_ACTIVITY_VIDEO_MAX_BYTES + 1024 * 1024) {
      return fail("Файл слишком большой", 413);
    }

    const formData = await request.formData();
    const file = formData.get("file");

    if (
      !file ||
      typeof file === "string" ||
      typeof (file as { arrayBuffer?: unknown }).arrayBuffer !== "function"
    ) {
      return fail("Нужно выбрать файл");
    }

    const uploadedFile = file as {
      arrayBuffer: () => Promise<ArrayBuffer>;
      name?: string;
      type?: string;
    };

    const input = {
      bytes: Buffer.from(await uploadedFile.arrayBuffer()),
      originalName: uploadedFile.name || "personal-activity.png",
      contentType: uploadedFile.type,
      activityId: activity.id,
      userId: user.id
    };
    if (uploadedFile.type?.startsWith("video/") || /\.(mp4|mov)$/i.test(uploadedFile.name ?? "")) {
      const videoUrl = await uploadPersonalActivityVideo(input);
      return ok({ videoUrl });
    }

    const photoUrl = await uploadPersonalActivityPhoto(input);
    return ok({ photoUrl });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
