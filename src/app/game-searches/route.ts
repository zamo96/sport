import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { resolveHotSearchStartAt, resolveSearchDays } from "@/lib/game-search";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = createGameSearchSchema.parse(await request.json());
    const preferredDays = resolveSearchDays(body.searchType, body.preferredDays, body.hotWindow);
    const hotStartsAt =
      body.searchType === "hot" && body.hotWindow && body.hotStartTime
        ? resolveHotSearchStartAt(body.hotWindow, body.hotStartTime)
        : null;

    if (body.searchType === "hot" && !hotStartsAt) {
      return fail("Не удалось определить время начала горячего поиска");
    }

    if (body.searchType === "hot" && hotStartsAt && hotStartsAt.getTime() <= Date.now()) {
      return fail("Для горячего поиска выбери время позже текущего");
    }

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
          hotStartsAt,
          durationMinutes: body.searchType === "hot" ? body.durationMinutes ?? null : null,
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
        updatedAt: gameSearch.updatedAt.toISOString(),
        hotStartsAt: gameSearch.hotStartsAt?.toISOString() ?? null
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
