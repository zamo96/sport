import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { uploadPersonalActivityPhoto } from "@/lib/uploads";

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

    if (!hasPersonalActivityEnded(activity.scheduledAt, activity.durationMinutes ?? 60)) {
      return fail("Фотоотчёт можно добавить после завершения визита");
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

    const photoUrl = await uploadPersonalActivityPhoto({
      bytes: Buffer.from(await uploadedFile.arrayBuffer()),
      originalName: uploadedFile.name || "personal-activity.png",
      contentType: uploadedFile.type,
      activityId: activity.id,
      userId: user.id
    });

    return ok({ photoUrl });
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
