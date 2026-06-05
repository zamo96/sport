import { NextRequest } from "next/server";
import { GameSearchResponseStatus } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchSlotProposalSchema } from "@/lib/validators";

export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireSessionUser();
    const body = createGameSearchSlotProposalSchema.parse(await request.json());

    const gameSearch = await prisma.gameSearch.findFirst({
      where: {
        id: params.id,
        createdByUserId: user.id
      },
      include: {
        responses: {
          where: {
            status: GameSearchResponseStatus.approved
          }
        }
      }
    });

    if (!gameSearch) {
      return fail("Поиск игры не найден", 404);
    }

    if (gameSearch.responses.length === 0) {
      return fail("Сначала нужно подтвердить хотя бы одного игрока", 409);
    }

    const proposal = await prisma.$transaction(async (tx) => {
      await tx.gameSearchSlotProposal.updateMany({
        where: {
          gameSearchId: gameSearch.id,
          status: "open"
        },
        data: {
          status: "closed"
        }
      });

      const created = await tx.gameSearchSlotProposal.create({
        data: {
          gameSearchId: gameSearch.id,
          comment: body.comment?.trim() || null,
          options: {
            create: body.options.map((option) => ({
              proposedCourtId: option.proposedCourtId ?? gameSearch.preferredCourtId ?? null,
              scheduledAt: new Date(option.scheduledAt),
              durationMinutes: option.durationMinutes ?? gameSearch.durationMinutes ?? gameSearch.scheduledDurationMinutes ?? 90
            }))
          }
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

      const summary = created.options
        .slice(0, 3)
        .map((option) =>
          option.scheduledAt.toLocaleString("ru-RU", {
            day: "2-digit",
            month: "2-digit",
            hour: "2-digit",
            minute: "2-digit"
          })
        )
        .join(", ");

      await tx.gameSearchMessage.create({
        data: {
          gameSearchId: gameSearch.id,
          senderUserId: user.id,
          text:
            created.options.length === 1
              ? `Организатор предложил слот: ${summary}.`
              : `Организатор предложил ${created.options.length} варианта времени: ${summary}${created.options.length > 3 ? "..." : ""}.`
        }
      });

      return created;
    });

    return ok({
      proposal: {
        ...proposal,
        createdAt: proposal.createdAt.toISOString(),
        updatedAt: proposal.updatedAt.toISOString(),
        options: proposal.options.map((option) => ({
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
