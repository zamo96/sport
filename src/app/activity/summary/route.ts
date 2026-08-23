import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { getHotNotificationsCount, getIncomingLikesCount } from "@/server/app-data";
import { runGameRequestMaintenance } from "@/server/game-request-maintenance";
import { touchUserActivity } from "@/server/user-activity";

export async function GET() {
  try {
    const user = await requireSessionUser();
    await touchUserActivity(user.id);
    await runGameRequestMaintenance();
    const seenAt = user.lastInboxSeenAt ?? new Date(0);
    const notificationsSeenAt = user.lastNotificationsSeenAt ?? new Date(0);
    const matchWhere = {
      status: "active" as const,
      OR: [{ user1Id: user.id }, { user2Id: user.id }]
    };

    const [
      newMatches,
      unreadMessages,
      unreadSearchLobbyMessages,
      incomingLikesCount,
      hotBadgeCount,
      activeSearches,
      pendingSearchResponsesCount
    ] = await Promise.all([
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
      prisma.gameSearchMessage.findMany({
        where: {
          createdAt: {
            gt: notificationsSeenAt
          },
          senderUserId: {
            not: user.id
          },
          gameSearch: {
            OR: [
              { createdByUserId: user.id },
              {
                responses: {
                  some: {
                    responderUserId: user.id,
                    status: {
                      in: ["approved"]
                    }
                  }
                }
              }
            ]
          }
        },
        select: {
          gameSearchId: true
        }
      }),
      getIncomingLikesCount(user.id),
      getHotNotificationsCount(user.id),
      prisma.gameSearch.findMany({
        where: {
          createdByUserId: user.id,
          searchType: "hot",
          isActive: true,
          status: {
            in: ["active", "in_review"]
          }
        },
        select: {
          playersNeeded: true,
          responses: {
            where: {
              status: "approved"
            },
            select: {
              id: true
            }
          }
        }
      }),
      prisma.gameSearchResponse.count({
        where: {
          status: "pending",
          gameSearch: {
            createdByUserId: user.id,
            searchType: "hot",
            isActive: true,
            status: {
              in: ["active", "in_review"]
            }
          }
        }
      })
    ]);

    const unreadMatchIds = new Set<string>();

    for (const match of newMatches) {
      unreadMatchIds.add(match.id);
    }

    for (const message of unreadMessages) {
      unreadMatchIds.add(message.gameRequestId ?? message.matchId);
    }

    const unreadSearchLobbyIds = new Set<string>();

    for (const message of unreadSearchLobbyMessages) {
      unreadSearchLobbyIds.add(message.gameSearchId);
    }

    const activeSearchesCount = activeSearches.filter((search) => {
      const playersNeeded = Math.max(search.playersNeeded ?? 1, 1);
      return search.responses.length < playersNeeded;
    }).length;

    return ok({
      inboxBadgeCount: unreadMatchIds.size,
      incomingLikesCount,
      hotBadgeCount,
      discoverBadgeCount: incomingLikesCount + hotBadgeCount,
      activeSearchesCount,
      searchesBadgeCount: pendingSearchResponsesCount + unreadSearchLobbyIds.size,
      notificationSound: user.notificationSound ?? true
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
