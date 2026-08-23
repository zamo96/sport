import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import {
  MAX_CHAT_ATTACHMENTS,
  MAX_CHAT_IMAGE_BYTES,
  removeStoredChatImage,
  storeChatImage
} from "@/server/chat-media";
import {
  MAX_CHAT_UPLOAD_REQUEST_BYTES,
  parseChatMediaFiles
} from "@/server/chat-media-multipart";

const MAX_CHAT_UPLOADS_PER_HOUR = 40;
const MAX_UNCLAIMED_CHAT_MEDIA = 12;
const UNCLAIMED_CHAT_MEDIA_TTL_MS = 24 * 60 * 60 * 1000;

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const contentLength = Number(request.headers.get("content-length"));
    if (Number.isFinite(contentLength) && contentLength > MAX_CHAT_UPLOAD_REQUEST_BYTES) {
      return fail("Общий размер загрузки слишком большой", 413);
    }

    const files = await parseChatMediaFiles(request);

    if (!files.length) {
      return fail("Добавьте фото");
    }
    if (files.length > MAX_CHAT_ATTACHMENTS) {
      return fail(`Можно загрузить не больше ${MAX_CHAT_ATTACHMENTS} фото`);
    }

    await cleanupStaleAssets(user.id);

    const [recentUploadCount, unclaimedCount] = await Promise.all([
      prisma.chatMediaAsset.count({
        where: {
          uploaderUserId: user.id,
          createdAt: { gte: new Date(Date.now() - 60 * 60 * 1000) }
        }
      }),
      prisma.chatMediaAsset.count({
        where: {
          uploaderUserId: user.id,
          claimedAt: null
        }
      })
    ]);

    if (recentUploadCount + files.length > MAX_CHAT_UPLOADS_PER_HOUR) {
      return fail("Слишком много загрузок. Попробуйте позже", 429);
    }
    if (unclaimedCount + files.length > MAX_UNCLAIMED_CHAT_MEDIA) {
      return fail("Сначала отправьте или отмените ранее загруженные фото", 429);
    }

    const assets: Array<{
      id: string;
      kind: "image";
      url: string;
      mimeType: string;
      byteSize: number;
      position: number;
      storageKey: string;
    }> = [];
    const uploadedStorageKeys: string[] = [];

    try {
      for (const file of files) {
        if (file.size > MAX_CHAT_IMAGE_BYTES) {
          throw new Error("Фото должно быть не больше 5 МБ");
        }

        const stored = await storeChatImage({
          bytes: file.bytes,
          uploaderUserId: user.id,
          declaredMimeType: file.type
        });
        uploadedStorageKeys.push(stored.storageKey);

        const asset = await prisma.chatMediaAsset.create({
          data: {
            uploaderUserId: user.id,
            storageKey: stored.storageKey,
            mimeType: stored.mimeType,
            byteSize: stored.byteSize,
            originalName: file.name.slice(0, 255) || null
          }
        });

        assets.push({
          id: asset.id,
          kind: "image" as const,
          url: `/chat-media/${asset.id}`,
          mimeType: asset.mimeType,
          byteSize: asset.byteSize,
          position: 0,
          storageKey: stored.storageKey
        });
      }
    } catch (error) {
      await Promise.all(uploadedStorageKeys.map(removeStoredChatImage));
      if (assets.length) {
        await prisma.chatMediaAsset.deleteMany({
          where: { id: { in: assets.map((asset) => asset.id) } }
        });
      }
      throw error;
    }

    return ok(
      {
        asset: assets.length === 1 ? toPublicAsset(assets[0]) : undefined,
        assets: assets.map(toPublicAsset)
      },
      { status: 201 }
    );
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}

function toPublicAsset(asset: {
  id: string;
  kind: "image";
  url: string;
  mimeType: string;
  byteSize: number;
  position: number;
}) {
  return {
    id: asset.id,
    kind: asset.kind,
    url: asset.url,
    mimeType: asset.mimeType,
    byteSize: asset.byteSize,
    position: asset.position
  };
}

async function cleanupStaleAssets(userId: string) {
  const staleAssets = await prisma.chatMediaAsset.findMany({
    where: {
      uploaderUserId: userId,
      OR: [
        {
          claimedAt: null,
          createdAt: { lt: new Date(Date.now() - UNCLAIMED_CHAT_MEDIA_TTL_MS) }
        },
        {
          claimedAt: { not: null },
          chatMessageMedia: null,
          searchMessageMedia: null
        }
      ]
    },
    select: {
      id: true,
      storageKey: true
    }
  });

  if (!staleAssets.length) {
    return;
  }

  await Promise.all(staleAssets.map((asset) => removeStoredChatImage(asset.storageKey)));
  await prisma.chatMediaAsset.deleteMany({
    where: {
      id: { in: staleAssets.map((asset) => asset.id) }
    }
  });
}
