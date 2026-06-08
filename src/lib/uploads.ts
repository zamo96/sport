import { randomUUID } from "crypto";
import { mkdir, writeFile } from "fs/promises";
import path from "path";

import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

type UploadImageInput = {
  bytes: Buffer;
  originalName: string;
  contentType?: string;
};

type UploadAvatarInput = UploadImageInput & {
  userId: string;
};

type UploadCourtPhotoInput = UploadImageInput & {
  courtId?: string;
  objectKey?: string;
};

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ALLOWED_CONTENT_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

let s3Client: S3Client | null = null;

function requiredEnv(name: string) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required env: ${name}`);
  }
  return value;
}

function resolveUploadsProvider() {
  return process.env.UPLOADS_PROVIDER?.trim() || "local";
}

function sanitizeExtension(originalName: string, contentType?: string) {
  const rawExtension = originalName.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (rawExtension && ["jpg", "jpeg", "png", "webp", "gif"].includes(rawExtension)) {
    return rawExtension === "jpeg" ? "jpg" : rawExtension;
  }

  switch (contentType) {
    case "image/jpeg":
      return "jpg";
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    case "image/gif":
      return "gif";
    default:
      return "png";
  }
}

function validateImage(bytes: Buffer, contentType?: string) {
  if (bytes.length === 0) {
    throw new Error("Файл пустой");
  }

  if (bytes.length > MAX_IMAGE_BYTES) {
    throw new Error("Фото должно быть не больше 5 МБ");
  }

  if (contentType && !ALLOWED_CONTENT_TYPES.has(contentType)) {
    throw new Error("Поддерживаются только JPG, PNG, WEBP или GIF");
  }
}

function getS3Client() {
  if (s3Client) {
    return s3Client;
  }

  s3Client = new S3Client({
    endpoint: process.env.S3_ENDPOINT?.trim() || "https://storage.yandexcloud.net",
    region: process.env.S3_REGION?.trim() || "ru-central1",
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE !== "false",
    credentials: {
      accessKeyId: requiredEnv("S3_ACCESS_KEY_ID"),
      secretAccessKey: requiredEnv("S3_SECRET_ACCESS_KEY")
    }
  });

  return s3Client;
}

function buildPublicObjectUrl(bucket: string, key: string) {
  const publicBaseUrl = process.env.S3_PUBLIC_BASE_URL?.trim();
  const encodedKey = encodeObjectKeyForUrl(key);

  if (publicBaseUrl) {
    return `${publicBaseUrl.replace(/\/$/, "")}/${encodedKey}`;
  }

  const endpoint = (process.env.S3_ENDPOINT?.trim() || "https://storage.yandexcloud.net").replace(/\/$/, "");
  return `${endpoint}/${bucket}/${encodedKey}`;
}

function encodeObjectKeyForUrl(key: string) {
  return key
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

function sanitizeObjectKey(value: string) {
  const key = value.trim().replace(/^\/+/, "").replace(/\\/g, "/");

  if (!key || key.includes("..") || key.endsWith("/")) {
    throw new Error("Некорректный S3 ключ для фото");
  }

  return key;
}

async function uploadImageToS3({
  bytes,
  originalName,
  contentType,
  keyPrefix,
  objectKey
}: UploadImageInput & { keyPrefix: string; objectKey?: string }) {
  const bucket = requiredEnv("S3_BUCKET");
  const extension = sanitizeExtension(originalName, contentType);
  const key = objectKey
    ? sanitizeObjectKey(objectKey)
    : `${keyPrefix.replace(/^\/+|\/+$/g, "")}/${randomUUID()}.${extension}`;

  await getS3Client().send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: bytes,
      ContentType: contentType || "application/octet-stream",
      CacheControl: "public, max-age=31536000, immutable"
    })
  );

  return buildPublicObjectUrl(bucket, key);
}

async function uploadImageLocally({
  bytes,
  originalName,
  contentType,
  objectKey
}: UploadImageInput & { objectKey?: string }) {
  const extension = sanitizeExtension(originalName, contentType);
  const uploadsDir = path.join(process.cwd(), "public", "uploads");
  const fileName = objectKey ? sanitizeObjectKey(objectKey) : `${randomUUID()}.${extension}`;
  const filePath = path.join(uploadsDir, fileName);

  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, bytes);

  return `/uploads/${fileName}`;
}

export async function uploadAvatar(input: UploadAvatarInput) {
  validateImage(input.bytes, input.contentType);

  if (resolveUploadsProvider() === "s3") {
    return uploadImageToS3({ ...input, keyPrefix: `avatars/${input.userId}` });
  }

  return uploadImageLocally(input);
}

export async function uploadCourtPhoto(input: UploadCourtPhotoInput) {
  validateImage(input.bytes, input.contentType);

  const keyPrefix = input.courtId ? `courts/${input.courtId}` : "courts/import";

  if (resolveUploadsProvider() === "s3") {
    return uploadImageToS3({ ...input, keyPrefix });
  }

  return uploadImageLocally(input);
}

export function resolveUploadedObjectUrl(objectKey: string) {
  if (resolveUploadsProvider() === "s3") {
    return buildPublicObjectUrl(requiredEnv("S3_BUCKET"), sanitizeObjectKey(objectKey));
  }

  return `/uploads/${sanitizeObjectKey(objectKey)}`;
}
