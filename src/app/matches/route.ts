import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { otherUserFromMatch } from "@/server/serializers";

export async function GET() {
  try {
    const user = await requireSessionUser();
    const matches = await prisma.match.findMany({
      where: {
        OR: [{ user1Id: user.id }, { user2Id: user.id }]
      },
      include: {
        user1: true,
        user2: true,
        messages: {
          orderBy: { createdAt: "desc" },
          take: 1
        },
        gameRequests: {
          include: {
            proposedCourt: true
          },
          orderBy: { createdAt: "desc" },
          take: 1
        }
      },
      orderBy: {
        updatedAt: "desc"
      }
    });

    return ok({
      matches: matches.map((match) => ({
        id: match.id,
        status: match.status,
        createdAt: match.createdAt.toISOString(),
        otherUser: otherUserFromMatch(match, user.id),
        lastMessage: match.messages[0]
          ? {
              ...match.messages[0],
              createdAt: match.messages[0].createdAt.toISOString()
            }
          : null,
        latestGameRequest: match.gameRequests[0]
          ? {
              ...match.gameRequests[0],
              proposedDatetime: match.gameRequests[0].proposedDatetime.toISOString(),
              outcomeUpdatedAt: match.gameRequests[0].outcomeUpdatedAt?.toISOString() ?? null,
              createdAt: match.gameRequests[0].createdAt.toISOString(),
              updatedAt: match.gameRequests[0].updatedAt.toISOString()
            }
          : null
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
