import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { discoverFiltersSchema } from "@/lib/validators";
import { countDiscoverCandidates } from "@/server/discover";

/**
 * Число для бейджа вкладки «Игроки», пока открыта другая вкладка. Тот же отбор,
 * что у `GET /users/discover`, но без ранжирования и без записи показов:
 * карточки, которых человек не видел, не должны попадать в `DiscoverImpression` —
 * это будущие обучающие данные ранкера.
 */
export async function GET(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const filters = discoverFiltersSchema.parse(Object.fromEntries(request.nextUrl.searchParams));

    return ok({ count: await countDiscoverCandidates(user.id, filters) });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
