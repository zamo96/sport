import { requireSessionUser } from "@/lib/auth";
import { isExpiredHotSearch } from "@/lib/game-search";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";

export async function GET() {
  try {
    const user = await requireSessionUser();
    const gameSearches = await prisma.gameSearch.findMany({
      where: {
        createdByUserId: user.id
      },
      include: {
        preferredCourt: true,
        responses: {
          include: {
            responderUser: true
          },
          orderBy: [
            { status: "asc" },
            { createdAt: "asc" }
          ]
        }
      },
      orderBy: {
        createdAt: "desc"
      }
    });

    return ok({
      gameSearches: gameSearches.map((gameSearch) => ({
        ...gameSearch,
        createdAt: gameSearch.createdAt.toISOString(),
        updatedAt: gameSearch.updatedAt.toISOString(),
        hotStartsAt: gameSearch.hotStartsAt?.toISOString() ?? null,
        playersNeeded: gameSearch.playersNeeded,
        isExpired: isExpiredHotSearch(gameSearch.hotStartsAt)
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
