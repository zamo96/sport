import { Prisma } from "@prisma/client";

import { DAY_OPTIONS, TIME_RANGE_OPTIONS } from "@/lib/constants";
import { translateServer } from "@/lib/i18n/server";
import { pluralKeySuffix } from "@/lib/i18n/server/notifications";
import { prisma } from "@/lib/prisma";
import { normalizeSports } from "@/lib/sport-levels";
import { getLocalDateParts } from "@/lib/timezone";
import { getIncomingLikePlayers } from "@/server/app-data";
import { countDiscoverCandidates, summarizeDiscoverCandidates } from "@/server/discover";
import {
  sendCampaignPush,
  type CampaignPreview,
  type CampaignSendStatus
} from "@/server/notification-campaigns";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** Даём человеку самому закончить онбординг, прежде чем напоминать. */
const ONBOARDING_MIN_AGE_MS = 2 * HOUR_MS;
const ONBOARDING_MAX_AGE_MS = 7 * DAY_MS;
/** Совпадает с кулдауном кампании в реестре: движок всё равно отсеет остальных. */
const ONBOARDING_COOLDOWN_MS = 48 * HOUR_MS;

const FIRST_PLAYERS_MIN_AGE_MS = DAY_MS;
const FIRST_PLAYERS_MAX_AGE_MS = 14 * DAY_MS;
/** Меньше трёх карточек — пуш приведёт на пустой экран, это хуже молчания. */
const MIN_CANDIDATES_FOR_PUSH = 3;

const NEW_PLAYERS_MIN_ACCOUNT_AGE_MS = 3 * DAY_MS;
const NEW_PLAYERS_MIN_IDLE_MS = 2 * DAY_MS;
const NEW_PLAYERS_COOLDOWN_MS = 48 * HOUR_MS;
/** Один новый профиль — не повод будить человека. */
const MIN_NEW_CANDIDATES = 2;

const LIKES_MIN_AGE_MS = DAY_MS;
const LIKES_MIN_IDLE_MS = DAY_MS;
const LIKES_COOLDOWN_MS = 24 * HOUR_MS;

const WEEK_MS = 7 * DAY_MS;
const TRAINING_COOLDOWN_MS = WEEK_MS;

const WIN_BACK_MIN_IDLE_MS = WEEK_MS;
/** Дальше двух месяцев молчания перестаём писать: это уже не возврат, а спам. */
const WIN_BACK_MAX_IDLE_MS = 60 * DAY_MS;
const WIN_BACK_COOLDOWN_MS = WEEK_MS;

const USER_BATCH_SIZE = 200;
/** Подсчёт кандидатов идёт в памяти, поэтому ограничиваем работу одного прогона. */
const MAX_SCORED_USERS_PER_RUN = 200;

const HAS_ACTIVE_DEVICE = {
  pushDevices: {
    some: {
      platform: "ios",
      isActive: true
    }
  }
} satisfies Prisma.UserWhereInput;

export type CampaignRunOptions = {
  /** Прогон без отправки: считает аудиторию и собирает примеры текстов. */
  dryRun?: boolean;
};

type CampaignStats = Record<CampaignSendStatus, number> & {
  scanned: number;
  samples: Array<{ userId: string } & CampaignPreview>;
};

const MAX_SAMPLES = 5;

function emptyStats(): CampaignStats {
  return { sent: 0, holdout: 0, duplicate: 0, skipped: 0, failed: 0, scanned: 0, samples: [] };
}

function collect(stats: CampaignStats, userId: string, result: Awaited<ReturnType<typeof sendCampaignPush>>) {
  stats[result.status] += 1;

  if (result.preview && stats.samples.length < MAX_SAMPLES) {
    stats.samples.push({ userId, ...result.preview });
  }
}

/**
 * Кампании идут строго последовательно и в порядке ценности: дневной лимит один
 * на всех, и при параллельном запуске две кампании успели бы проверить лимит до
 * того, как любая из них записала доставку.
 */
export async function runLifecycleCampaigns(now = new Date(), options: CampaignRunOptions = {}) {
  return {
    onboardingIncomplete: await runOnboardingIncomplete(now, options),
    likesWaiting: await runLikesWaiting(now, options),
    firstPlayersReady: await runFirstPlayersReady(now, options),
    newPlayersArrived: await runNewPlayersArrived(now, options),
    trainingNudge: await runTrainingNudge(now, options),
    winBack: await runWinBack(now, options)
  };
}

