import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { adminClubStatusPatchSchema } from "@/lib/validators";
import { adminClubsFailure } from "@/app/api/admin/clubs/_shared";
import { updateAdminClubStatus } from "@/server/admin-clubs";

export async function PATCH(request: Request, { params }: { params: { id: string } }) {
  try {
    const actor = await requireAdminUser();
    const input = adminClubStatusPatchSchema.parse(await request.json());
    return ok(await updateAdminClubStatus(actor, params.id, input));
  } catch (error) {
    return adminClubsFailure(error);
  }
}
