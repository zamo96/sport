import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";

export async function GET() {
  try {
    const user = await requireSessionUser();
    const seenAt = user.lastInboxSeenAt ?? new Date(0);
    const matchWhere = {
      OR: [{ user1Id: user.id }, { user2Id: user.id }]
    };

    const [newMatches, unreadMessages] = await Promise.all([
      prisma.match.findMany({
        where: {
          ...matchWhere,
          createdAt: {
            gt: seenAt
          }
        },
        select: {
          id: true
        }
      }),
      prisma.chatMessage.findMany({
        where: {
          createdAt: {
            gt: seenAt
          },
          senderUserId: {
            not: user.id
          },
          match: matchWhere
        },
        select: {
          matchId: true
        }
      })
    ]);

    const unreadMatchIds = new Set<string>();

    for (const match of newMatches) {
      unreadMatchIds.add(match.id);
    }

    for (const message of unreadMessages) {
      unreadMatchIds.add(message.matchId);
    }

    return ok({
      inboxBadgeCount: unreadMatchIds.size
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
