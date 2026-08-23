import path from "node:path";

import { prisma } from "@/lib/prisma";
import { SAINT_PETERSBURG_CITY } from "@/lib/club-city-replacement";
import { replaceCityClubsFromWorkbook, resolveClubsImportFile } from "./import-clubs";

async function main() {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const expectedCountArg = args.find((arg) => arg.startsWith("--expected-count="));
  const expectedCount = expectedCountArg ? Number(expectedCountArg.split("=")[1]) : 997;
  const fileArg = args.find((arg) => !arg.startsWith("--"));

  if (!Number.isInteger(expectedCount) || expectedCount <= 0) {
    throw new Error("--expected-count должен быть положительным целым числом");
  }

  const filePath = await resolveClubsImportFile(fileArg);
  if (!filePath) {
    throw new Error("Не найден файл клубов. Передай путь до canonical .xlsx");
  }

  const summary = await replaceCityClubsFromWorkbook(filePath, {
    city: SAINT_PETERSBURG_CITY,
    apply,
    expectedCount
  });

  console.log(`${summary.applied ? "Замена выполнена" : "DRY RUN"}: ${summary.city}`);
  console.log(`Новый набор: ${summary.incomingCount}`);
  console.log(`С сохранением Court.id: ${summary.retainedIdCount}`);
  console.log(`Будет создано: ${summary.createdCount}`);
  console.log(`Будет архивировано: ${summary.retiredCount}`);
  if (!summary.applied) {
    console.log("Изменений в БД нет. Для применения повтори команду с --apply");
  }
}

if (process.argv[1] && path.resolve(process.argv[1]).endsWith("replace-city-clubs.ts")) {
  main()
    .catch((error) => {
      console.error(error);
      process.exit(1);
    })
    .finally(async () => {
      await prisma.$disconnect();
    });
}
