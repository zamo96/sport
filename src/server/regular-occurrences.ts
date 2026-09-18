import {
  Prisma,
  RegularPairOccurrenceConfirmationStatus,
  RegularPairOccurrenceStatus
} from "@prisma/client";

import { prisma } from "@/lib/prisma";
import { formatLocalDateTime, getLocalDateParts, localDateTimeToUtc } from "@/lib/timezone";

type DBLike = Prisma.TransactionClient | typeof prisma;
type TimePreferenceSlot = { hour: number; minute: number; day?: string };

const DAY_INDEX: Record<string, number> = {
  sunday: 0,
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6
};

const TIME_RANGE_HOURS: Record<string, TimePreferenceSlot> = {
  morning: { hour: 9, minute: 0 },
  day: { hour: 14, minute: 0 },
  evening: { hour: 19, minute: 0 }
};

function parseTimePreference(value: string): TimePreferenceSlot | null {
  const [maybeDay, maybeTime] = value.split("@");
  if (maybeDay && maybeTime && DAY_INDEX[maybeDay] !== undefined) {
    const pairedSlot = parseTimePreference(maybeTime);
    return pairedSlot ? { ...pairedSlot, day: maybeDay } : null;
  }

  const rangeSlot = TIME_RANGE_HOURS[value];
  if (rangeSlot) {
    return rangeSlot;
  }

  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(value);
  if (!match) {
    return null;
  }

  return {
    hour: Number(match[1]),
    minute: Number(match[2])
  };
}

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

/**
 * Ближайшие две недели слотов пары. Расписание хранится как «вечер понедельника
 * в 19:00», то есть в стенных часах пары, поэтому и календарь, и час берутся в
 * её зоне: `setHours` в UTC-контейнере ставил слот на 19:00 UTC, и москвич
 * видел 22:00. Зону применяет `localDateTimeToUtc`, так что перевод часов
 * учитывается сам.
 */
function buildOccurrenceSchedule({
  preferredDays,
  preferredTimeRanges,
  timezone,
  now = new Date()
}: {
  preferredDays: string[];
  preferredTimeRanges: string[];
  timezone: string | null | undefined;
  now?: Date;
}) {
  const today = getLocalDateParts(timezone, now);
  const result: Date[] = [];

  for (let offset = 0; offset < 14; offset += 1) {
    // Арифметика по календарю, без зоны: «дата пары плюс N дней».
    const dayDate = new Date(Date.UTC(today.year, today.month - 1, today.day + offset));
    const weekday = dayDate.getUTCDay();
    const dayMatch = preferredDays.some((day) => DAY_INDEX[day] === weekday);
    if (!dayMatch) {
      continue;
    }

    for (const timeRange of preferredTimeRanges) {
      const slot = parseTimePreference(timeRange);
      if (!slot) {
        continue;
      }
      if (slot.day && DAY_INDEX[slot.day] !== weekday) {
        continue;
      }

      const scheduledAt = localDateTimeToUtc(
        timezone,
        dayDate.getUTCFullYear(),
        dayDate.getUTCMonth() + 1,
        dayDate.getUTCDate(),
        slot.hour,
        slot.minute
      );

      if (scheduledAt.getTime() <= now.getTime()) {
        continue;
      }

      result.push(scheduledAt);
    }
  }

  return result.sort((left, right) => left.getTime() - right.getTime());
}

