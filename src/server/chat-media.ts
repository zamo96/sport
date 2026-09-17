import { randomUUID } from "crypto";
import { mkdir, readFile, unlink, writeFile } from "fs/promises";
import path from "path";

import { DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { Prisma, PrismaClient } from "@prisma/client";
import sharp from "sharp";

import { IMAGE_SIZE_ERROR, MAX_IMAGE_BYTES, NORMALIZED_IMAGE_SIZE_ERROR } from "@/lib/upload-limits";
import { summarizeChatReceipts } from "@/lib/chat-receipts";

export const MAX_CHAT_ATTACHMENTS = 4;
export const MAX_CHAT_IMAGE_BYTES = MAX_IMAGE_BYTES;
export const MAX_CHAT_IMAGE_PIXELS = 40_000_000;

const CHAT_MEDIA_PREFIX = "chat-media";

type SupportedImage = {
  mimeType: "image/jpeg" | "image/png" | "image/webp" | "image/gif";
  extension: "jpg" | "png" | "webp" | "gif";
};

type ChatMediaTransaction = Omit<
  PrismaClient,
  "$connect" | "$disconnect" | "$on" | "$transaction" | "$use" | "$extends"
>;

type MessageWithAttachments = {
  id: string;
  createdAt: Date;
  text: string;
  receipts?: Array<{ readAt: Date | null }>;
  attachments: Array<{
    position: number;
    asset: {
      id: string;
      mimeType: string;
      byteSize: number;
    };
  }>;
};

let privateS3Client: S3Client | null = null;

export const chatMessageAttachmentsInclude = {
  receipts: { select: { readAt: true } },
  attachments: {
    include: {
      asset: true
    },
    orderBy: {
      position: "asc"
    }
  }
} satisfies Prisma.ChatMessageInclude;

export const gameSearchMessageAttachmentsInclude = {
  receipts: { select: { readAt: true } },
  attachments: {
    include: {
      asset: true
    },
    orderBy: {
      position: "asc"
    }
  }
} satisfies Prisma.GameSearchMessageInclude;

function requiredEnv(name: string) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required env: ${name}`);
  }
  return value;
}

function usesS3() {
  return (process.env.UPLOADS_PROVIDER?.trim() || "local") === "s3";
}

function getPrivateS3Client() {
  if (privateS3Client) {
    return privateS3Client;
  }

  privateS3Client = new S3Client({
    endpoint: process.env.S3_ENDPOINT?.trim() || "https://storage.yandexcloud.net",
    region: process.env.S3_REGION?.trim() || "ru-central1",
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE !== "false",
    credentials: {
      accessKeyId: requiredEnv("S3_ACCESS_KEY_ID"),
      secretAccessKey: requiredEnv("S3_SECRET_ACCESS_KEY")
    }
  });

  return privateS3Client;
}

function localChatMediaRoot() {
  const configured = process.env.CHAT_MEDIA_LOCAL_DIR?.trim();
  return configured ? path.resolve(configured) : path.join(process.cwd(), ".data", CHAT_MEDIA_PREFIX);
}

function safeLocalPath(storageKey: string) {
  if (!storageKey.startsWith(`${CHAT_MEDIA_PREFIX}/`) || storageKey.includes("..") || storageKey.includes("\\")) {
    throw new Error("Некорректный ключ медиа");
  }

  const relativeKey = storageKey.slice(CHAT_MEDIA_PREFIX.length + 1);
  return path.join(localChatMediaRoot(), relativeKey);
}

export function detectChatImage(bytes: Buffer): SupportedImage {
  if (bytes.length === 0) {
    throw new Error("Файл пустой");
  }
  if (bytes.length > MAX_CHAT_IMAGE_BYTES) {
    throw new Error(IMAGE_SIZE_ERROR);
  }

  if (
    bytes.length >= 5 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff &&
    bytes[bytes.length - 2] === 0xff &&
    bytes[bytes.length - 1] === 0xd9
  ) {
    return { mimeType: "image/jpeg", extension: "jpg" };
  }
  if (
    bytes.length >= 20 &&
    bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) &&
    bytes.subarray(bytes.length - 12, bytes.length - 8).equals(Buffer.alloc(4)) &&
    bytes.subarray(bytes.length - 8, bytes.length - 4).toString("ascii") === "IEND"
  ) {
    return { mimeType: "image/png", extension: "png" };
  }
  if (
    bytes.length >= 12 &&
    bytes.subarray(0, 4).toString("ascii") === "RIFF" &&
    bytes.subarray(8, 12).toString("ascii") === "WEBP" &&
    bytes.readUInt32LE(4) + 8 === bytes.length
  ) {
    return { mimeType: "image/webp", extension: "webp" };
  }
  if (
    bytes.length >= 7 &&
    ["GIF87a", "GIF89a"].includes(bytes.subarray(0, 6).toString("ascii")) &&
    bytes[bytes.length - 1] === 0x3b
  ) {
    return { mimeType: "image/gif", extension: "gif" };
  }

  throw new Error("Поддерживаются только JPG, PNG, WEBP или GIF");
}

export async function storeChatImage(input: {
  bytes: Buffer;
  uploaderUserId: string;
  declaredMimeType?: string;
}) {
  const normalized = await normalizeChatImage(input.bytes);
  const detected = normalized.image;
  if (
    input.declaredMimeType &&
    input.declaredMimeType !== "application/octet-stream" &&
    input.declaredMimeType !== detected.mimeType
  ) {
    throw new Error("Тип файла не соответствует содержимому");
  }

  const storageKey = `${CHAT_MEDIA_PREFIX}/${input.uploaderUserId}/${randomUUID()}.${detected.extension}`;

  if (usesS3()) {
    await getPrivateS3Client().send(
      new PutObjectCommand({
        Bucket: requiredEnv("S3_BUCKET"),
        Key: storageKey,
        Body: normalized.bytes,
        ContentType: detected.mimeType,
        CacheControl: "private, no-store"
      })
    );
  } else {
    const filePath = safeLocalPath(storageKey);
    await mkdir(path.dirname(filePath), { recursive: true });
    await writeFile(filePath, normalized.bytes, { flag: "wx" });
  }

  return {
    storageKey,
    mimeType: detected.mimeType,
    byteSize: normalized.bytes.length
  };
}

export async function normalizeChatImage(bytes: Buffer) {
  const image = detectChatImage(bytes);

  try {
    const processor = sharp(bytes, {
      animated: image.mimeType === "image/gif",
      failOn: "error",
      limitInputPixels: MAX_CHAT_IMAGE_PIXELS
    });
    const metadata = await processor.metadata();
    const width = metadata.width ?? 0;
    const height = metadata.height ?? 0;
    const pages = metadata.pages ?? 1;

    if (!width || !height || width * height * pages > MAX_CHAT_IMAGE_PIXELS) {
      throw new Error("Слишком большое разрешение фото");
    }

    const oriented = processor.rotate();
    let normalizedBytes: Buffer;
    switch (image.mimeType) {
      case "image/jpeg":
        normalizedBytes = await oriented.jpeg({ quality: 90, mozjpeg: true }).toBuffer();
        break;
      case "image/png":
        normalizedBytes = await oriented.png({ compressionLevel: 9 }).toBuffer();
        break;
      case "image/webp":
        normalizedBytes = await oriented.webp({ quality: 90 }).toBuffer();
        break;
      case "image/gif":
        normalizedBytes = await oriented.gif().toBuffer();
        break;
    }

    if (normalizedBytes.length > MAX_CHAT_IMAGE_BYTES) {
      throw new Error(NORMALIZED_IMAGE_SIZE_ERROR);
    }

    return { bytes: normalizedBytes, image };
  } catch (error) {
    if (error instanceof Error && (error.message.includes("разрешение") || error.message === NORMALIZED_IMAGE_SIZE_ERROR)) {
      throw error;
    }
    throw new Error("Не удалось безопасно обработать фото");
  }
}

export async function readChatImage(storageKey: string) {
  if (usesS3()) {
    const result = await getPrivateS3Client().send(
      new GetObjectCommand({
        Bucket: requiredEnv("S3_BUCKET"),
        Key: storageKey
      })
    );
    if (!result.Body) {
      throw new Error("Медиа не найдено");
    }
    return Buffer.from(await result.Body.transformToByteArray());
  }

  return readFile(safeLocalPath(storageKey));
}

export async function removeStoredChatImage(storageKey: string) {
  if (usesS3()) {
    await getPrivateS3Client()
      .send(
        new DeleteObjectCommand({
          Bucket: requiredEnv("S3_BUCKET"),
          Key: storageKey
        })
      )
      .catch(() => undefined);
    return;
  }

  await unlink(safeLocalPath(storageKey)).catch(() => undefined);
}

export function serializeChatAttachment(
  attachment: MessageWithAttachments["attachments"][number]
) {
  return {
    id: attachment.asset.id,
    kind: "image" as const,
    url: `/chat-media/${attachment.asset.id}`,
    mimeType: attachment.asset.mimeType,
    byteSize: attachment.asset.byteSize,
    position: attachment.position
  };
}

export function serializeChatMessage<T extends MessageWithAttachments>(message: T) {
  const { receipts, ...publicMessage } = message;
  return {
    ...publicMessage,
    ...(receipts ? { receipt: summarizeChatReceipts(receipts) } : {}),
    attachments: message.attachments.map(serializeChatAttachment),
    createdAt: message.createdAt.toISOString()
  };
}

export function chatMessagePreview(message: { text: string; attachments: Array<unknown> }) {
  const text = message.text.trim();
  if (text) {
    return text.length > 120 ? `${text.slice(0, 117)}...` : text;
  }
  return message.attachments.length > 1 ? `📷 ${message.attachments.length} фото` : "📷 Фото";
}

export function normalizeAttachmentIds(attachmentIds: string[]) {
  return Array.from(new Set(attachmentIds));
}

export async function claimChatMessageAttachments(
  tx: ChatMediaTransaction,
  input: {
    attachmentIds: string[];
    uploaderUserId: string;
    chatMessageId: string;
  }
) {
  if (!input.attachmentIds.length) {
    return;
  }

  const claimedAt = new Date();
  const claimed = await tx.chatMediaAsset.updateMany({
    where: {
      id: { in: input.attachmentIds },
      uploaderUserId: input.uploaderUserId,
      claimedAt: null
    },
    data: { claimedAt }
  });

  if (claimed.count !== input.attachmentIds.length) {
    throw new Error("Одно или несколько вложений недоступны");
  }

  await tx.chatMessageMedia.createMany({
    data: input.attachmentIds.map((assetId, position) => ({
      chatMessageId: input.chatMessageId,
      assetId,
      position
    }))
  });
}

export async function claimGameSearchMessageAttachments(
  tx: ChatMediaTransaction,
  input: {
    attachmentIds: string[];
    uploaderUserId: string;
    gameSearchMessageId: string;
  }
) {
  if (!input.attachmentIds.length) {
    return;
  }

  const claimedAt = new Date();
  const claimed = await tx.chatMediaAsset.updateMany({
    where: {
      id: { in: input.attachmentIds },
      uploaderUserId: input.uploaderUserId,
      claimedAt: null
    },
    data: { claimedAt }
  });

  if (claimed.count !== input.attachmentIds.length) {
    throw new Error("Одно или несколько вложений недоступны");
  }

  await tx.gameSearchMessageMedia.createMany({
    data: input.attachmentIds.map((assetId, position) => ({
      gameSearchMessageId: input.gameSearchMessageId,
      assetId,
      position
    }))
  });
}
