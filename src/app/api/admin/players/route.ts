import { NextRequest } from "next/server";

import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { adminPlayersQuerySchema } from "@/lib/validators";
import { listAdminPlayers } from "@/server/admin-players";
import { adminPlayersFailure } from "@/app/api/admin/players/_shared";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    await requireAdminUser();
    const query = adminPlayersQuerySchema.parse(Object.fromEntries(request.nextUrl.searchParams.entries()));
    return ok(await listAdminPlayers(query));
  } catch (error) {
    return adminPlayersFailure(error);
  }
}
