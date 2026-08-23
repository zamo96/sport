import { NextRequest } from "next/server";

import { adminPlayersFailure } from "@/app/api/admin/players/_shared";
import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { adminPlayerStatusPatchSchema } from "@/lib/validators";
import { updateAdminPlayerStatus } from "@/server/admin-players";

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const actor = await requireAdminUser();
    const input = adminPlayerStatusPatchSchema.parse(await request.json());
    return ok(await updateAdminPlayerStatus(actor, params.id, input));
  } catch (error) {
    return adminPlayersFailure(error);
  }
}