/**
 * Человек зарегистрировался, но не дошёл до конца анкеты: без уровня и
 * расписания подобрать ему некого, поэтому это самая дырявая точка воронки.
 */
export async function runOnboardingIncomplete(now = new Date(), options: CampaignRunOptions = {}) {
  const stats = emptyStats();

  const users = await prisma.user.findMany({
    where: {
      accountStatus: "active",
      onboardingCompleted: false,
      createdAt: {
        gte: new Date(now.getTime() - ONBOARDING_MAX_AGE_MS),
        lte: new Date(now.getTime() - ONBOARDING_MIN_AGE_MS)
      },
      // cron ходит каждые 5 минут: отсекаем уже написавших здесь, чтобы не
      // гонять их через движок по четыре запроса на каждом прогоне.
      notificationDeliveries: {
        none: {
          campaignKey: "onboarding_incomplete",
          createdAt: {
            gte: new Date(now.getTime() - ONBOARDING_COOLDOWN_MS)
          }
        }
      },
      ...HAS_ACTIVE_DEVICE
    },
    select: { id: true, timezone: true },
    orderBy: { createdAt: "asc" },
    take: USER_BATCH_SIZE
  });

  for (const user of users) {
    stats.scanned += 1;

    const result = await sendCampaignPush({
      userId: user.id,
      campaignKey: "onboarding_incomplete",
      dedupeKey: `onboarding_incomplete:${user.id}:${getLocalDateParts(user.timezone, now).dateKey}`,
      content: (locale) => ({
        title: translateServer(locale, "push.onboarding.title"),
        body: translateServer(locale, "push.onboarding.body")
      }),
      href: "/onboarding",
      now,
      dryRun: options.dryRun
    });

    collect(stats, user.id, result);
  }

  return stats;
}

/**
 * Первые сутки без единого свайпа. Пуш уходит только если игроку реально есть
 * что показать — иначе он открывает пустой поиск и удаляет приложение.
 */
export async function runFirstPlayersReady(now = new Date(), options: CampaignRunOptions = {}) {
  const stats = emptyStats();

  const users = await prisma.user.findMany({
    where: {
      accountStatus: "active",
      onboardingCompleted: true,
      isVerified: true,
      createdAt: {
        gte: new Date(now.getTime() - FIRST_PLAYERS_MAX_AGE_MS),
        lte: new Date(now.getTime() - FIRST_PLAYERS_MIN_AGE_MS)
      },
      swipesSent: {
        none: {}
      },
      notificationDeliveries: {
        none: {
          campaignKey: "first_players_ready"
        }
      },
      ...HAS_ACTIVE_DEVICE
    },
    select: { id: true },
    orderBy: { createdAt: "asc" },
    take: MAX_SCORED_USERS_PER_RUN
  });

  for (const user of users) {
    stats.scanned += 1;

    const candidateCount = await countDiscoverCandidates(user.id);

    if (candidateCount < MIN_CANDIDATES_FOR_PUSH) {
      stats.skipped += 1;
      continue;
    }

    const result = await sendCampaignPush({
      userId: user.id,
      campaignKey: "first_players_ready",
      // Кампания разовая: один ключ на игрока за всё время.
      dedupeKey: `first_players_ready:${user.id}`,
      content: (locale) => ({
        title: translateServer(locale, "push.firstPlayers.title"),
        body: translateServer(locale, "push.firstPlayers.body", { count: candidateCount })
      }),
      href: "/discover",
      context: { candidateCount },
      now,
      dryRun: options.dryRun
    });

    collect(stats, user.id, result);
  }

  return stats;
}

/**
 * Кто-то лайкнул, но человек не вернулся. Мгновенный пуш на лайк уже уходит из
 * `POST /swipes`, здесь — напоминание через сутки.
 */
