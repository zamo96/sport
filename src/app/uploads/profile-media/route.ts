import { Prisma } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import {
  normalizeProfileMediaList,
  PROFILE_PHOTO_LIMIT,
  PROFILE_VIDEO_LIMIT,
  removeProfileMedia
} from "@/lib/profile-media";
import { withSerializableTransactionRetry } from "@/lib/prisma-transaction";
import { uploadProfileMedia } from "@/lib/uploads";

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

    const updated = await withSerializableTransactionRetry(async (transaction) => {
      const current = await transaction.user.findUnique({
        where: { id: user.id },
        select: { avatarUrl: true, profilePhotoUrls: true, profileVideoUrls: true }
      });

      if (!current) {
        return null;
      }

      const profilePhotoUrls = normalizeProfileMediaList(current.profilePhotoUrls, PROFILE_PHOTO_LIMIT);
      const profileVideoUrls = normalizeProfileMediaList(current.profileVideoUrls, PROFILE_VIDEO_LIMIT);

      if (mediaType === "photo") {
        if (profilePhotoUrls.length >= PROFILE_PHOTO_LIMIT) {
          throw new Error("Можно добавить до 6 фото в карточку");
        }
        profilePhotoUrls.push(url);
      } else {
        if (profileVideoUrls.length >= PROFILE_VIDEO_LIMIT) {
          throw new Error("Можно добавить до 4 видео в карточку");
        }
        profileVideoUrls.push(url);
      }

      const nextProfilePhotoUrls = normalizeProfileMediaList(profilePhotoUrls, PROFILE_PHOTO_LIMIT);
      const nextProfileVideoUrls = normalizeProfileMediaList(profileVideoUrls, PROFILE_VIDEO_LIMIT);
      const nextAvatarUrl = mediaType === "photo" ? nextProfilePhotoUrls[0] : current.avatarUrl;

      return transaction.user.update({
        where: { id: user.id },
        data: {
          avatarUrl: nextAvatarUrl,
          profilePhotoUrls: nextProfilePhotoUrls as Prisma.InputJsonValue,
          profileVideoUrls: nextProfileVideoUrls as Prisma.InputJsonValue
        },
        select: { avatarUrl: true, profilePhotoUrls: true, profileVideoUrls: true }
      });
    });

    if (!updated) {
      return fail("Пользователь не найден", 404);
    }

    return ok({
      mediaUrl: url,
      mediaType,
      avatarUrl: updated.avatarUrl,
      profilePhotoUrls: normalizeProfileMediaList(updated.profilePhotoUrls, PROFILE_PHOTO_LIMIT),
      profileVideoUrls: normalizeProfileMediaList(updated.profileVideoUrls, PROFILE_VIDEO_LIMIT)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

export async function DELETE(request: Request) {
  try {
    const user = await requireSessionUser();
    const body = (await request.json().catch(() => null)) as { mediaUrl?: unknown } | null;
    const mediaUrl = typeof body?.mediaUrl === "string" ? body.mediaUrl.trim() : "";

    if (!mediaUrl || mediaUrl.length > 600) {
      return fail("Некорректная ссылка на медиа");
    }

    const result = await withSerializableTransactionRetry(async (transaction) => {
      const current = await transaction.user.findUnique({
        where: { id: user.id },
        select: { avatarUrl: true, profilePhotoUrls: true, profileVideoUrls: true }
      });

      if (!current) {
        return null;
      }

      const removal = removeProfileMedia(current, mediaUrl);
      const updated = removal.removed
        ? await transaction.user.update({
            where: { id: user.id },
            data: {
              avatarUrl: removal.avatarUrl,
              profilePhotoUrls: removal.profilePhotoUrls as Prisma.InputJsonValue,
              profileVideoUrls: removal.profileVideoUrls as Prisma.InputJsonValue
            },
            select: { avatarUrl: true, profilePhotoUrls: true, profileVideoUrls: true }
          })
        : current;

      return { removal, updated };
    });

    if (!result) {
      return fail("Пользователь не найден", 404);
    }

    return ok({
      mediaUrl: result.removal.mediaUrl,
      mediaType: result.removal.mediaType,
      avatarUrl: result.updated.avatarUrl,
      profilePhotoUrls: normalizeProfileMediaList(result.updated.profilePhotoUrls, PROFILE_PHOTO_LIMIT),
      profileVideoUrls: normalizeProfileMediaList(result.updated.profileVideoUrls, PROFILE_VIDEO_LIMIT)
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
