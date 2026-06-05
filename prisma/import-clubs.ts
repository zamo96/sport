import { access, readFile } from "node:fs/promises";
import path from "node:path";

import { CourtSetting, Sport, Surface } from "@prisma/client";
import * as XLSX from "xlsx";

import { DEFAULT_CITY } from "@/lib/constants";
import { prisma } from "@/lib/prisma";

type ClubRow = {
  name?: string;
  address?: string;
  sports?: string;
  phone?: string;
  working_hours?: string;
  yandex_maps_url?: string;
  website_url?: string;
  photo_url?: string;
  metro?: string;
  district?: string;
  district_label?: string;
  lat?: number | string;
  lng?: number | string;
};

type CsvRow = Record<string, string>;

const DISTRICTS_REFERENCE_PATH = path.join(process.cwd(), "docs/import/districts-reference.csv");
const METROS_REFERENCE_PATH = path.join(process.cwd(), "docs/import/metros-spb.reference.csv");
const DEFAULT_CLUBS_XLSX_PATH = path.join(process.cwd(), "docs/import/clubs.xlsx");
const IMPORT_SOURCE_TYPE = "xlsx-import";
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
  футбол: Sport.football
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
            city: DEFAULT_CITY
          }
        ])
    ).values()
  );

  const metroNames = Array.from(
    new Set([
      ...metrosReference.map((row) => row.name),
      ...rows.map((row) => row.metro).filter((metro): metro is string => Boolean(metro))
    ])
  );

  await prisma.district.createMany({
    data: districtRows,
    skipDuplicates: true
  });

  await prisma.metro.createMany({
    data: metroNames.map((name) => ({
      name,
      city: DEFAULT_CITY
    })),
    skipDuplicates: true
  });

  const metros = await prisma.metro.findMany({
    where: { city: DEFAULT_CITY }
  });
  const metroByName = new Map(metros.map((metro) => [metro.name.toLowerCase(), metro.id]));

  const dedupedRows = Array.from(
    new Map(
      rows.map((row) => [
        `${row.name.toLowerCase()}::${row.address.toLowerCase()}`,
        row
      ])
    ).values()
  );

  await prisma.court.deleteMany({
    where: {
      sourceType: IMPORT_SOURCE_TYPE
    }
  });

  await prisma.court.createMany({
    data: dedupedRows.map((row) => ({
      name: row.name,
      address: row.address,
      city: DEFAULT_CITY,
      district: row.district,
      nearestMetroId: row.metro ? metroByName.get(row.metro.toLowerCase()) ?? null : null,
      locationLat: row.lat,
      locationLng: row.lng,
      surface: Surface.any,
      setting: CourtSetting.indoor,
      supportedSports: row.sports,
      phone: row.phone,
      workingHours: row.workingHours,
      yandexMapsUrl: row.yandexMapsUrl,
      websiteUrl: row.websiteUrl,
      photoUrl: row.photoUrl,
      priceRange: "Не указано",
      rating: null,
      sourceType: IMPORT_SOURCE_TYPE,
      bookingUrl: row.websiteUrl
    }))
  });

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

  console.log(`Импорт завершен. Загружено клубов: ${importedCount}`);
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
  sports: Sport[];
  phone: string | null;
  workingHours: string | null;
  yandexMapsUrl: string | null;
  websiteUrl: string | null;
  photoUrl: string | null;
  metro: string | null;
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

  if (!name || !address || sports.length === 0 || lat == null || lng == null) {
    return null;
  }

  return {
    name,
    address,
    sports,
    phone: normalizeText(row.phone),
    workingHours: normalizeText(row.working_hours),
    yandexMapsUrl: normalizeUrl(row.yandex_maps_url),
    websiteUrl: normalizeUrl(row.website_url),
    photoUrl: normalizeUrl(row.photo_url),
    metro: normalizeText(row.metro),
    district: normalizeDistrictCode(row.district),
    districtLabel: normalizeText(row.district_label),
    lat,
    lng
  };
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
