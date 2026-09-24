import { randomUUID } from "crypto";
import { mkdir, writeFile } from "fs/promises";
import path from "path";

import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

import { IMAGE_SIZE_ERROR, MAX_IMAGE_BYTES } from "@/lib/upload-limits";
import { validatePersonalActivityVideo } from "@/lib/personal-activity-media";

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

type UploadGameReportPhotoInput = UploadImageInput & {
  gameRequestId: string;
  userId: string;
};

type UploadPersonalActivityPhotoInput = UploadImageInput & {
  activityId: string;
  userId: string;
};

type UploadProfileMediaInput = UploadImageInput & {
  userId: string;
};


const MAX_VIDEO_BYTES = 60 * 1024 * 1024;
const ALLOWED_CONTENT_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const ALLOWED_VIDEO_CONTENT_TYPES = new Set(["video/mp4", "video/quicktime", "video/mpeg"]);

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

function sanitizeProfileMediaExtension(originalName: string, contentType?: string) {
  const rawExtension = originalName.split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (rawExtension && ["jpg", "jpeg", "png", "webp", "gif", "mp4", "mov", "mpeg", "mpg"].includes(rawExtension)) {
    if (rawExtension === "jpeg") {
      return "jpg";
    }
    if (rawExtension === "mpg") {
      return "mpeg";
    }
    return rawExtension;
  }

  switch (contentType) {
    case "video/mp4":
      return "mp4";
    case "video/quicktime":
      return "mov";
    case "video/mpeg":
      return "mpeg";
    default:
      return sanitizeExtension(originalName, contentType);
  }
}

function inferProfileMediaType(originalName: string, contentType?: string): "photo" | "video" {
  if (contentType?.startsWith("video/")) {
    return "video";
  }

  const extension = originalName.split(".").pop()?.toLowerCase();
  if (extension && ["mp4", "mov", "mpeg", "mpg"].includes(extension)) {
    return "video";
  }

  return "photo";
}

function validateImage(bytes: Buffer, contentType?: string) {
  if (bytes.length === 0) {
    throw new Error("Файл пустой");
  }

  if (bytes.length > MAX_IMAGE_BYTES) {
    throw new Error(IMAGE_SIZE_ERROR);
  }

  if (contentType && !ALLOWED_CONTENT_TYPES.has(contentType)) {
    throw new Error("Поддерживаются только JPG, PNG, WEBP или GIF");
  }
}

function validateProfileMedia(bytes: Buffer, originalName: string, contentType?: string) {
  const mediaType = inferProfileMediaType(originalName, contentType);

  if (mediaType === "photo") {
    validateImage(bytes, contentType);
    return mediaType;
  }

  if (bytes.length === 0) {
    throw new Error("Файл пустой");
  }

  if (bytes.length > MAX_VIDEO_BYTES) {
    throw new Error("Видео должно быть не больше 60 МБ");
  }

  if (contentType && !ALLOWED_VIDEO_CONTENT_TYPES.has(contentType)) {
    throw new Error("Поддерживаются только MP4, MOV или MPEG");
  }

  return mediaType;
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

async function uploadProfileMediaToS3({
  bytes,
  originalName,
  contentType,
  keyPrefix
}: UploadImageInput & { keyPrefix: string }) {
  const bucket = requiredEnv("S3_BUCKET");
  const extension = sanitizeProfileMediaExtension(originalName, contentType);
  const key = `${keyPrefix.replace(/^\/+|\/+$/g, "")}/${randomUUID()}.${extension}`;

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

async function uploadProfileMediaLocally({
  bytes,
  originalName,
  contentType,
  objectKey
}: UploadImageInput & { objectKey: string }) {
  const extension = sanitizeProfileMediaExtension(originalName, contentType);
  const uploadsDir = path.join(process.cwd(), "public", "uploads");
  const filePath = path.join(uploadsDir, `${objectKey}.${extension}`);

  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, bytes);

  return `/uploads/${objectKey}.${extension}`;
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

export async function uploadGameReportPhoto(input: UploadGameReportPhotoInput) {
  validateImage(input.bytes, input.contentType);

  const keyPrefix = `game-reports/${input.gameRequestId}/${input.userId}`;

  if (resolveUploadsProvider() === "s3") {
    return uploadImageToS3({ ...input, keyPrefix });
  }

  return uploadImageLocally({ ...input, objectKey: `${keyPrefix}/${randomUUID()}.${sanitizeExtension(input.originalName, input.contentType)}` });
}

export async function uploadPersonalActivityPhoto(input: UploadPersonalActivityPhotoInput) {
  validateImage(input.bytes, input.contentType);

  const keyPrefix = `personal-activities/${input.activityId}/${input.userId}`;

  if (resolveUploadsProvider() === "s3") {
    return uploadImageToS3({ ...input, keyPrefix });
  }

  return uploadImageLocally({ ...input, objectKey: `${keyPrefix}/${randomUUID()}.${sanitizeExtension(input.originalName, input.contentType)}` });
}

export async function uploadPersonalActivityVideo(input: UploadPersonalActivityPhotoInput) {
  validatePersonalActivityVideo(input.bytes, input.contentType);
  const extension = input.contentType === "video/quicktime" ? "mov" : "mp4";
  const normalized = { ...input, originalName: `video.${extension}` };
  const keyPrefix = `personal-activities/${input.activityId}/${input.userId}`;
  return resolveUploadsProvider() === "s3"
    ? uploadProfileMediaToS3({ ...normalized, keyPrefix })
    : uploadProfileMediaLocally({ ...normalized, objectKey: `${keyPrefix}/${randomUUID()}` });
}

/** Only attach video URLs produced for this owner's exact visit. */
export function isOwnedPersonalActivityVideoUrl(url: string, activityId: string, userId: string) {
  const marker = "__personal_activity_video__";
  const prefix = resolveUploadedObjectUrl(`personal-activities/${activityId}/${userId}/${marker}`).slice(0, -marker.length);
  if (!url.startsWith(prefix)) return false;
  return /^[a-f0-9-]+\.(mp4|mov)$/.test(url.slice(prefix.length));
}

export async function uploadProfileMedia(input: UploadProfileMediaInput) {
  const mediaType = validateProfileMedia(input.bytes, input.originalName, input.contentType);
  const keyPrefix = `profile-media/${input.userId}/${mediaType}s`;

  const url =
    resolveUploadsProvider() === "s3"
      ? await uploadProfileMediaToS3({ ...input, keyPrefix })
      : await uploadProfileMediaLocally({ ...input, objectKey: `${keyPrefix}/${randomUUID()}` });

  return { mediaType, url };
}

export function resolveUploadedObjectUrl(objectKey: string) {
  if (resolveUploadsProvider() === "s3") {
    return buildPublicObjectUrl(requiredEnv("S3_BUCKET"), sanitizeObjectKey(objectKey));
  }

  return `/uploads/${sanitizeObjectKey(objectKey)}`;
}
