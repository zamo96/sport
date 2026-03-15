import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { resolveSearchDays } from "@/lib/game-search";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = createGameSearchSchema.parse(await request.json());
    const preferredDays = resolveSearchDays(body.searchType, body.preferredDays, body.hotWindow);

    const gameSearch = await prisma.$transaction(async (tx) => {
      await tx.gameSearch.updateMany({
        where: {
          createdByUserId: user.id,
          isActive: true,
          searchType: body.searchType
        },
        data: {
          isActive: false
        }
      });

      const created = await tx.gameSearch.create({
        data: {
          createdByUserId: user.id,
          preferredCourtId: body.preferredCourtId ?? null,
          preferredDays,
          preferredTimeRanges: body.preferredTimeRanges,
          searchType: body.searchType,
          hotWindow: body.searchType === "hot" ? body.hotWindow ?? null : null,
          hasCourtBooked: body.hasCourtBooked ?? false,
          sport: body.sport,
          format: body.format,
          comment: body.comment,
          status: "active",
          isActive: true
        },
        include: {
          preferredCourt: true
        }
      });

      await tx.user.update({
        where: { id: user.id },
        data: { isLookingForGame: true }
      });

      return created;
    });

    return ok({
      gameSearch: {
        ...gameSearch,
        createdAt: gameSearch.createdAt.toISOString(),
        updatedAt: gameSearch.updatedAt.toISOString()
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
