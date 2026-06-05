import {
  Prisma,
  RegularPairOccurrenceConfirmationStatus,
  RegularPairOccurrenceStatus
} from "@prisma/client";

import { prisma } from "@/lib/prisma";

type DBLike = Prisma.TransactionClient | typeof prisma;

const DAY_INDEX: Record<string, number> = {
  sunday: 0,
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6
};

const TIME_RANGE_HOURS: Record<string, { hour: number; minute: number }> = {
  morning: { hour: 9, minute: 0 },
  day: { hour: 14, minute: 0 },
  evening: { hour: 19, minute: 0 }
};

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function buildOccurrenceSchedule({
  preferredDays,
  preferredTimeRanges,
  now = new Date()
}: {
  preferredDays: string[];
  preferredTimeRanges: string[];
  now?: Date;
}) {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);

  const result: Date[] = [];

  for (let offset = 0; offset < 14; offset += 1) {
    const dayDate = new Date(start);
    dayDate.setDate(start.getDate() + offset);

    const weekday = dayDate.getDay();
    const dayMatch = preferredDays.some((day) => DAY_INDEX[day] === weekday);
    if (!dayMatch) {
      continue;
    }

    for (const timeRange of preferredTimeRanges) {
      const slot = TIME_RANGE_HOURS[timeRange];
      if (!slot) {
        continue;
      }

      const scheduledAt = new Date(dayDate);
      scheduledAt.setHours(slot.hour, slot.minute, 0, 0);

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
    preferredTimeRanges
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
      : await db.regularPairOccurrence.create({
          data: {
            regularPairId,
            scheduledAt,
            scheduleAnchor: scheduledAt,
            durationMinutes: 90,
            proposedCourtId: regularPair.preferredCourtId ?? null,
            sport: regularPair.sport,
            format: regularPair.format,
            status: RegularPairOccurrenceStatus.pending
          }
        });

    await db.regularPairOccurrenceConfirmation.upsert({
      where: {
        occurrenceId_userId: {
          occurrenceId: occurrence.id,
          userId: regularPair.createdByUserId
        }
      },
      update: {},
      create: {
        occurrenceId: occurrence.id,
        userId: regularPair.createdByUserId
      }
    });

    await db.regularPairOccurrenceConfirmation.upsert({
      where: {
        occurrenceId_userId: {
          occurrenceId: occurrence.id,
          userId: regularPair.partnerUserId
        }
      },
      update: {},
      create: {
        occurrenceId: occurrence.id,
        userId: regularPair.partnerUserId
      }
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

    const scheduleText = `${updatedOccurrence.scheduledAt.toLocaleString("ru-RU", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    })} · ${createdGameRequest.durationMinutes ?? 90} мин`;

    await db.chatMessage.create({
      data: {
        matchId: updatedOccurrence.regularPair.matchId,
        senderUserId: updatedOccurrence.regularPair.createdByUserId,
        text: `Ближайшая регулярная игра подтверждена: ${scheduleText} · ${createdGameRequest.proposedCourt.name}.`
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
