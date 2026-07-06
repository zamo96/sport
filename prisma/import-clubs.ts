import { access, readFile } from "node:fs/promises";
import path from "node:path";

import { Sport } from "@prisma/client";
import * as XLSX from "xlsx";

import { DEFAULT_CITY } from "@/lib/constants";
import { prisma } from "@/lib/prisma";
import { resolveUploadedObjectUrl, uploadCourtPhoto } from "@/lib/uploads";
import { syncClubRecords } from "@/server/club-sync";

type ClubRow = {
  name?: string;
  address?: string;
  city?: string;
  sports?: string;
  phone?: string;
  working_hours?: string;
  yandex_maps_url?: string;
  website_url?: string;
  booking_url?: string;
  booking_form_url?: string;
  online_booking_url?: string;
  about?: string;
  about_club?: string;
  description?: string;
  amenities?: string;
  amenity?: string;
  facilities?: string;
  messenger_type?: string;
  messenger?: string;
  messenger_url?: string;
  telegram_url?: string;
  max_url?: string;
  photo_url?: string;
  photo_file?: string;
  photo_path?: string;
  photo_s3_key?: string;
  metro?: string;
  metros?: string;
  district?: string;
  district_label?: string;
  lat?: number | string;
  lng?: number | string;
  [key: string]: unknown;
};

type CsvRow = Record<string, string>;

const DISTRICTS_REFERENCE_PATH = path.join(process.cwd(), "docs/import/districts-reference.csv");
const METROS_REFERENCE_PATH = path.join(process.cwd(), "docs/import/metros-spb.reference.csv");
const DEFAULT_CLUBS_XLSX_PATH = path.join(process.cwd(), "docs/import/clubs.xlsx");
const IMPORT_SOURCE_TYPE = "xlsx-import";
const MAX_COURT_PHOTOS = 8;
const MAX_COURT_AMENITIES = 12;
const VALID_SPORTS = new Set(Object.values(Sport));

const SPORT_ALIASES: Record<string, Sport> = {
  table_tennis: Sport.table_tennis,
  "table tennis": Sport.table_tennis,
  "настольный теннис": Sport.table_tennis,
  tennis: Sport.tennis,
  "большой теннис": Sport.tennis,
  padel: Sport.padel,
  падел: Sport.padel,
  squash: Sport.squash,
  сквош: Sport.squash,
  badminton: Sport.badminton,
  бадминтон: Sport.badminton,
  volleyball: Sport.volleyball,
  волейбол: Sport.volleyball,
  fitness: Sport.fitness,
  фитнесс: Sport.fitness,
  фитнес: Sport.fitness,
  "спортзал": Sport.fitness,
  boxing: Sport.boxing,
  бокс: Sport.boxing,
  yoga: Sport.yoga,
  йога: Sport.yoga,
  football: Sport.football,
  футбол: Sport.football,
  running: Sport.running,
  run: Sport.running,
  бег: Sport.running,
  пробежка: Sport.running,
  supboard: Sport.supboard,
  sup: Sport.supboard,
  сапборд: Sport.supboard,
  "сап борд": Sport.supboard
};

