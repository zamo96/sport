import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { getHotNotificationsCount, getIncomingLikesCount } from "@/server/app-data";
import { touchUserActivity } from "@/server/user-activity";

export async function GET() {
  try {
    const user = await requireSessionUser();
    await touchUserActivity(user.id);
    const seenAt = user.lastInboxSeenAt ?? new Date(0);
    const matchWhere = {
      status: "active" as const,
      OR: [{ user1Id: user.id }, { user2Id: user.id }]
    };

    const [newMatches, unreadMessages, incomingLikesCount, hotBadgeCount] = await Promise.all([
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
          matchId: true,
          gameRequestId: true
        }
      }),
      getIncomingLikesCount(user.id),
      getHotNotificationsCount(user.id)
    ]);

    const unreadMatchIds = new Set<string>();

    for (const match of newMatches) {
      unreadMatchIds.add(match.id);
    }

    for (const message of unreadMessages) {
      unreadMatchIds.add(message.gameRequestId ?? message.matchId);
    }

    return ok({
      inboxBadgeCount: unreadMatchIds.size,
      incomingLikesCount,
      hotBadgeCount,
      discoverBadgeCount: incomingLikesCount + hotBadgeCount,
      notificationSound: user.notificationSound ?? true
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