export async function runLikesWaiting(now = new Date(), options: CampaignRunOptions = {}) {
  const stats = emptyStats();

  const users = await prisma.user.findMany({
    where: {
      accountStatus: "active",
      onboardingCompleted: true,
      isVerified: true,
      lastActiveAt: {
        lt: new Date(now.getTime() - LIKES_MIN_IDLE_MS)
      },
      swipesReceived: {
        some: {
          action: {
            in: ["like", "superlike"]
          },
          createdAt: {
            lte: new Date(now.getTime() - LIKES_MIN_AGE_MS)
          }
        }
      },
      notificationDeliveries: {
        none: {
          campaignKey: "likes_waiting",
          createdAt: {
            gte: new Date(now.getTime() - LIKES_COOLDOWN_MS)
          }
        }
      },
      ...HAS_ACTIVE_DEVICE
    },
    select: { id: true, timezone: true },
    orderBy: { lastActiveAt: "asc" },
    take: MAX_SCORED_USERS_PER_RUN
  });

  for (const user of users) {
    stats.scanned += 1;

    // Ровно тот же запрос, что рисует вкладку «Вас лайкнули»: если он пуст,
    // экран после пуша тоже будет пустым.
    const waiting = await getIncomingLikePlayers(user.id);

    if (waiting.length === 0) {
      stats.skipped += 1;
      continue;
    }

    const result = await sendCampaignPush({
      userId: user.id,
      campaignKey: "likes_waiting",
      dedupeKey: `likes_waiting:${user.id}:${getLocalDateParts(user.timezone, now).dateKey}`,
      content: (locale) => ({
        title: translateServer(locale, "push.likesWaiting.title"),
        body: translateServer(
          locale,
          `push.likesWaiting.body.${pluralKeySuffix(locale, waiting.length)}`,
          { count: waiting.length }
        )
      }),
      href: "/discover?view=likes",
      context: { waiting: waiting.length },
      now,
      dryRun: options.dryRun
    });

    collect(stats, user.id, result);
  }

  return stats;
}

/** Игрок давно не заходил, а рядом за это время появились новые профили. */
export async function runNewPlayersArrived(now = new Date(), options: CampaignRunOptions = {}) {
  const stats = emptyStats();

  const users = await prisma.user.findMany({
    where: {
      accountStatus: "active",
      onboardingCompleted: true,
      isVerified: true,
      createdAt: {
        lte: new Date(now.getTime() - NEW_PLAYERS_MIN_ACCOUNT_AGE_MS)
      },
      lastActiveAt: {
        lt: new Date(now.getTime() - NEW_PLAYERS_MIN_IDLE_MS)
      },
      notificationDeliveries: {
        none: {
          campaignKey: "new_players_arrived",
          createdAt: {
            gte: new Date(now.getTime() - NEW_PLAYERS_COOLDOWN_MS)
          }
        }
      },
      ...HAS_ACTIVE_DEVICE
    },
    select: { id: true, lastActiveAt: true, timezone: true },
    orderBy: { lastActiveAt: "asc" },
    take: MAX_SCORED_USERS_PER_RUN
  });

  for (const user of users) {
    stats.scanned += 1;

    const { fresh } = await summarizeDiscoverCandidates(user.id, {
      filters: { view: "swipe" },
      newerThan: user.lastActiveAt
    });

    if (fresh < MIN_NEW_CANDIDATES) {
      stats.skipped += 1;
      continue;
    }

    const result = await sendCampaignPush({
      userId: user.id,
      campaignKey: "new_players_arrived",
      dedupeKey: `new_players_arrived:${user.id}:${getLocalDateParts(user.timezone, now).dateKey}`,
      content: (locale) => ({
        title: translateServer(locale, "push.newPlayers.title"),
        body: translateServer(locale, `push.newPlayers.body.${pluralKeySuffix(locale, fresh)}`, {
          count: fresh
        })
      }),
      href: "/discover",
      context: { freshCandidates: fresh },
      now,
      dryRun: options.dryRun
    });

    collect(stats, user.id, result);
  }

  return stats;
}

/**
 * «Не хотите сходить на тренировку?» — единственная кампания, которой не нужна
 * проверка на пустой экран: она ведёт в форму создания поиска, а не в список.
 * Зато форма приходит уже заполненной свободным слотом из профиля.
 */
