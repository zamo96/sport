import { randomUUID } from "crypto";
import { mkdir, writeFile } from "fs/promises";
import path from "path";

import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

type UploadAvatarInput = {
  bytes: Buffer;
  originalName: string;
  contentType?: string;
  userId: string;
};

const MAX_AVATAR_BYTES = 5 * 1024 * 1024;
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

function validateAvatar(bytes: Buffer, contentType?: string) {
  if (bytes.length === 0) {
    throw new Error("Файл пустой");
  }

  if (bytes.length > MAX_AVATAR_BYTES) {
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

  if (publicBaseUrl) {
    return `${publicBaseUrl.replace(/\/$/, "")}/${key}`;
  }

  const endpoint = (process.env.S3_ENDPOINT?.trim() || "https://storage.yandexcloud.net").replace(/\/$/, "");
  return `${endpoint}/${bucket}/${key}`;
}

async function uploadAvatarToS3({ bytes, originalName, contentType, userId }: UploadAvatarInput) {
  const bucket = requiredEnv("S3_BUCKET");
  const extension = sanitizeExtension(originalName, contentType);
  const key = `avatars/${userId}/${randomUUID()}.${extension}`;

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

async function uploadAvatarLocally({ bytes, originalName, contentType }: UploadAvatarInput) {
  const extension = sanitizeExtension(originalName, contentType);
  const uploadsDir = path.join(process.cwd(), "public", "uploads");
  const fileName = `${randomUUID()}.${extension}`;
  const filePath = path.join(uploadsDir, fileName);

  await mkdir(uploadsDir, { recursive: true });
  await writeFile(filePath, bytes);

  return `/uploads/${fileName}`;
}

export async function uploadAvatar(input: UploadAvatarInput) {
  validateAvatar(input.bytes, input.contentType);

  if (resolveUploadsProvider() === "s3") {
    return uploadAvatarToS3(input);
  }

  return uploadAvatarLocally(input);
}