export async function importClubsFromWorkbook(filePath: string) {
  const districtsReference = await loadReferenceRows(DISTRICTS_REFERENCE_PATH);
  const metrosReference = await loadReferenceRows(METROS_REFERENCE_PATH);

  const workbook = XLSX.readFile(filePath);
  const firstSheetName = workbook.SheetNames[0];

  if (!firstSheetName) {
    throw new Error("В файле нет листов для импорта");
  }

  const firstSheet = workbook.Sheets[firstSheetName];
  const rawRows = XLSX.utils.sheet_to_json<ClubRow>(firstSheet, {
    defval: "",
    raw: false
  });

  const rows = rawRows
    .map(normalizeRow)
    .filter((row): row is NormalizedClubRow => row !== null);

  const districtNameByCode = new Map(districtsReference.map((row) => [row.code, row.label]));
  const districtRows = Array.from(
    new Map(
      rows
        .filter((row) => row.district)
        .map((row) => [
          row.district as string,
          {
            code: row.district as string,
            name: row.districtLabel || districtNameByCode.get(row.district as string) || row.district as string,
            city: row.city
          }
        ])
    ).values()
  );

  const metroRows = Array.from(
    new Map(
      [
        ...metrosReference.map((row) => ({ name: row.name, city: DEFAULT_CITY })),
        ...rows
          .flatMap((row) => row.metros.map((metro) => ({ name: metro, city: row.city })))
      ].map((metro) => [metro.name.toLowerCase(), metro])
    ).values()
  );

  await prisma.district.createMany({
    data: districtRows,
    skipDuplicates: true
  });

  await prisma.metro.createMany({
    data: metroRows,
    skipDuplicates: true
  });

  const dedupedRows = Array.from(
    new Map(
      rows.map((row) => [
        courtImportKey(row),
        row
      ])
    ).values()
  );
  const rowsWithPhotos = await Promise.all(
    dedupedRows.map((row) => resolveImportedPhotos(row, path.dirname(filePath)))
  );

  const summary = await syncClubRecords(
    rowsWithPhotos.map((row) => ({
      sourceType: IMPORT_SOURCE_TYPE,
      sourceExternalId: courtImportKey(row),
      sourceUrl: row.yandexMapsUrl ?? row.websiteUrl,
      name: row.name,
      address: row.address,
      city: row.city,
      district: row.district,
      sports: row.sports,
      phone: row.phone,
      workingHours: row.workingHours,
      yandexMapsUrl: row.yandexMapsUrl,
      websiteUrl: row.websiteUrl,
      bookingUrl: row.bookingUrl,
      about: row.about,
      amenities: row.amenities,
      messengerType: row.messengerType,
      messengerUrl: row.messengerUrl,
      photoUrl: row.photoUrl,
      photoUrls: row.photoUrls,
      metroNames: row.metros,
      locationLat: row.lat,
      locationLng: row.lng
    })),
    {
      city: DEFAULT_CITY,
      sourceType: IMPORT_SOURCE_TYPE,
      autoPublishNew: true,
      prisma
    }
  );

  const importedCount = await prisma.court.count({
    where: { sourceType: IMPORT_SOURCE_TYPE }
  });

  const groupedByDistrict = await prisma.court.groupBy({
    by: ["district"],
    where: { sourceType: IMPORT_SOURCE_TYPE },
    _count: {
      _all: true
    }
  });

  console.log(
    `Импорт завершен. Клубов в источнике: ${importedCount}. Создано: ${summary.createdCount}, обновлено: ${summary.updatedCount}, без изменений: ${summary.unchangedCount}`
  );
  console.log("По районам:");
  for (const row of groupedByDistrict.sort((left, right) => (right._count._all ?? 0) - (left._count._all ?? 0))) {
    console.log(`- ${row.district ?? "Без района"}: ${row._count._all}`);
  }
}

export async function resolveClubsImportFile(preferredPath?: string | null) {
  const candidates = [preferredPath?.trim() || "", DEFAULT_CLUBS_XLSX_PATH].filter(Boolean);

  for (const candidate of candidates) {
    try {
      await access(candidate);
      return candidate;
    } catch {
      continue;
    }
  }

  return null;
}

type NormalizedClubRow = {
  name: string;
  address: string;
  city: string;
  sports: Sport[];
  phone: string | null;
  workingHours: string | null;
  yandexMapsUrl: string | null;
  websiteUrl: string | null;
  bookingUrl: string | null;
  about: string | null;
  amenities: string[];
  messengerType: string | null;
  messengerUrl: string | null;
  photoUrl: string | null;
  photoUrls: string[];
  photoFiles: string[];
  photoS3Keys: string[];
  metros: string[];
  district: string | null;
  districtLabel: string | null;
  lat: number;
  lng: number;
};

function normalizeRow(row: ClubRow): NormalizedClubRow | null {
  const name = normalizeText(row.name);
  const address = normalizeAddress(row.address);
  const sports = normalizeSports(row.sports);
  const lat = parseCoordinate(row.lat);
  const lng = parseCoordinate(row.lng);
  const messenger = normalizeMessenger(row);

  if (!name || !address || sports.length === 0 || lat == null || lng == null) {
    return null;
  }

  return {
    name,
    address,
    city: normalizeText(row.city) ?? DEFAULT_CITY,
    sports,
    phone: normalizeText(row.phone),
    workingHours: normalizeText(row.working_hours),
    yandexMapsUrl: normalizeUrl(row.yandex_maps_url),
    websiteUrl: normalizeUrl(row.website_url),
    bookingUrl: normalizeFirstUrl(row, "booking_url", "booking_form_url", "online_booking_url", "бронь", "ссылка_брони"),
    about: normalizeFirstText(row, "about", "about_club", "description", "о_клубе"),
    amenities: normalizeAmenities(row),
    messengerType: messenger.type,
    messengerUrl: messenger.url,
    photoUrl: null,
    photoUrls: normalizeUrlValues(row, "photo_url", "photo_urls"),
    photoFiles: normalizeTextValues(row, "photo_file", "photo_files", "photo_path", "photo_paths"),
    photoS3Keys: normalizeS3KeyValues(row, "photo_s3_key", "photo_s3_keys"),
    metros: normalizeMetroValues(row),
    district: normalizeDistrictCode(row.district),
    districtLabel: normalizeText(row.district_label),
    lat,
    lng
  };
}

