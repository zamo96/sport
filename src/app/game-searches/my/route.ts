import { requireSessionUser } from "@/lib/auth";
import { isExpiredHotSearch } from "@/lib/game-search";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";

export async function GET() {
  try {
    const user = await requireSessionUser();
    const pairIds = await prisma.regularPair.findMany({
      where: {
        OR: [{ createdByUserId: user.id }, { partnerUserId: user.id }]
      },
      select: {
        id: true
      }
    });
    await Promise.all(pairIds.map((pair) => syncRegularPairOccurrences(prisma, pair.id)));
    const gameSearches = await prisma.gameSearch.findMany({
      where: {
        createdByUserId: user.id
      },
      include: {
        preferredCourt: true,
        slotProposals: {
          where: {
            status: "open"
          },
          orderBy: {
            createdAt: "desc"
          },
          take: 1,
          include: {
            options: {
              include: {
                proposedCourt: true,
                votes: true
              },
              orderBy: {
                scheduledAt: "asc"
              }
            }
          }
        },
        regularPair: {
          include: {
            partnerUser: true,
            preferredCourt: true,
            occurrences: {
              include: {
                proposedCourt: true,
                confirmations: {
                  include: {
                    user: true
                  }
                }
              },
              orderBy: {
                scheduledAt: "asc"
              }
            }
          }
        },
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
        preferredDistricts: stringArray(gameSearch.preferredDistricts),
        preferredDays: stringArray(gameSearch.preferredDays),
        preferredTimeRanges: stringArray(gameSearch.preferredTimeRanges),
        createdAt: gameSearch.createdAt.toISOString(),
        updatedAt: gameSearch.updatedAt.toISOString(),
        hotStartsAt: gameSearch.hotStartsAt?.toISOString() ?? null,
        scheduledAt: gameSearch.scheduledAt?.toISOString() ?? null,
        scheduledDurationMinutes: gameSearch.scheduledDurationMinutes ?? null,
        activeSlotProposal: gameSearch.slotProposals[0] ?? null,
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

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}
