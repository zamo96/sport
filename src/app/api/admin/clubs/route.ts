import { NextRequest } from "next/server";

import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { adminClubsQuerySchema } from "@/lib/validators";
import { adminClubsFailure } from "@/app/api/admin/clubs/_shared";
import { listAdminClubs } from "@/server/admin-clubs";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    await requireAdminUser();
    const query = adminClubsQuerySchema.parse(Object.fromEntries(request.nextUrl.searchParams.entries()));
    return ok(await listAdminClubs(query));
  } catch (error) {
    return adminClubsFailure(error);
  }
}
