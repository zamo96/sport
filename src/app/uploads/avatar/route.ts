import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { uploadAvatar } from "@/lib/uploads";

export async function POST(request: Request) {
  try {
    const user = await requireSessionUser();
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

    const bytes = Buffer.from(await uploadedFile.arrayBuffer());
    const originalName = uploadedFile.name || "avatar.png";
    const avatarUrl = await uploadAvatar({
      bytes,
      originalName,
      contentType: uploadedFile.type,
      userId: user.id
    });

    await prisma.user.update({
      where: { id: user.id },
      data: { avatarUrl }
    });

    return ok({ avatarUrl });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
