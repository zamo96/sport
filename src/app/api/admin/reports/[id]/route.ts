import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { resolveContentReportSchema } from "@/lib/validators";
import { getAdminContentReport, resolveAdminContentReport } from "@/server/content-reports";
import { adminReportsFailure } from "@/app/api/admin/reports/_shared";

export const dynamic = "force-dynamic";

export async function GET(_request: Request, { params }: { params: { id: string } }) {
  try {
    await requireAdminUser();
    return ok(await getAdminContentReport(params.id));
  } catch (error) {
    return adminReportsFailure(error);
  }
}

export async function PATCH(request: Request, { params }: { params: { id: string } }) {
  try {
    const actor = await requireAdminUser();
    const body = resolveContentReportSchema.parse(await request.json());
    return ok(await resolveAdminContentReport(actor, params.id, body));
  } catch (error) {
    return adminReportsFailure(error);
  }
}