async function resolveImportedPhotos(row: NormalizedClubRow, workbookDir: string): Promise<NormalizedClubRow> {
  const photoUrls = [...row.photoUrls];

  for (const [index, photoFile] of row.photoFiles.entries()) {
    if (photoUrls.length >= MAX_COURT_PHOTOS) {
      break;
    }

    const filePath = resolveImportAssetPath(photoFile, workbookDir);
    const bytes = await readImportAsset(filePath);
    if (!bytes) {
      console.warn(`Фото пропущено: файл не найден ${filePath}`);
      continue;
    }
    const objectKey = row.photoS3Keys[index] ?? defaultCourtPhotoObjectKey(row, filePath, index);
    const photoUrl = await uploadCourtPhoto({
      bytes,
      originalName: path.basename(filePath),
      contentType: inferImageContentType(filePath),
      objectKey
    });

    photoUrls.push(photoUrl);
  }

  for (const s3Key of row.photoS3Keys) {
    if (photoUrls.length >= MAX_COURT_PHOTOS) {
      break;
    }

    photoUrls.push(resolveUploadedObjectUrl(s3Key));
  }

  const dedupedPhotoUrls = uniqueNonEmpty(photoUrls).slice(0, MAX_COURT_PHOTOS);

  return {
    ...row,
    photoUrl: dedupedPhotoUrls[0] ?? null,
    photoUrls: dedupedPhotoUrls
  };
}

async function readImportAsset(filePath: string) {
  try {
    return await readFile(filePath);
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
      return null;
    }

    throw error;
  }
}

function resolveImportAssetPath(value: string, workbookDir: string) {
  if (path.isAbsolute(value)) {
    return value;
  }

  return path.resolve(workbookDir, value);
}

function defaultCourtPhotoObjectKey(row: NormalizedClubRow, filePath: string, index: number) {
  const extension = path.extname(filePath).toLowerCase() || ".jpg";
  const suffix = index > 0 ? `-${index + 1}` : "";
  return `courts/import/${slugifyForObjectKey(row.name)}-${slugifyForObjectKey(row.address).slice(0, 36)}${suffix}${extension}`;
}

function slugifyForObjectKey(value: string) {
  return value
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-zа-яё0-9]+/gi, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "club";
}

function inferImageContentType(filePath: string) {
  switch (path.extname(filePath).toLowerCase()) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".png":
      return "image/png";
    case ".webp":
      return "image/webp";
    case ".gif":
      return "image/gif";
    default:
      return undefined;
  }
}

function normalizeText(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.replace(/\s+/g, " ").trim();
  return normalized.length > 0 ? normalized : null;
}

function normalizeUrl(value: unknown) {
  const text = normalizeText(value);
  return text && /^https?:\/\//i.test(text) ? text : null;
}

function normalizeUrlValues(row: ClubRow, singularKey: string, pluralKey: string) {
  return normalizeColumnValues(row, singularKey, pluralKey)
    .map(normalizeUrl)
    .filter((value): value is string => Boolean(value))
    .slice(0, MAX_COURT_PHOTOS);
}

function normalizeTextValues(row: ClubRow, singularKey: string, pluralKey: string, ...aliases: string[]) {
  return [singularKey, pluralKey, ...aliases]
    .flatMap((key) => normalizeColumnValues(row, key, key.endsWith("s") ? key : `${key}s`))
    .map(normalizeText)
    .filter((value): value is string => Boolean(value))
    .slice(0, MAX_COURT_PHOTOS);
}

function normalizeS3KeyValues(row: ClubRow, singularKey: string, pluralKey: string) {
  return normalizeColumnValues(row, singularKey, pluralKey)
    .map(normalizeS3Key)
    .filter((value): value is string => Boolean(value))
    .slice(0, MAX_COURT_PHOTOS);
}

function normalizeAmenities(row: ClubRow) {
  return uniqueNonEmpty([
    ...normalizeColumnValues(row, "amenity", "amenities"),
    ...normalizeColumnValues(row, "facility", "facilities"),
    ...splitCellValues(row["удобства"])
  ]).slice(0, MAX_COURT_AMENITIES);
}

function normalizeMetroValues(row: ClubRow) {
  return uniqueNonEmpty([
    ...normalizeColumnValues(row, "metro", "metros"),
    ...splitCellValues(row["метро"])
  ]);
}

function courtImportKey(row: Pick<NormalizedClubRow, "name" | "address" | "city">) {
  return `${row.name.toLowerCase()}::${row.address.toLowerCase()}::${row.city.toLowerCase()}`;
}

function normalizeFirstText(row: ClubRow, ...keys: string[]) {
  for (const key of keys) {
    const value = normalizeText(row[key]);
    if (value) {
      return value;
    }
  }

  return null;
}

