import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";

export async function GET() {
  try {
    const user = await requireSessionUser();
    const gameRequests = await prisma.gameRequest.findMany({
      where: {
        OR: [{ createdByUserId: user.id }, { matchedUserId: user.id }]
      },
      include: {
        proposedCourt: true,
        createdByUser: true,
        matchedUser: true
      },
      orderBy: {
        createdAt: "desc"
      }
    });

    return ok({
      gameRequests: gameRequests.map((gameRequest) => ({
        ...gameRequest,
        proposedDatetime: gameRequest.proposedDatetime.toISOString(),
        createdAt: gameRequest.createdAt.toISOString(),
        updatedAt: gameRequest.updatedAt.toISOString()
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