export async function runTrainingNudge(now = new Date(), options: CampaignRunOptions = {}) {
  const stats = emptyStats();

  const users = await prisma.user.findMany({
    where: {
      accountStatus: "active",
      onboardingCompleted: true,
      isVerified: true,
      gameSearches: {
        none: {
          isActive: true,
          status: {
            in: ["active", "in_review"]
          }
        }
      },
      personalActivities: {
        none: {
          status: "planned",
          scheduledAt: {
            gt: now
          }
        }
      },
      notificationDeliveries: {
        none: {
          campaignKey: "training_nudge",
          createdAt: {
            gte: new Date(now.getTime() - TRAINING_COOLDOWN_MS)
          }
        }
      },
      ...HAS_ACTIVE_DEVICE
    },
    select: { id: true, timezone: true, availabilityByDay: true, preferredSports: true },
    orderBy: { id: "asc" },
    take: USER_BATCH_SIZE
  });

  for (const user of users) {
    const slot = resolveTomorrowSlot(user.availabilityByDay, user.timezone, now);

    if (!slot) {
      continue;
    }

    stats.scanned += 1;

    const sport = normalizeSports(user.preferredSports)[0];
    const query = new URLSearchParams({ day: slot.day, time: slot.timeRange });

    if (sport) {
      query.set("sport", sport);
    }

    const result = await sendCampaignPush({
      userId: user.id,
      campaignKey: "training_nudge",
      dedupeKey: `training_nudge:${user.id}:${getLocalDateParts(user.timezone, now).dateKey}`,
      content: (locale) => ({
        title: translateServer(locale, "push.trainingNudge.title"),
        body: translateServer(locale, "push.trainingNudge.body", {
          day: translateServer(locale, `push.day.${slot.day}`)
        })
      }),
      href: `/play/searches/new?${query.toString()}`,
      context: { day: slot.day, timeRange: slot.timeRange, sport: sport ?? null },
      now,
      dryRun: options.dryRun
    });

    collect(stats, user.id, result);
  }

  return stats;
}

/** Неделя молчания. Возвращаем только туда, где действительно есть с кем играть. */
export async function runWinBack(now = new Date(), options: CampaignRunOptions = {}) {
  const stats = emptyStats();

  const users = await prisma.user.findMany({
    where: {
      accountStatus: "active",
      onboardingCompleted: true,
      isVerified: true,
      lastActiveAt: {
        gte: new Date(now.getTime() - WIN_BACK_MAX_IDLE_MS),
        lt: new Date(now.getTime() - WIN_BACK_MIN_IDLE_MS)
      },
      notificationDeliveries: {
        none: {
          campaignKey: "win_back",
          createdAt: {
            gte: new Date(now.getTime() - WIN_BACK_COOLDOWN_MS)
          }
        }
      },
      ...HAS_ACTIVE_DEVICE
    },
    select: { id: true, timezone: true },
    orderBy: { lastActiveAt: "asc" },
    take: MAX_SCORED_USERS_PER_RUN
  });

  for (const user of users) {
    stats.scanned += 1;

    const candidateCount = await countDiscoverCandidates(user.id, { view: "swipe" });

    if (candidateCount < MIN_CANDIDATES_FOR_PUSH) {
      stats.skipped += 1;
      continue;
    }

    const result = await sendCampaignPush({
      userId: user.id,
      campaignKey: "win_back",
      dedupeKey: `win_back:${user.id}:${getLocalDateParts(user.timezone, now).dateKey}`,
      content: (locale) => ({
        title: translateServer(locale, "push.winBack.title"),
        body: translateServer(locale, `push.winBack.body.${pluralKeySuffix(locale, candidateCount)}`, {
          count: candidateCount
        })
      }),
      href: "/discover",
      context: { candidateCount },
      now,
      dryRun: options.dryRun
    });

    collect(stats, user.id, result);
  }

  return stats;
}

/**
 * Завтрашний день недели в зоне игрока, если он отмечен свободным в профиле.
 * Пишем накануне: предложить тренировку в тот же час, когда она начинается,
 * бесполезно.
 */
type DayOption = (typeof DAY_OPTIONS)[number];
type TimeRangeOption = (typeof TIME_RANGE_OPTIONS)[number];

export function resolveTomorrowSlot(
  availabilityByDay: unknown,
  timezone: string | null,
  now = new Date()
): { day: DayOption; timeRange: TimeRangeOption } | null {
  if (!availabilityByDay || typeof availabilityByDay !== "object" || Array.isArray(availabilityByDay)) {
    return null;
  }

  const parts = getLocalDateParts(timezone, now);
  const tomorrow = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + 1));
  const day = DAY_OPTIONS[(tomorrow.getUTCDay() + 6) % 7];
  const ranges = (availabilityByDay as Record<string, unknown>)[day];

  if (!Array.isArray(ranges)) {
    return null;
  }

  const timeRange = ranges.find(
    (range): range is TimeRangeOption =>
      typeof range === "string" && (TIME_RANGE_OPTIONS as readonly string[]).includes(range)
  );

  return timeRange ? { day, timeRange } : null;
}
