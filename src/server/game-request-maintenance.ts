import { GameRequestStatus, Prisma } from "@prisma/client";

import { sendPushToUser } from "@/lib/push";
import { formatLocalDateTime, getLocalDateParts } from "@/lib/timezone";
import { prisma } from "@/lib/prisma";
import { getRealtimeRedis, publishRealtimeEventToUsers } from "@/server/realtime";

const REMINDER_KEY_PREFIX = "tennis:game-request-reminder";
const REMINDER_KEY_TTL_SECONDS = 60 * 60 * 36;

/**
 * Два окна в локальной зоне игрока, а не в московской: общий серверный слот
 * «до 15:00 / после» открывался в полночь по Москве и будил половину карты.
 * Часы выбраны в промежутках между слотами дайджеста (12:00 и 18:00), а конец
 * окна — до 22:00, чтобы догоняющий запуск не вылез в тихие часы.
 */
const REMINDER_WINDOWS = [
  { slot: "morning", startHour: 10, endHour: 12 },
  { slot: "evening", startHour: 20, endHour: 22 }
] as const;

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

/**
 * Окно считается в зоне игрока и возвращает ключ его календарного дня: иначе
 * и час отправки, и граница суток брались бы с сервера.
 */
export function resolveReminderWindow(now: Date, timezone: string | null | undefined) {
  const parts = getLocalDateParts(timezone, now);
  const open = REMINDER_WINDOWS.find((window) => parts.hour >= window.startHour && parts.hour < window.endHour);

  return open ? { dateKey: parts.dateKey, slot: open.slot } : null;
}

/**
 * Cron ходит каждые 5 минут, а окна локальные: сначала дешёвым группирующим
 * запросом выясняем, у кого сейчас вообще открыто окно. В большинстве прогонов
 * дальше идти не нужно, и заодно `take` не тратится на игроков, у которых ночь.
 */
async function resolveOpenZoneFilter(now: Date): Promise<Prisma.UserWhereInput | null> {
  const zones = await prisma.user.groupBy({
    by: ["timezone"],
    where: { notificationGames: true }
  });
  const openZones = zones
    .map((zone) => zone.timezone)
    .filter((timezone) => resolveReminderWindow(now, timezone) !== null);

  if (openZones.length === 0) {
    return null;
  }

  const namedZones = openZones.filter((timezone): timezone is string => timezone !== null);

  // Пустая зона — это откат на Москву, поэтому такие игроки идут вместе с ней.
  if (openZones.length === namedZones.length) {
    return { timezone: { in: namedZones } };
  }

  return { OR: [{ timezone: { in: namedZones } }, { timezone: null }] };
}

export async function sendPendingGameRequestReminders(now = new Date()) {
  const redis = getRealtimeRedis();
  if (!redis) {
    return;
  }

  const zoneFilter = await resolveOpenZoneFilter(now);

  if (!zoneFilter) {
    return;
  }

  const pendingRequests = await prisma.gameRequest.findMany({
    where: {
      status: GameRequestStatus.pending,
      proposedDatetime: {
        gt: now
      },
      matchedUser: {
        notificationGames: true,
        ...zoneFilter
      }
    },
    include: {
      proposedCourt: true,
      matchedUser: {
        select: {
          id: true,
          notificationSound: true,
          timezone: true
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
      // Окно проверяем до похода в Redis: в большинстве прогонов у игрока
      // сейчас не то время суток, и ключ трогать незачем.
      const window = resolveReminderWindow(now, request.matchedUser.timezone);

      if (!window) {
        return;
      }

      const key = `${REMINDER_KEY_PREFIX}:${request.id}:${window.dateKey}:${window.slot}`;
      const shouldSend = await redis.set(key, "1", "EX", REMINDER_KEY_TTL_SECONDS, "NX");

      if (shouldSend !== "OK") {
        return;
      }

      await sendPushToUser({
        userId: request.matchedUserId,
        title: "Подтверди игру",
        body: `${request.proposedCourt?.name ?? "Место уточняется"} · ${formatLocalDateTime(request.matchedUser.timezone, request.proposedDatetime, { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" })}`,
        href: `/play/games/${request.id}`,
        sound: request.matchedUser.notificationSound ?? true
      });
    })
  );
}
