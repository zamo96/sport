import { GameRequestStatus, GameSearchResponseStatus, GameSearchStatus, Prisma } from "@prisma/client";

import { translateServer } from "@/lib/i18n/server";
import { pluralKeySuffix } from "@/lib/i18n/server/notifications";
import type { SupportedLocale } from "@/lib/locales";
import { prisma } from "@/lib/prisma";
import { formatLocalDateTime, getLocalDateParts } from "@/lib/timezone";
import {
  ACTIVE_PUSH_DEVICE,
  collectCampaignResult,
  emptyCampaignStats,
  HAS_ACTIVE_PUSH_DEVICE,
  sendCampaignPush
} from "@/server/notification-campaigns";

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

/** Мгновенный пуш об отклике уже ушёл — здесь напоминание, если автор молчит. */
const RESPONSE_WAIT_MS = 3 * HOUR_MS;
/** У срочного поиска ждать три часа поздно: игра начнётся раньше напоминания. */
const URGENT_RESPONSE_WAIT_MS = 45 * MINUTE_MS;
const URGENT_HORIZON_MS = 6 * HOUR_MS;
/**
 * Двое суток молчания — это тоже ответ. Ключ дедупа даёт один пуш в сутки,
 * поэтому за окно человек получит максимум два напоминания и дальше тишина.
 */
const RESPONSE_MAX_AGE_MS = 2 * DAY_MS;

/** Игра идёт час-полтора: спрашивать про итог раньше нечего. */
const OUTCOME_GRACE_MS = 4 * HOUR_MS;
const OUTCOME_MAX_AGE_MS = 2 * DAY_MS;

/** Прогон идёт каждые 5 минут, поэтому одной пачки с запасом хватает. */
const BATCH_SIZE = 200;

/**
 * Рубильник напоминаний, по умолчанию выключенный: как и у lifecycle-рассылок,
 * это даёт выкатить код, посмотреть аудиторию через `?dryRun=1` и только потом
 * начать писать людям. На dry-run он не влияет.
 */
export function pendingActionRemindersEnabled() {
  return ["1", "true", "yes"].includes((process.env.PENDING_ACTION_REMINDERS_ENABLED ?? "").trim().toLowerCase());
}

export type PendingActionRunOptions = {
  /** Прогон без отправки: считает аудиторию и собирает примеры текстов. */
  dryRun?: boolean;
};

/**
 * Напоминания тому, от кого ждут действия. В отличие от lifecycle-кампаний это
 * не рассылка, а долг перед конкретным человеком, поэтому кампании
 * транзакционные: общий дневной лимит они не тратят, но тихие часы соблюдают —
 * до утра такое подождёт.
 */
export async function runPendingActionReminders(now = new Date(), options: PendingActionRunOptions = {}) {
  const enabled = options.dryRun ? true : pendingActionRemindersEnabled();

  if (!enabled) {
    return {
      enabled: false,
      searchResponseWaiting: emptyCampaignStats(),
      gameOutcomePending: emptyCampaignStats()
    };
  }

  return {
    enabled: true,
    searchResponseWaiting: await runSearchResponseWaiting(now, options),
    gameOutcomePending: await runGameOutcomePending(now, options)
  };
}

function pairKey(left: string, right: string) {
  return [left, right].sort().join(":");
}

/**
 * Экран прячет заблокированную пару, значит и напоминание по ней звало бы в
 * пустоту. Блокировки тянем одним запросом на весь прогон и фильтруем в памяти:
 * фильтр зависит от пары, а не от одного пользователя, и в `where` не ложится.
 */
async function loadBlockedPairs(userIds: string[]) {
  if (userIds.length === 0) {
    return () => false;
  }

  const blocks = await prisma.block.findMany({
    where: {
      OR: [{ blockerUserId: { in: userIds } }, { blockedUserId: { in: userIds } }]
    },
    select: { blockerUserId: true, blockedUserId: true }
  });

  const blocked = new Set(blocks.map((block) => pairKey(block.blockerUserId, block.blockedUserId)));

  return (left: string, right: string) => blocked.has(pairKey(left, right));
}

function intlLocale(locale: SupportedLocale) {
  return locale === "ru" ? "ru-RU" : "en-GB";
}

function playerName(locale: SupportedLocale, name: string | null | undefined) {
  return name?.trim() || translateServer(locale, "push.player.fallback");
}

/**
 * Автор поиска получил отклик и молчит. Мгновенный пуш уходит из
 * `POST /game-searches/[id]/respond`, здесь — напоминание, пока на том конце
 * человек ждёт решения.
 */
