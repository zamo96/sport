import { GameRequestStatus } from "@prisma/client";

import { sendPushToUser } from "@/lib/push";
import { prisma } from "@/lib/prisma";
import { getRealtimeRedis, publishRealtimeEventToUsers } from "@/server/realtime";

const REMINDER_KEY_PREFIX = "tennis:game-request-reminder";
const REMINDER_KEY_TTL_SECONDS = 60 * 60 * 36;

export async function runGameRequestMaintenance(options: { sendReminders?: boolean } = {}) {
  await expirePendingGameRequests();

  if (options.sendReminders !== false) {
    await sendPendingGameRequestReminders();
  }
}

async function expirePendingGameRequests() {
  const now = new Date();
  const expiredPendingRequests = await prisma.gameRequest.findMany({
    where: {
      status: GameRequestStatus.pending,
      proposedDatetime: {
        lte: now
      }
    },
    select: {
      id: true,
      sharedRootId: true
    }
  });

  if (expiredPendingRequests.length === 0) {
    return;
  }

  const rootIds = Array.from(new Set(expiredPendingRequests.map((request) => request.sharedRootId ?? request.id)));
  const relatedRequests = await prisma.gameRequest.findMany({
    where: {
      OR: [
        {
          id: {
            in: rootIds
          }
        },
        {
          sharedRootId: {
            in: rootIds
          }
        }
      ]
    },
    include: {
      proposedCourt: true,
      createdByUser: {
        select: {
          id: true,
          name: true,
          notificationGames: true,
          notificationSound: true
        }
      },
      matchedUser: {
        select: {
          id: true,
          name: true,
          notificationGames: true,
          notificationSound: true
        }
      }
    }
  });

  const groups = new Map<string, typeof relatedRequests>();
  for (const request of relatedRequests) {
    const rootId = request.sharedRootId ?? request.id;
    const group = groups.get(rootId) ?? [];
    group.push(request);
    groups.set(rootId, group);
  }

  const requestsToCancel = Array.from(groups.values()).flatMap((group) => {
    const isGrouped = group.length > 1;
    return group.filter((request) =>
      isGrouped
        ? request.status !== GameRequestStatus.canceled && request.status !== GameRequestStatus.declined
        : request.status === GameRequestStatus.pending
    );
  });

  if (requestsToCancel.length === 0) {
    return;
  }

  const cancelIds = requestsToCancel.map((request) => request.id);
  const nowMessage = "Время игры наступило, но подтверждения не было. Договоренность отменена автоматически.";

  await prisma.$transaction(async (tx) => {
    await tx.gameRequest.updateMany({
      where: {
        id: {
          in: cancelIds
        }
      },
      data: {
        status: GameRequestStatus.canceled
      }
    });

    await tx.chatMessage.createMany({
      data: requestsToCancel.flatMap((request) => [
        {
          matchId: request.matchId,
          gameRequestId: null,
          senderUserId: request.createdByUserId,
          text: nowMessage
        },
        {
          matchId: request.matchId,
          gameRequestId: request.id,
          senderUserId: request.createdByUserId,
          text: nowMessage
        }
      ])
    });

    const touchedMatchIds = Array.from(new Set(requestsToCancel.map((request) => request.matchId)));
    await Promise.all(
      touchedMatchIds.map((matchId) =>
        tx.match.update({
          where: { id: matchId },
          data: { updatedAt: new Date() }
        })
      )
    );
  });

  await Promise.all(
    requestsToCancel.map(async (request) => {
      const recipients = [request.createdByUser, request.matchedUser];

      await publishRealtimeEventToUsers(
        recipients.map((recipient) => recipient.id),
        {
          type: "game_request_updated",
          matchId: request.matchId,
          gameRequestId: request.id,
          status: GameRequestStatus.canceled,
          href: `/play/games/${request.id}`
        }
      );

      await Promise.all(
        recipients.map((recipient) => {
          if (!recipient.notificationGames) {
            return Promise.resolve();
          }

          return sendPushToUser({
            userId: recipient.id,
            title: "Игра отменена автоматически",
            body: `${request.proposedCourt?.name ?? "Место уточняется"} · подтверждение не пришло до начала игры.`,
            href: `/play/games/${request.id}`,
            sound: recipient.notificationSound ?? true
          });
        })
      );
    })
  );
}

async function sendPendingGameRequestReminders() {
  const redis = getRealtimeRedis();
  if (!redis) {
    return;
  }

  const now = new Date();
  const { dayKey, slot } = getMoscowReminderWindow(now);
  const pendingRequests = await prisma.gameRequest.findMany({
    where: {
      status: GameRequestStatus.pending,
      proposedDatetime: {
        gt: now
      },
      matchedUser: {
        notificationGames: true
      }
    },
    include: {
      proposedCourt: true,
      matchedUser: {
        select: {
          id: true,
          name: true,
          notificationSound: true
        }
      }
    },
    orderBy: {
      proposedDatetime: "asc"
    },
    take: 100
  });

  await Promise.all(
    pendingRequests.map(async (request) => {
      const key = `${REMINDER_KEY_PREFIX}:${request.id}:${dayKey}:${slot}`;
      const shouldSend = await redis.set(key, "1", "EX", REMINDER_KEY_TTL_SECONDS, "NX");

      if (shouldSend !== "OK") {
        return;
      }

      await sendPushToUser({
        userId: request.matchedUserId,
        title: "Подтверди игру",
        body: `${request.proposedCourt?.name ?? "Место уточняется"} · ${request.proposedDatetime.toLocaleString("ru-RU")}`,
        href: `/play/games/${request.id}`,
        sound: request.matchedUser.notificationSound ?? true
      });
    })
  );
}

function getMoscowReminderWindow(date: Date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Moscow",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hour12: false
  })
    .formatToParts(date)
    .reduce<Record<string, string>>((acc, part) => {
      if (part.type !== "literal") {
        acc[part.type] = part.value;
      }
      return acc;
    }, {});

  const hour = Number(parts.hour ?? "0");

  return {
    dayKey: `${parts.year}-${parts.month}-${parts.day}`,
    slot: hour < 15 ? "morning" : "evening"
  };
}
