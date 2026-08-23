import { NextRequest } from "next/server";

import { adminPlayersFailure } from "@/app/api/admin/players/_shared";
import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { adminPlayerProfilePatchSchema } from "@/lib/validators";
import { updateAdminPlayerProfile } from "@/server/admin-players";

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const actor = await requireAdminUser();
    const input = adminPlayerProfilePatchSchema.parse(await request.json());
    const { player } = await updateAdminPlayerProfile(actor, params.id, input);
    return ok({ player });
  } catch (error) {
    return adminPlayersFailure(error);
  }
}