export async function runSearchResponseWaiting(now = new Date(), options: PendingActionRunOptions = {}) {
  const stats = emptyCampaignStats();

  const responses = await prisma.gameSearchResponse.findMany({
    where: {
      status: GameSearchResponseStatus.pending,
      createdAt: { gte: new Date(now.getTime() - RESPONSE_MAX_AGE_MS) },
      OR: [
        { createdAt: { lte: new Date(now.getTime() - RESPONSE_WAIT_MS) } },
        {
          createdAt: { lte: new Date(now.getTime() - URGENT_RESPONSE_WAIT_MS) },
          gameSearch: {
            hotStartsAt: { gt: now, lte: new Date(now.getTime() + URGENT_HORIZON_MS) }
          }
        }
      ],
      // Ушедший из приложения игрок ответа уже не ждёт.
      responderUser: { accountStatus: "active" },
      gameSearch: {
        isActive: true,
        // Отклик переводит поиск в `in_review`, поэтому один `active` не годится.
        status: { in: [GameSearchStatus.active, GameSearchStatus.in_review] },
        // Срочные поиски закрываются лениво, на чтении экрана: без явной
        // проверки напоминание звало бы в уже начавшуюся игру.
        AND: [
          { OR: [{ hotStartsAt: null }, { hotStartsAt: { gt: now } }] },
          { OR: [{ scheduledAt: null }, { scheduledAt: { gt: now } }] }
        ],
        createdByUser: {
          accountStatus: "active",
          notificationGames: true,
          ...HAS_ACTIVE_PUSH_DEVICE
        }
      }
    },
    select: {
      id: true,
      gameSearchId: true,
      responderUserId: true,
      responderUser: { select: { name: true } },
      gameSearch: {
        select: {
          createdByUserId: true,
          createdByUser: { select: { timezone: true } }
        }
      }
    },
    orderBy: { createdAt: "asc" },
    take: BATCH_SIZE
  });

  if (responses.length === 0) {
    return stats;
  }

  const isBlockedPair = await loadBlockedPairs(
    Array.from(
      new Set(responses.flatMap((response) => [response.responderUserId, response.gameSearch.createdByUserId]))
    )
  );

  type OwnerBucket = {
    timezone: string | null;
    searchIds: Set<string>;
    firstSearchId: string;
    firstResponderName: string | null;
    responseIds: string[];
  };

  const owners = new Map<string, OwnerBucket>();

  for (const response of responses) {
    const ownerId = response.gameSearch.createdByUserId;

    if (isBlockedPair(ownerId, response.responderUserId)) {
      continue;
    }

    const bucket = owners.get(ownerId) ?? {
      timezone: response.gameSearch.createdByUser.timezone,
      searchIds: new Set<string>(),
      firstSearchId: response.gameSearchId,
      firstResponderName: response.responderUser.name,
      responseIds: []
    };

    bucket.searchIds.add(response.gameSearchId);
    bucket.responseIds.push(response.id);
    owners.set(ownerId, bucket);
  }

  for (const [ownerId, bucket] of owners) {
    stats.scanned += 1;

    const count = bucket.responseIds.length;
    const suffix = (locale: SupportedLocale) => pluralKeySuffix(locale, count);
    // Пуш обязан приводить на экран, где отклик видно: один поиск — прямо в
    // него, несколько — в список «Мои поиски».
    const href = bucket.searchIds.size === 1 ? `/play/searches/${bucket.firstSearchId}` : "/play/searches";

    const result = await sendCampaignPush({
      userId: ownerId,
      campaignKey: "search_response_waiting",
      dedupeKey: `search_response_waiting:${ownerId}:${getLocalDateParts(bucket.timezone, now).dateKey}`,
      content: (locale) => {
        // Имя стоит в заголовке, счётчик — во множественных формах: и то и
        // другое отдаём обеим строкам, лишний плейсхолдер просто не встретится.
        const values = { count, name: playerName(locale, bucket.firstResponderName) };

        return {
          title: translateServer(locale, `push.searchResponseWaiting.title.${suffix(locale)}`, values),
          body: translateServer(locale, `push.searchResponseWaiting.body.${suffix(locale)}`, values)
        };
      },
      href,
      context: { responseIds: bucket.responseIds, searchIds: Array.from(bucket.searchIds) },
      now,
      dryRun: options.dryRun
    });

    collectCampaignResult(stats, ownerId, result);
  }

  return stats;
}

/**
 * Игра прошла, но никто не отметил, состоялась ли она. Отметить может любой из
 * двоих, поэтому напоминание уходит обоим: кто первым откроет, тот и закроет
 * вопрос для пары.
 */
