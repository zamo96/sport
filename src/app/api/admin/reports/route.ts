import { NextRequest } from "next/server";

import { adminReportsFailure } from "@/app/api/admin/reports/_shared";
import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { adminContentReportsQuerySchema } from "@/lib/validators";
import { listAdminContentReports } from "@/server/content-reports";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    await requireAdminUser();
    const query = adminContentReportsQuerySchema.parse(Object.fromEntries(request.nextUrl.searchParams.entries()));
    return ok(await listAdminContentReports(query));
  } catch (error) {
    return adminReportsFailure(error);
  }
}
