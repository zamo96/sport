import { requireAdminUser } from "@/lib/admin";
import { ok } from "@/lib/http";
import { getAdminPlayer } from "@/server/admin-players";
import { adminPlayersFailure } from "@/app/api/admin/players/_shared";

export const dynamic = "force-dynamic";

export async function GET(_request: Request, { params }: { params: { id: string } }) {
  try {
    await requireAdminUser();
    return ok(await getAdminPlayer(params.id));
  } catch (error) {
    return adminPlayersFailure(error);
  }
}
