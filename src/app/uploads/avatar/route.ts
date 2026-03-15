import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { randomUUID } from "crypto";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";

export async function POST(request: Request) {
  try {
    const user = await requireSessionUser();
    const formData = await request.formData();
    const file = formData.get("file");

    if (!(file instanceof File)) {
      return fail("Нужно выбрать файл");
    }

    const bytes = Buffer.from(await file.arrayBuffer());
    const extension = file.name.split(".").pop() || "png";
    const uploadsDir = path.join(process.cwd(), "public", "uploads");
    const fileName = `${randomUUID()}.${extension}`;
    const filePath = path.join(uploadsDir, fileName);

    await mkdir(uploadsDir, { recursive: true });
    await writeFile(filePath, bytes);

    const avatarUrl = `/uploads/${fileName}`;

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
