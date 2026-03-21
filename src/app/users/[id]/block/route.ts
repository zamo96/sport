import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";

export async function POST(_request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();

    if (params.id === user.id) {
      return fail("Нельзя заблокировать самого себя");
    }

    const targetUser = await prisma.user.findUnique({
      where: { id: params.id }
    });

    if (!targetUser) {
      return fail("Пользователь не найден", 404);
    }

    await prisma.$transaction(async (tx) => {
      await tx.block.upsert({
        where: {
          blockerUserId_blockedUserId: {
            blockerUserId: user.id,
            blockedUserId: params.id
          }
        },
        create: {
          blockerUserId: user.id,
          blockedUserId: params.id
        },
        update: {}
      });

      await tx.match.updateMany({
        where: {
          OR: [
            { user1Id: user.id, user2Id: params.id },
            { user1Id: params.id, user2Id: user.id }
          ]
        },
        data: {
          status: "archived"
        }
      });
    });

    return ok({ success: true });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
