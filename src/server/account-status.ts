import { Prisma } from "@prisma/client";

type RowLockClient = Pick<Prisma.TransactionClient, "$queryRaw">;

export async function lockActiveUserForMutation(db: RowLockClient, userId: string) {
  const lockedUserIds = await lockActiveUsersForMutation(db, [userId]);
  return lockedUserIds.has(userId);
}

export async function lockActiveUsersForMutation(db: RowLockClient, userIds: string[]) {
  const orderedUserIds = Array.from(new Set(userIds)).sort();
  if (orderedUserIds.length === 0) {
    return new Set<string>();
  }

  const rows = await db.$queryRaw<Array<{ id: string }>>(Prisma.sql`
    SELECT "id"
    FROM "User"
    WHERE "id" IN (${Prisma.join(orderedUserIds)}) AND "accountStatus" = 'active'
    ORDER BY "id"
    FOR UPDATE
  `);

  return new Set(rows.map((row) => row.id));
}
