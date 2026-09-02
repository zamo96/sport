import { prisma } from "@/lib/prisma";
import { resolveTimezoneFromCoordinates } from "@/lib/timezone";

const BATCH_SIZE = 500;

/**
 * Проставляет `User.timezone` уже зарегистрированным игрокам: сначала по
 * домашней точке, затем по координатам города. Без зоны движок кампаний
 * откатывается на Москву, поэтому бэкфилл нужен один раз после миграции.
 */
async function main() {
  const dryRun = process.argv.includes("--dry-run");
  let cursor: string | null = null;
  let scanned = 0;
  let resolved = 0;
  let unresolved = 0;

  for (;;) {
    const page: { cursor?: { id: string }; skip?: number } = cursor
      ? { cursor: { id: cursor }, skip: 1 }
      : {};
    const users = await prisma.user.findMany({
      where: { timezone: null },
      select: {
        id: true,
        homeLat: true,
        homeLng: true,
        location: { select: { latitude: true, longitude: true } }
      },
      orderBy: { id: "asc" },
      ...page,
      take: BATCH_SIZE
    });

    if (users.length === 0) {
      break;
    }

    for (const user of users) {
      scanned += 1;
      const timezone =
        resolveTimezoneFromCoordinates(user.homeLat, user.homeLng) ??
        resolveTimezoneFromCoordinates(user.location?.latitude, user.location?.longitude);

      if (!timezone) {
        unresolved += 1;
        continue;
      }

      resolved += 1;

      if (!dryRun) {
        await prisma.user.update({
          where: { id: user.id },
          data: { timezone }
        });
      }
    }

    cursor = users[users.length - 1].id;
  }

  console.log(
    `Таймзоны${dryRun ? " (dry run)" : ""}: просмотрено ${scanned}, проставлено ${resolved}, без координат ${unresolved}`
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
