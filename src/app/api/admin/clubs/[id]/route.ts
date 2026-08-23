import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { adminClubsFailure } from "@/app/api/admin/clubs/_shared";
import { getAdminClub } from "@/server/admin-clubs";

export const dynamic = "force-dynamic";

export async function GET(_: Request, { params }: { params: { id: string } }) {
  try {
    await requireAdminUser();
    return ok(await getAdminClub(params.id));
  } catch (error) {
    return adminClubsFailure(error);
  }
}
