import { NextRequest } from "next/server";
import { GameSearchResponseStatus, GameSearchType, Prisma } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { formatLocalDateTime } from "@/lib/timezone";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { buildWeeklySchedule } from "@/lib/game-search";
import { voteGameSearchSlotProposalSchema } from "@/lib/validators";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";
import { assertActiveCourtIds } from "@/server/court-status";

function commonCourtId(options: { proposedCourtId?: string | null }[]) {
  const courtIds = Array.from(
    new Set(options.map((option) => option.proposedCourtId).filter((courtId): courtId is string => Boolean(courtId)))
  );
  return courtIds.length === 1 ? courtIds[0] ?? null : null;
}

export async function PUT(
  request: NextRequest,
  { params }: { params: { id: string; proposalId: string } }
) {
  try {
    const user = await requireSessionUser();
    const body = voteGameSearchSlotProposalSchema.parse(await request.json());

    const proposal = await prisma.gameSearchSlotProposal.findFirst({
      where: {
        id: params.proposalId,
        gameSearchId: params.id,
        status: "open",
        gameSearch: {
          searchType: GameSearchType.regular,
          responses: {
            some: {
              responderUserId: user.id,
              status: GameSearchResponseStatus.approved
            }
          }
        }
      },
      include: {
        gameSearch: {
          select: {
            id: true,
            preferredCourtId: true,
            // Голосует участник, но расписание пары живёт в зоне организатора.
            createdByUser: { select: { timezone: true } },
            responses: {
              where: {
                status: GameSearchResponseStatus.approved
              },
              select: {
                id: true
              }
            },
            regularPair: {
              select: {
                id: true
              }
            }
          }
        },
        options: {
          select: {
            id: true,
            proposedCourtId: true
          }
        }
      }
    });

    if (!proposal) {
      return fail("Опрос по слотам не найден", 404);
    }

    const allowedOptionIds = new Set(proposal.options.map((option) => option.id));
    if (body.optionIds.some((optionId) => !allowedOptionIds.has(optionId))) {
      return fail("Один из слотов недоступен", 400);
    }

    const updated = await prisma.$transaction(async (tx) => {
      await assertActiveCourtIds(tx, [
        proposal.gameSearch.preferredCourtId,
        ...proposal.options.map((option) => option.proposedCourtId)
      ]);
      await tx.gameSearchSlotVote.deleteMany({
        where: {
          userId: user.id,
          option: {
            proposalId: proposal.id
          }
        }
      });

      if (body.optionIds.length > 0) {
        await tx.gameSearchSlotVote.createMany({
          data: body.optionIds.map((optionId) => ({
            optionId,
            userId: user.id
          }))
        });
      }

      const updated = await tx.gameSearchSlotProposal.findUniqueOrThrow({
        where: {
          id: proposal.id
        },
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
      });

      const approvedRespondersCount = proposal.gameSearch.responses.length;
      const finalizedOptions =
        approvedRespondersCount > 0
          ? updated.options.filter((option) => option.votes.length >= approvedRespondersCount)
          : [];

      if (finalizedOptions.length === 0) {
        return updated;
      }

      const weeklySchedule = buildWeeklySchedule(finalizedOptions, proposal.gameSearch.createdByUser?.timezone);
      const proposedRegularCourtId = commonCourtId(finalizedOptions) ?? proposal.gameSearch.preferredCourtId ?? null;

      await tx.gameSearch.update({
        where: {
          id: proposal.gameSearch.id
        },
        data: {
          preferredDays: weeklySchedule.preferredDays as Prisma.InputJsonValue,
          preferredTimeRanges: weeklySchedule.preferredTimeRanges as Prisma.InputJsonValue,
          preferredCourtId: proposedRegularCourtId
        }
      });

      if (proposal.gameSearch.regularPair) {
        await tx.regularPair.update({
          where: {
            id: proposal.gameSearch.regularPair.id
          },
          data: {
            preferredDays: weeklySchedule.preferredDays as Prisma.InputJsonValue,
            preferredTimeRanges: weeklySchedule.preferredTimeRanges as Prisma.InputJsonValue,
            preferredCourtId: proposedRegularCourtId
          }
        });
        await syncRegularPairOccurrences(tx, proposal.gameSearch.regularPair.id);
      }

      const summary = finalizedOptions
        .slice(0, 3)
        .map((option) =>
          formatLocalDateTime(user.timezone, option.scheduledAt, {
            weekday: "short",
            hour: "2-digit",
            minute: "2-digit"
          })
        )
        .join(", ");

      await tx.gameSearchMessage.create({
        data: {
          gameSearchId: proposal.gameSearch.id,
          senderUserId: user.id,
          text: `Регулярное расписание согласовано: ${summary}${finalizedOptions.length > 3 ? "..." : ""}. Эти слоты будут повторяться каждую неделю.`
        }
      });

      return tx.gameSearchSlotProposal.update({
        where: {
          id: proposal.id
        },
        data: {
          status: "closed"
        },
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
      });
    });

    return ok({
      proposal: {
        ...updated,
        createdAt: updated.createdAt.toISOString(),
        updatedAt: updated.updatedAt.toISOString(),
        options: updated.options.map((option) => ({
          ...option,
          scheduledAt: option.scheduledAt.toISOString(),
          createdAt: option.createdAt.toISOString(),
          votes: option.votes.map((vote) => ({
            ...vote,
            createdAt: vote.createdAt.toISOString()
          }))
        }))
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "COURT_UNAVAILABLE") {
      return fail("Клуб временно недоступен", 409);
    }
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
