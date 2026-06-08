import { NextRequest } from "next/server";
import { GameSearchResponseStatus, GameSearchType, Prisma } from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { createGameSearchSlotProposalSchema } from "@/lib/validators";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";

const DAY_KEYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] as const;
const DAY_ORDER = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function formatTimeSlot(date: Date) {
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

function buildWeeklySchedule(options: { scheduledAt: string }[]) {
  const days = new Set<string>();
  const timePreferences = new Set<string>();

  for (const option of options) {
    const date = new Date(option.scheduledAt);
    if (Number.isNaN(date.getTime())) {
      continue;
    }
    const day = DAY_KEYS[date.getDay()];
    days.add(day);
    timePreferences.add(`${day}@${formatTimeSlot(date)}`);
  }

  return {
    preferredDays: DAY_ORDER.filter((day) => days.has(day)),
    preferredTimeRanges: Array.from(timePreferences).sort((left, right) => {
      const [leftDay, leftTime] = left.split("@");
      const [rightDay, rightTime] = right.split("@");
      const dayDiff = DAY_ORDER.indexOf(leftDay) - DAY_ORDER.indexOf(rightDay);
      return dayDiff || (leftTime ?? "").localeCompare(rightTime ?? "");
    })
  };
}

function commonCourtId(options: { proposedCourtId?: string | null }[]) {
  const courtIds = Array.from(
    new Set(options.map((option) => option.proposedCourtId).filter((courtId): courtId is string => Boolean(courtId)))
  );
  return courtIds.length === 1 ? courtIds[0] ?? null : null;
}

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

    if (gameSearch.searchType !== GameSearchType.regular) {
      return fail("Слоты можно предлагать только в регулярном поиске", 409);
    }

    if (gameSearch.responses.length === 0) {
      return fail("Сначала нужно подтвердить хотя бы одного игрока", 409);
    }

    const proposal = await prisma.$transaction(async (tx) => {
      const weeklySchedule = buildWeeklySchedule(body.options);
      const preferredDays = weeklySchedule.preferredDays.length
        ? weeklySchedule.preferredDays
        : normalizeStringArray(gameSearch.preferredDays);
      const preferredTimeRanges = weeklySchedule.preferredTimeRanges.length
        ? weeklySchedule.preferredTimeRanges
        : normalizeStringArray(gameSearch.preferredTimeRanges);
      const proposedRegularCourtId = commonCourtId(body.options) ?? gameSearch.preferredCourtId ?? null;

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

      await tx.gameSearch.update({
        where: {
          id: gameSearch.id
        },
        data: {
          preferredDays: preferredDays as Prisma.InputJsonValue,
          preferredTimeRanges: preferredTimeRanges as Prisma.InputJsonValue,
          preferredCourtId: proposedRegularCourtId
        }
      });

      const regularPair = await tx.regularPair.findUnique({
        where: {
          gameSearchId: gameSearch.id
        },
        select: {
          id: true
        }
      });

      if (regularPair) {
        await tx.regularPair.update({
          where: {
            id: regularPair.id
          },
          data: {
            preferredDays: preferredDays as Prisma.InputJsonValue,
            preferredTimeRanges: preferredTimeRanges as Prisma.InputJsonValue,
            preferredCourtId: proposedRegularCourtId
          }
        });
        await syncRegularPairOccurrences(tx, regularPair.id);
      }

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
              ? `Организатор предложил регулярный еженедельный слот: ${summary}.`
              : `Организатор предложил ${created.options.length} еженедельных варианта времени: ${summary}${created.options.length > 3 ? "..." : ""}.`
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