export async function syncRegularPairOccurrences(db: DBLike, regularPairId: string) {
  const regularPair = await db.regularPair.findUnique({
    where: { id: regularPairId },
    include: {
      // Зона организатора — зона пары: расписание пишут в ней же, когда
      // закрывают опрос по слотам.
      createdByUser: { select: { timezone: true } },
      occurrences: {
        include: {
          confirmations: true,
          gameRequest: true
        }
      }
    }
  });

  if (!regularPair) {
    return null;
  }

  const preferredDays = normalizeStringArray(regularPair.preferredDays);
  const preferredTimeRanges = normalizeStringArray(regularPair.preferredTimeRanges);
  const desiredSchedule = buildOccurrenceSchedule({
    preferredDays,
    preferredTimeRanges,
    timezone: regularPair.createdByUser?.timezone ?? null
  });
  const desiredKeys = new Set(desiredSchedule.map((date) => date.toISOString()));

  for (const occurrence of regularPair.occurrences) {
    const isFuture = occurrence.scheduledAt.getTime() > Date.now();
    const anchorKey = (occurrence.scheduleAnchor ?? occurrence.scheduledAt).toISOString();
    const shouldExist = desiredKeys.has(anchorKey);

    if (!isFuture && occurrence.status === RegularPairOccurrenceStatus.pending) {
      await db.regularPairOccurrence.update({
        where: { id: occurrence.id },
        data: { status: RegularPairOccurrenceStatus.expired }
      });
      continue;
    }

    if (isFuture && !shouldExist && occurrence.status === RegularPairOccurrenceStatus.pending) {
      await db.regularPairOccurrence.update({
        where: { id: occurrence.id },
        data: { status: RegularPairOccurrenceStatus.canceled }
      });
    }
  }

  for (const scheduledAt of desiredSchedule) {
    const desiredKey = scheduledAt.toISOString();
    const existing = regularPair.occurrences.find(
      (occurrence) => (occurrence.scheduleAnchor ?? occurrence.scheduledAt).toISOString() === desiredKey
    );

    const occurrence = existing
      ? await db.regularPairOccurrence.update({
          where: { id: existing.id },
          data: {
            scheduleAnchor: existing.scheduleAnchor ?? scheduledAt,
            durationMinutes: existing.durationMinutes ?? 90,
            proposedCourtId: existing.proposedCourtId ?? regularPair.preferredCourtId ?? null,
            sport: regularPair.sport,
            format: regularPair.format
          }
        })
      : await db.regularPairOccurrence.upsert({
          where: {
            regularPairId_scheduledAt: {
              regularPairId,
              scheduledAt
            }
          },
          update: {
            scheduleAnchor: scheduledAt,
            sport: regularPair.sport,
            format: regularPair.format
          },
          create: {
            scheduledAt,
            regularPairId,
            scheduleAnchor: scheduledAt,
            durationMinutes: 90,
            proposedCourtId: regularPair.preferredCourtId ?? null,
            sport: regularPair.sport,
            format: regularPair.format,
            status: RegularPairOccurrenceStatus.pending
          }
        });

    // Multiple read endpoints can sync the same pair concurrently. Insert only
    // missing rows atomically, without resetting either player's existing answer.
    await db.regularPairOccurrenceConfirmation.createMany({
      data: [
        {
          occurrenceId: occurrence.id,
          userId: regularPair.createdByUserId
        },
        {
          occurrenceId: occurrence.id,
          userId: regularPair.partnerUserId
        }
      ],
      skipDuplicates: true
    });
  }

  return db.regularPair.findUnique({
    where: { id: regularPairId },
    include: {
      preferredCourt: true,
      createdByUser: true,
      partnerUser: true,
      match: true,
      occurrences: {
        include: {
          proposedCourt: true,
          gameRequest: true,
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
  });
}

export async function updateRegularPairOccurrenceProposal(
  db: DBLike,
  occurrenceId: string,
  updates: {
    scheduledAt?: Date;
    proposedCourtId?: string | null;
    durationMinutes?: number | null;
  }
) {
  const occurrence = await db.regularPairOccurrence.findUnique({
    where: { id: occurrenceId }
  });

  if (!occurrence) {
    return null;
  }

  if (updates.scheduledAt) {
    const duplicate = await db.regularPairOccurrence.findFirst({
      where: {
        regularPairId: occurrence.regularPairId,
        scheduledAt: updates.scheduledAt,
        id: {
          not: occurrenceId
        }
      }
    });

    if (duplicate) {
      throw new Error("Слот на это время уже существует");
    }
  }

  await db.regularPairOccurrenceConfirmation.updateMany({
    where: {
      occurrenceId
    },
    data: {
      status: RegularPairOccurrenceConfirmationStatus.pending,
      respondedAt: null
    }
  });

  await db.regularPairOccurrence.update({
    where: { id: occurrenceId },
    data: {
      ...(updates.scheduledAt
        ? {
            scheduledAt: updates.scheduledAt,
            scheduleAnchor: occurrence.scheduleAnchor ?? occurrence.scheduledAt
          }
        : {}),
      ...(updates.proposedCourtId !== undefined
        ? {
            proposedCourtId: updates.proposedCourtId
          }
        : {}),
      ...(updates.durationMinutes !== undefined
        ? {
            durationMinutes: updates.durationMinutes
          }
        : {}),
      status: RegularPairOccurrenceStatus.pending
    }
  });

  return db.regularPairOccurrence.findUnique({
    where: { id: occurrenceId },
    include: {
      proposedCourt: true,
      confirmations: {
        include: {
          user: true
        }
      }
    }
  });
}

export async function updateRegularPairOccurrenceConfirmation(
  db: DBLike,
  occurrenceId: string,
  userId: string,
  status: RegularPairOccurrenceConfirmationStatus
) {
  const confirmation = await db.regularPairOccurrenceConfirmation.findFirst({
    where: {
      occurrenceId,
      userId
    },
    include: {
      occurrence: {
        include: {
          regularPair: true,
          confirmations: true
        }
      }
    }
  });

  if (!confirmation) {
    return null;
  }

  await db.regularPairOccurrenceConfirmation.update({
    where: {
      occurrenceId_userId: {
        occurrenceId,
        userId
      }
    },
    data: {
      status,
      respondedAt: new Date()
    }
  });

  const confirmations = await db.regularPairOccurrenceConfirmation.findMany({
    where: { occurrenceId }
  });

  let nextStatus: RegularPairOccurrenceStatus = RegularPairOccurrenceStatus.pending;
  if (confirmations.some((item) => item.status === RegularPairOccurrenceConfirmationStatus.declined)) {
    nextStatus = RegularPairOccurrenceStatus.declined;
  } else if (
    confirmations.length >= 2 &&
    confirmations.every((item) => item.status === RegularPairOccurrenceConfirmationStatus.confirmed)
  ) {
    nextStatus = RegularPairOccurrenceStatus.confirmed;
  }

  const updatedOccurrence = await db.regularPairOccurrence.update({
    where: { id: occurrenceId },
    data: {
      status: nextStatus
    },
    include: {
      proposedCourt: true,
      gameRequest: {
        include: {
          proposedCourt: true
        }
      },
      confirmations: {
        include: {
          user: true
        }
      },
      regularPair: {
        include: {
          createdByUser: true,
          partnerUser: true,
          preferredCourt: true,
          match: true
        }
      }
    }
  });

  if (
    nextStatus === RegularPairOccurrenceStatus.confirmed &&
    !updatedOccurrence.gameRequest &&
    (updatedOccurrence.proposedCourtId ?? updatedOccurrence.regularPair.preferredCourtId)
  ) {
    const createdGameRequest = await db.gameRequest.create({
      data: {
        matchId: updatedOccurrence.regularPair.matchId,
        regularPairOccurrenceId: updatedOccurrence.id,
        createdByUserId: updatedOccurrence.regularPair.createdByUserId,
        matchedUserId: updatedOccurrence.regularPair.partnerUserId,
        proposedCourtId: updatedOccurrence.proposedCourtId ?? updatedOccurrence.regularPair.preferredCourtId!,
        proposedDatetime: updatedOccurrence.scheduledAt,
        durationMinutes: updatedOccurrence.durationMinutes ?? 90,
        sport: updatedOccurrence.sport,
        format: updatedOccurrence.format,
        comment: "Ближайший слот по регулярной паре подтверждён обоими игроками.",
        status: "accepted"
      },
      include: {
        proposedCourt: true
      }
    });

    const scheduleText = `${formatLocalDateTime(
      updatedOccurrence.regularPair.createdByUser?.timezone,
      updatedOccurrence.scheduledAt
    )} · ${createdGameRequest.durationMinutes ?? 90} мин`;

    await db.chatMessage.create({
      data: {
        matchId: updatedOccurrence.regularPair.matchId,
        senderUserId: updatedOccurrence.regularPair.createdByUserId,
        text: `Ближайшая регулярная игра подтверждена: ${scheduleText} · ${createdGameRequest.proposedCourt?.name ?? "Место уточняется"}.`
      }
    });

    await db.chatMessage.create({
      data: {
        matchId: updatedOccurrence.regularPair.matchId,
        gameRequestId: createdGameRequest.id,
        senderUserId: updatedOccurrence.regularPair.createdByUserId,
        text: "Оба игрока подтвердили этот слот. Здесь можно обсудить детали ближайшей игры."
      }
    });

    await db.match.update({
      where: { id: updatedOccurrence.regularPair.matchId },
      data: { updatedAt: new Date() }
    });

    return db.regularPairOccurrence.findUnique({
      where: { id: occurrenceId },
      include: {
        proposedCourt: true,
        gameRequest: {
          include: {
            proposedCourt: true
          }
        },
        confirmations: {
          include: {
            user: true
          }
        },
        regularPair: {
          include: {
            createdByUser: true,
            partnerUser: true,
            preferredCourt: true,
            match: true
          }
        }
      }
    });
  }

  return updatedOccurrence;
}
