import { Prisma } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { uploadProfileMedia } from "@/lib/uploads";

const PROFILE_PHOTO_LIMIT = 6;
const PROFILE_VIDEO_LIMIT = 4;

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
    const originalName = uploadedFile.name || "profile-media";
    const { mediaType, url } = await uploadProfileMedia({
      bytes,
      originalName,
      contentType: uploadedFile.type,
      userId: user.id
    });

    const current = await prisma.user.findUnique({
      where: { id: user.id },
      select: { avatarUrl: true, profilePhotoUrls: true, profileVideoUrls: true }
    });

    if (!current) {
      return fail("Пользователь не найден", 404);
    }

    const profilePhotoUrls = normalizeMediaList(current.profilePhotoUrls, PROFILE_PHOTO_LIMIT);
    const profileVideoUrls = normalizeMediaList(current.profileVideoUrls, PROFILE_VIDEO_LIMIT);

    if (mediaType === "photo") {
      if (profilePhotoUrls.length >= PROFILE_PHOTO_LIMIT) {
        return fail("Можно добавить до 6 фото в карточку");
      }
      profilePhotoUrls.push(url);
    } else {
      if (profileVideoUrls.length >= PROFILE_VIDEO_LIMIT) {
        return fail("Можно добавить до 4 видео в карточку");
      }
      profileVideoUrls.push(url);
    }

    const nextProfilePhotoUrls = uniqueMedia(profilePhotoUrls, PROFILE_PHOTO_LIMIT);
    const nextProfileVideoUrls = uniqueMedia(profileVideoUrls, PROFILE_VIDEO_LIMIT);
    const nextAvatarUrl = mediaType === "photo" ? nextProfilePhotoUrls[0] : current.avatarUrl;

    const updated = await prisma.user.update({
      where: { id: user.id },
      data: {
        avatarUrl: nextAvatarUrl,
        profilePhotoUrls: nextProfilePhotoUrls as Prisma.InputJsonValue,
        profileVideoUrls: nextProfileVideoUrls as Prisma.InputJsonValue
      },
      select: { avatarUrl: true, profilePhotoUrls: true, profileVideoUrls: true }
    });

    return ok({
      mediaUrl: url,
      mediaType,
      avatarUrl: updated.avatarUrl,
      profilePhotoUrls: normalizeMediaList(updated.profilePhotoUrls, PROFILE_PHOTO_LIMIT),
      profileVideoUrls: normalizeMediaList(updated.profileVideoUrls, PROFILE_VIDEO_LIMIT)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

function normalizeMediaList(value: unknown, limit: number) {
  return uniqueMedia(Array.isArray(value) ? value : [], limit);
}

function uniqueMedia(value: unknown[], limit: number) {
  return Array.from(
    new Set(
      value
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean)
    )
  ).slice(0, limit);
}