export async function runGameOutcomePending(now = new Date(), options: PendingActionRunOptions = {}) {
  const stats = emptyCampaignStats();

  const participantSelect = {
    id: true,
    name: true,
    timezone: true,
    notificationGames: true,
    // Недостижимого игрока отсеиваем здесь: движок сделал бы на него четыре
    // запроса и всё равно вернул `no_device`.
    pushDevices: {
      where: ACTIVE_PUSH_DEVICE,
      select: { id: true },
      take: 1
    }
  } satisfies Prisma.UserSelect;

  const requests = await prisma.gameRequest.findMany({
    where: {
      status: GameRequestStatus.accepted,
      outcome: null,
      proposedDatetime: {
        lte: new Date(now.getTime() - OUTCOME_GRACE_MS),
        gte: new Date(now.getTime() - OUTCOME_MAX_AGE_MS)
      },
      createdByUser: { accountStatus: "active" },
      matchedUser: { accountStatus: "active" },
      // Игра, о которой некому написать, не должна попадать в пачку.
      OR: [{ createdByUser: HAS_ACTIVE_PUSH_DEVICE }, { matchedUser: HAS_ACTIVE_PUSH_DEVICE }]
    },
    select: {
      id: true,
      sharedRootId: true,
      proposedDatetime: true,
      createdByUser: { select: participantSelect },
      matchedUser: { select: participantSelect }
    },
    orderBy: { proposedDatetime: "asc" },
    take: BATCH_SIZE
  });

  if (requests.length === 0) {
    return stats;
  }

  const isBlockedPair = await loadBlockedPairs(
    Array.from(new Set(requests.flatMap((request) => [request.createdByUser.id, request.matchedUser.id])))
  );

  type ParticipantBucket = {
    timezone: string | null;
    /** Самая давняя неотмеченная игра: с неё и начинаем разговор. */
    oldestRequestId: string;
    oldestDatetime: Date;
    oldestOpponentName: string | null;
    /**
     * Групповая игра — это несколько строк-приглашений с общим корнем, но для
     * человека она одна: считаем события, а не строки, иначе пуш обещал бы три
     * игры там, где была одна.
     */
    eventKeys: Set<string>;
    requestIds: string[];
  };

  const participants = new Map<string, ParticipantBucket>();

  for (const request of requests) {
    if (isBlockedPair(request.createdByUser.id, request.matchedUser.id)) {
      continue;
    }

    for (const [participant, opponent] of [
      [request.createdByUser, request.matchedUser],
      [request.matchedUser, request.createdByUser]
    ] as const) {
      if (!participant.notificationGames || participant.pushDevices.length === 0) {
        continue;
      }

      const bucket = participants.get(participant.id) ?? {
        timezone: participant.timezone,
        // Запросы отсортированы по времени, поэтому первая же игра и есть
        // самая давняя — пересчитывать ничего не нужно.
        oldestRequestId: request.id,
        oldestDatetime: request.proposedDatetime,
        oldestOpponentName: opponent.name,
        eventKeys: new Set<string>(),
        requestIds: []
      };

      bucket.eventKeys.add(request.sharedRootId ?? request.id);
      bucket.requestIds.push(request.id);
      participants.set(participant.id, bucket);
    }
  }

  for (const [userId, bucket] of participants) {
    stats.scanned += 1;

    const count = bucket.eventKeys.size;
    const suffix = (locale: SupportedLocale) => pluralKeySuffix(locale, count);

    const result = await sendCampaignPush({
      userId,
      campaignKey: "game_outcome_pending",
      dedupeKey: `game_outcome_pending:${userId}:${getLocalDateParts(bucket.timezone, now).dateKey}`,
      content: (locale) => {
        const when = formatLocalDateTime(
          bucket.timezone,
          bucket.oldestDatetime,
          { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" },
          intlLocale(locale)
        );

        return {
          title: translateServer(locale, `push.gameOutcome.title.${suffix(locale)}`, { count }),
          body: translateServer(locale, `push.gameOutcome.body.${suffix(locale)}`, {
            when,
            opponent: playerName(locale, bucket.oldestOpponentName)
          })
        };
      },
      // Списка игр нет ни в вебе, ни в приложении — ведём в самую давнюю
      // неотмеченную игру, остальные видно там же, в ленте ближайших.
      href: `/play/games/${bucket.oldestRequestId}`,
      context: { requestIds: bucket.requestIds },
      now,
      dryRun: options.dryRun
    });

    collectCampaignResult(stats, userId, result);
  }

  return stats;
}
