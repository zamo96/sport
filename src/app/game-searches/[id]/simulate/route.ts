import {
  GameSearchResponseStatus,
  GameSearchStatus,
  GameSearchSlotProposalStatus,
  GameSearchType,
  PlayFormat,
  Prisma,
  Sport
} from "@prisma/client";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";

const DAY_KEYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] as const;
const DAY_ORDER = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

const SIM_USERS = [
  { name: "Елена", level: 5, district: "petrogradsky" },
  { name: "Мария", level: 4, district: "primorsky" },
  { name: "София", level: 6, district: "central" }
];

function isSimulationEnabled() {
  return process.env.NODE_ENV !== "production" || process.env.ENABLE_SEARCH_SIMULATION === "true";
}

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function formatTimeSlot(date: Date) {
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

function buildWeeklySchedule(options: { scheduledAt: Date }[]) {
  const days = new Set<string>();
  const timePreferences = new Set<string>();

  for (const option of options) {
    const day = DAY_KEYS[option.scheduledAt.getDay()];
    days.add(day);
    timePreferences.add(`${day}@${formatTimeSlot(option.scheduledAt)}`);
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

async function ensureSimulationUsers(
  tx: Prisma.TransactionClient,
  gameSearch: { id: string; sport: Sport; preferredDays: Prisma.JsonValue; preferredTimeRanges: Prisma.JsonValue },
  excludedUserIds: Set<string>,
  count: number
) {
  const existing = await tx.user.findMany({
    where: {
      id: {
        notIn: Array.from(excludedUserIds)
      },
      onboardingCompleted: true,
      isLookingForGame: true
    },
    orderBy: {
      updatedAt: "desc"
    },
    take: count
  });

  const users = [...existing];
  for (let index = 0; users.length < count && index < SIM_USERS.length; index += 1) {
    const profile = SIM_USERS[index];
    const email = `sim-${gameSearch.id}-${index + 1}@tennis.local`;
    const user = await tx.user.upsert({
      where: { email },
      update: {
        name: profile.name,
        district: profile.district,
        preferredSports: [gameSearch.sport] as Prisma.InputJsonValue,
        sportLevels: { [gameSearch.sport]: profile.level } as Prisma.InputJsonValue,
        availableDays: normalizeStringArray(gameSearch.preferredDays) as Prisma.InputJsonValue,
        availableTimeRanges: normalizeStringArray(gameSearch.preferredTimeRanges) as Prisma.InputJsonValue,
        onboardingCompleted: true,
        isLookingForGame: true
      },
      create: {
        email,
        name: profile.name,
        age: 26 + index * 3,
        city: "Санкт-Петербург",
        district: profile.district,
        preferredDistricts: [profile.district] as Prisma.InputJsonValue,
        preferredSports: [gameSearch.sport] as Prisma.InputJsonValue,
        sportLevels: { [gameSearch.sport]: profile.level } as Prisma.InputJsonValue,
        preferredPlayFormat: PlayFormat.both,
        tennisLevel: gameSearch.sport === Sport.tennis ? profile.level : null,
        availableDays: normalizeStringArray(gameSearch.preferredDays) as Prisma.InputJsonValue,
        availableTimeRanges: normalizeStringArray(gameSearch.preferredTimeRanges) as Prisma.InputJsonValue,
        bio: "Симуляция: готов(а) регулярно играть и голосовать за предложенные слоты.",
        onboardingCompleted: true,
        isLookingForGame: true,
        isVerified: true
      }
    });

    if (!excludedUserIds.has(user.id)) {
      users.push(user);
    }
  }

  return users.slice(0, count);
}

export async function POST(_: Request, { params }: { params: { id: string } }) {
  try {
    if (!isSimulationEnabled()) {
      return fail("Симуляция доступна только в demo/dev режиме", 403);
    }

    const user = await requireSessionUser();

    const result = await prisma.$transaction(async (tx) => {
      const gameSearch = await tx.gameSearch.findFirst({
        where: {
          id: params.id,
          createdByUserId: user.id,
          searchType: GameSearchType.regular
        },
        include: {
          responses: {
            include: {
              responderUser: true
            }
          },
          slotProposals: {
            where: {
              status: GameSearchSlotProposalStatus.open
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
            select: {
              id: true
            }
          }
        }
      });

      if (!gameSearch) {
        throw new Error("Регулярный поиск не найден");
      }

      const activeProposal = gameSearch.slotProposals[0] ?? null;
      const approvedResponses = gameSearch.responses.filter((response) => response.status === GameSearchResponseStatus.approved);

      if (activeProposal && approvedResponses.length > 0) {
        const selectedOptions = activeProposal.options.slice(0, Math.min(2, activeProposal.options.length));
        let createdVotes = 0;

        for (const option of selectedOptions) {
          for (const response of approvedResponses) {
            await tx.gameSearchSlotVote.upsert({
              where: {
                optionId_userId: {
                  optionId: option.id,
                  userId: response.responderUserId
                }
              },
              update: {},
              create: {
                optionId: option.id,
                userId: response.responderUserId
              }
            });
            createdVotes += 1;
          }
        }

        const updatedProposal = await tx.gameSearchSlotProposal.findUniqueOrThrow({
          where: {
            id: activeProposal.id
          },
          include: {
            options: {
              include: {
                votes: true
              },
              orderBy: {
                scheduledAt: "asc"
              }
            }
          }
        });

        const finalizedOptions = updatedProposal.options.filter((option) => option.votes.length >= approvedResponses.length);
        if (finalizedOptions.length > 0) {
          const weeklySchedule = buildWeeklySchedule(finalizedOptions);
          const proposedRegularCourtId = commonCourtId(finalizedOptions) ?? gameSearch.preferredCourtId ?? null;

          await tx.gameSearch.update({
            where: {
              id: gameSearch.id
            },
            data: {
              preferredDays: weeklySchedule.preferredDays as Prisma.InputJsonValue,
              preferredTimeRanges: weeklySchedule.preferredTimeRanges as Prisma.InputJsonValue,
              preferredCourtId: proposedRegularCourtId
            }
          });

          if (gameSearch.regularPair) {
            await tx.regularPair.update({
              where: {
                id: gameSearch.regularPair.id
              },
              data: {
                preferredDays: weeklySchedule.preferredDays as Prisma.InputJsonValue,
                preferredTimeRanges: weeklySchedule.preferredTimeRanges as Prisma.InputJsonValue,
                preferredCourtId: proposedRegularCourtId
              }
            });
            await syncRegularPairOccurrences(tx, gameSearch.regularPair.id);
          }

          await tx.gameSearchSlotProposal.update({
            where: {
              id: activeProposal.id
            },
            data: {
              status: GameSearchSlotProposalStatus.closed
            }
          });

          await tx.gameSearchMessage.create({
            data: {
              gameSearchId: gameSearch.id,
              senderUserId: user.id,
              text: `Симуляция: игроки проголосовали за ${finalizedOptions.length} регулярных слота. Расписание будет повторяться каждую неделю.`
            }
          });
        }

        return {
          createdResponses: 0,
          createdVotes,
          finalizedOptions: finalizedOptions.length,
          message: finalizedOptions.length > 0 ? "Игроки проголосовали за слоты" : "Голоса добавлены"
        };
      }

      if (gameSearch.responses.some((response) => response.status === GameSearchResponseStatus.pending)) {
        return {
          createdResponses: 0,
          createdVotes: 0,
          finalizedOptions: 0,
          message: "Отклики уже есть. Одобри игроков, затем предложи регулярные слоты."
        };
      }

      if (approvedResponses.length > 0) {
        return {
          createdResponses: 0,
          createdVotes: 0,
          finalizedOptions: 0,
          message: "Игроки уже одобрены. Предложи слоты, затем запусти симуляцию ещё раз."
        };
      }

      const excludedUserIds = new Set([user.id, ...gameSearch.responses.map((response) => response.responderUserId)]);
      const responders = await ensureSimulationUsers(tx, gameSearch, excludedUserIds, Math.max(2, gameSearch.playersNeeded));

      for (const responder of responders) {
        await tx.gameSearchResponse.upsert({
          where: {
            gameSearchId_responderUserId: {
              gameSearchId: gameSearch.id,
              responderUserId: responder.id
            }
          },
          update: {
            status: GameSearchResponseStatus.pending,
            message: "Симуляция: хочу присоединиться к регулярной игре."
          },
          create: {
            gameSearchId: gameSearch.id,
            responderUserId: responder.id,
            status: GameSearchResponseStatus.pending,
            message: "Симуляция: хочу присоединиться к регулярной игре."
          }
        });
      }

      await tx.gameSearch.update({
        where: {
          id: gameSearch.id
        },
        data: {
          status: GameSearchStatus.in_review,
          isActive: true
        }
      });

      await tx.gameSearchMessage.create({
        data: {
          gameSearchId: gameSearch.id,
          senderUserId: responders[0]?.id ?? user.id,
          text: `Симуляция: ${responders.length} игрока откликнулись на регулярный поиск.`
        }
      });

      return {
        createdResponses: responders.length,
        createdVotes: 0,
        finalizedOptions: 0,
        message: "Добавлены отклики на регулярный поиск"
      };
    });

    return ok(result);
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
