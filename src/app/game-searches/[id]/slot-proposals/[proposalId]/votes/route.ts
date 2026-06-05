import { NextRequest } from "next/server";
import { GameSearchResponseStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { voteGameSearchSlotProposalSchema } from "@/lib/validators";

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
          responses: {
            some: {
              responderUserId: user.id,
              status: GameSearchResponseStatus.approved
            }
          }
        }
      },
      include: {
        options: {
          select: {
            id: true
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

      return tx.gameSearchSlotProposal.findUniqueOrThrow({
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
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
