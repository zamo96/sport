import { CourtStatus, Prisma, type PrismaClient } from "@prisma/client";

type CourtReader = Pick<PrismaClient, "court" | "$queryRaw">;

export async function assertActiveCourtIds(client: CourtReader, courtIds: Array<string | null | undefined>) {
  const ids = Array.from(new Set(courtIds.filter((id): id is string => Boolean(id))));
  if (!ids.length) return;
  await client.$queryRaw(Prisma.sql`SELECT "id" FROM "Court" WHERE "id" IN (${Prisma.join(ids)}) FOR SHARE`);
  const activeCount = await client.court.count({ where: { id: { in: ids }, status: CourtStatus.active } });
  if (activeCount !== ids.length) throw new Error("COURT_UNAVAILABLE");
}
