import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { swipeSchema } from "@/lib/validators";
import { createSwipeAndMaybeMatch } from "@/server/matching";

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = swipeSchema.parse(await request.json());

    if (body.toUserId === user.id) {
      return fail("Нельзя свайпнуть самого себя");
    }

    const targetUser = await prisma.user.findUnique({
      where: { id: body.toUserId }
    });

    if (!targetUser) {
      return fail("Игрок не найден", 404);
    }

    const result = await createSwipeAndMaybeMatch(user.id, body.toUserId, body.action);

    return ok({
      swipe: result.swipe,
      match: result.match
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