function normalizeFirstUrl(row: ClubRow, ...keys: string[]) {
  for (const key of keys) {
    const value = normalizeUrl(row[key]);
    if (value) {
      return value;
    }
  }

  return null;
}

function normalizeColumnValues(row: ClubRow, singularKey: string, pluralKey: string) {
  const values: unknown[] = [
    row[singularKey],
    row[pluralKey],
    ...Array.from({ length: MAX_COURT_PHOTOS }, (_, index) => row[`${singularKey}_${index + 1}`])
  ];

  return uniqueNonEmpty(values.flatMap(splitCellValues));
}

function normalizeMessenger(row: ClubRow): { type: string | null; url: string | null } {
  const explicitUrl = normalizeUrl(row.messenger_url);
  const telegramUrl = normalizeUrl(row.telegram_url);
  const maxUrl = normalizeUrl(row.max_url);
  const url = explicitUrl ?? telegramUrl ?? maxUrl;

  if (!url) {
    return { type: null, url: null };
  }

  const explicitType = normalizeMessengerType(row.messenger_type ?? row.messenger);
  const inferredType =
    telegramUrl === url
      ? "telegram"
      : maxUrl === url
        ? "max"
        : inferMessengerType(url);

  return {
    type: explicitType ?? inferredType,
    url
  };
}

function normalizeMessengerType(value: unknown) {
  const text = normalizeText(value)?.toLowerCase();
  if (!text) {
    return null;
  }

  if (["telegram", "tg", "телеграм", "телеграмм"].includes(text)) {
    return "telegram";
  }

  if (["max", "макс", "мax"].includes(text)) {
    return "max";
  }

  return text.replace(/\s+/g, "_").slice(0, 32);
}

function inferMessengerType(url: string) {
  const normalized = url.toLowerCase();
  if (normalized.includes("t.me") || normalized.includes("telegram")) {
    return "telegram";
  }

  if (normalized.includes("max")) {
    return "max";
  }

  return "messenger";
}

function splitCellValues(value: unknown) {
  const text = normalizeText(value);
  if (!text) {
    return [];
  }

  return text
    .split(/[\n;,|]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function uniqueNonEmpty(values: string[]) {
  return values.reduce<string[]>((result, value) => {
    const normalized = value.trim();
    if (normalized && !result.includes(normalized)) {
      result.push(normalized);
    }
    return result;
  }, []);
}

function normalizeS3Key(value: unknown) {
  const text = normalizeText(value);
  if (!text) {
    return null;
  }

  const withoutScheme = text.replace(/^s3:\/\//i, "").replace(/^\/+/, "");
  const bucket = process.env.S3_BUCKET?.trim();

  if (bucket && withoutScheme.startsWith(`${bucket}/`)) {
    return withoutScheme.slice(bucket.length + 1);
  }

  return withoutScheme;
}

function normalizeAddress(value: unknown) {
  const text = normalizeText(value);

  if (!text) {
    return null;
  }

  return text.replace(/^Санкт-Петербург\s*;\s*/i, "");
}

function normalizeSports(value: unknown) {
  if (typeof value !== "string") {
    return [];
  }

  const sports = value
    .split("|")
    .map((item) => item.trim().toLowerCase())
    .map((item) => SPORT_ALIASES[item] ?? null)
    .filter((item): item is Sport => Boolean(item) && VALID_SPORTS.has(item));

  return Array.from(new Set(sports));
}

function normalizeDistrictCode(value: unknown) {
  const text = normalizeText(value);
  return text ? text.toLowerCase() : null;
}

function parseCoordinate(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value !== "string") {
    return null;
  }

  const parsed = Number(value.replace(",", ".").trim());
  return Number.isFinite(parsed) ? parsed : null;
}

async function loadReferenceRows(filePath: string) {
  const raw = await readFile(filePath, "utf8");
  const lines = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const [headerLine, ...dataLines] = lines;
  const headers = headerLine.split(",").map((item) => item.trim());

  return dataLines.map<CsvRow>((line) => {
    const values = line.split(",").map((item) => item.trim());
    return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ""]));
  });
}

async function main() {
  const filePath = await resolveClubsImportFile(process.argv[2]);

  if (!filePath) {
    throw new Error("Не найден файл клубов. Передай путь до .xlsx или положи его в docs/import/clubs.xlsx");
  }

  await importClubsFromWorkbook(filePath);
}

if (process.argv[1] && path.resolve(process.argv[1]).endsWith("import-clubs.ts")) {
  main()
    .catch((error) => {
      console.error(error);
      process.exit(1);
    })
    .finally(async () => {
      await prisma.$disconnect();
    });
}
