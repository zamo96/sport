import path from "node:path";

import * as XLSX from "xlsx";

import {
  atomicWriteJson,
  buildPreparedYandexClubs,
  fetchYandexOrganizationCoordinates,
  groupRawYandexClubs,
  type RawYandexClubRow
} from "@/lib/yandex-club-source";

async function main() {
  const args = process.argv.slice(2);
  const inputPath = args.find((arg) => !arg.startsWith("--"));
  if (!inputPath) {
    throw new Error("Передай путь до исходного XLSX");
  }
  const outputPath = readArg(args, "--output") ?? path.join(process.cwd(), "prepared-yandex-clubs.json");
  const cacheDir = readArg(args, "--cache-dir") ?? path.join(path.dirname(outputPath), "yandex-cache");
  const concurrency = parsePositiveInteger(readArg(args, "--concurrency") ?? "4", "--concurrency");

  const workbook = XLSX.readFile(path.resolve(inputPath));
  const firstSheetName = workbook.SheetNames[0];
  if (!firstSheetName) throw new Error("В XLSX нет листов");
  const rawRows = XLSX.utils.sheet_to_json<RawYandexClubRow>(workbook.Sheets[firstSheetName], {
    defval: "",
    raw: false,
    range: 1
  });
  const organizations = groupRawYandexClubs(rawRows);
  if (organizations.length === 0) throw new Error("Не найдены Yandex org ID для подготовки");

  console.log(`Начинаю получение координат: ${organizations.length} организаций, concurrency=${concurrency}`);
  const coordinates = await fetchYandexOrganizationCoordinates(organizations, {
    cacheDir: path.resolve(cacheDir),
    concurrency,
    onProgress(completed, total) {
      if (completed === total || completed % 100 === 0) console.log(`Координаты: ${completed}/${total}`);
    }
  });
  const clubs = buildPreparedYandexClubs(organizations, coordinates);
  const payload = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    sourceFile: path.basename(inputPath),
    sourceRowCount: rawRows.length,
    uniqueOrganizationCount: organizations.length,
    clubs
  };
  await atomicWriteJson(path.resolve(outputPath), payload);
  console.log(`Готово: строк ${rawRows.length}, уникальных организаций ${organizations.length}, координат ${coordinates.size}`);
  console.log(`JSON: ${path.resolve(outputPath)}`);
}

function readArg(args: string[], name: string) {
  const prefix = `${name}=`;
  return args.find((arg) => arg.startsWith(prefix))?.slice(prefix.length);
}

function parsePositiveInteger(value: string, name: string) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${name} должен быть положительным целым числом`);
  return parsed;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
