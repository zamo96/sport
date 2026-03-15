import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { discoverFiltersSchema } from "@/lib/validators";
import { getDiscoverCandidates } from "@/server/discover";
import { serializeUserPreview } from "@/server/serializers";

export async function GET(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const filters = discoverFiltersSchema.parse(Object.fromEntries(request.nextUrl.searchParams));
    const candidates = await getDiscoverCandidates(user.id, filters);

    return ok({
      users: candidates.map((candidate) => serializeUserPreview(candidate))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
