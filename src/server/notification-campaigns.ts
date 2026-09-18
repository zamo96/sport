import { Prisma } from "@prisma/client";

import { sendPushToUser } from "@/lib/push";
import {
  DEFAULT_LOCALE,
  recommendLocaleForConfirmedCountry,
  normalizeSupportedLocale,
  type SupportedLocale
} from "@/lib/locales";
import { prisma } from "@/lib/prisma";
import { DEFAULT_TIMEZONE, resolveLocalHour } from "@/lib/timezone";
import { recordUserEvent } from "@/server/user-events";

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export { DEFAULT_TIMEZONE, resolveLocalHour };

/**
 * Достижимый игрок — это любое активное устройство, а не только iOS:
 * `sendPushToUser` доставляет и в APNs, и в FCM, а Android регистрирует токен
 * через `/devices/fcm`. Фильтр живёт здесь один на все кампании — когда у
 * каждой была своя копия с `platform: "ios"`, движок и аудитория разъехались,
 * и Android молча не получал ни одной рассылки.
 */
export const ACTIVE_PUSH_DEVICE = { isActive: true } satisfies Prisma.PushDeviceWhereInput;

export const HAS_ACTIVE_PUSH_DEVICE = {
  pushDevices: { some: ACTIVE_PUSH_DEVICE }
} satisfies Prisma.UserWhereInput;

/** Частотные лимиты по умолчанию для lifecycle-кампаний. */
export const DEFAULT_MAX_PER_DAY = 1;
export const DEFAULT_MAX_PER_WEEK = 3;

/**
 * Рубильник для всех lifecycle-рассылок. Выключенный по умолчанию, он даёт
 * выкатить код и проверить аудиторию через `?dryRun=1` до того, как cron
 * отправит первый настоящий пуш: cron ходит раз в 5 минут, догнать его после
 * деплоя нельзя.
 */
export function lifecycleCampaignsEnabled() {
  return ["1", "true", "yes"].includes((process.env.LIFECYCLE_CAMPAIGNS_ENABLED ?? "").trim().toLowerCase());
}

/** Тихие часы в локальном времени пользователя: [22:00, 09:00). */
export const QUIET_HOURS_START = 22;
export const QUIET_HOURS_END = 9;

/** Окно, в течение которого целевое действие засчитывается как конверсия пуша. */
const CONVERSION_WINDOW_MS = 72 * HOUR_MS;

export type CampaignCategory = "lifecycle" | "transactional";

export type NotificationPreferenceKey =
  | "notificationDigest"
  | "notificationGames"
  | "notificationMatches"
  | "notificationMessages";

export type CampaignDefinition = {
  category: CampaignCategory;
  /** Минимальный интервал между двумя доставками одной кампании одному игроку. */
  cooldownHours: number;
  /** Тумблер в настройках, который обязан быть включён. */
  preferenceKey: NotificationPreferenceKey;
  respectQuietHours?: boolean;
  maxPerDay?: number;
  maxPerWeek?: number;
};

/**
 * Реестр кампаний. `hot_search_digest` пока не подключён к движку — его шлёт
 * `runHotSearchDigestMaintenance`; запись здесь держит его лимиты наготове.
 */
export const CAMPAIGNS = {
  onboarding_incomplete: {
    category: "lifecycle",
    cooldownHours: 48,
    preferenceKey: "notificationDigest"
  },
  first_players_ready: {
    category: "lifecycle",
    cooldownHours: 168,
    preferenceKey: "notificationDigest"
  },
  new_players_arrived: {
    category: "lifecycle",
    cooldownHours: 48,
    preferenceKey: "notificationDigest"
  },
  likes_waiting: {
    category: "lifecycle",
    cooldownHours: 24,
    preferenceKey: "notificationMatches"
  },
  training_nudge: {
    category: "lifecycle",
    cooldownHours: 168,
    preferenceKey: "notificationDigest"
  },
  win_back: {
    category: "lifecycle",
    cooldownHours: 168,
    preferenceKey: "notificationDigest"
  },
  hot_search_digest: {
    category: "lifecycle",
    // Окна 12:00-15:00 и 18:00-21:00 могут сойтись на ~3 часа по краям.
    cooldownHours: 3,
    preferenceKey: "notificationGames",
    maxPerDay: 2,
    maxPerWeek: 10
  },
  // Напоминания о висящем действии: транзакционные, потому что это не рассылка,
  // а долг перед конкретным человеком, который ждёт ответа. Общий дневной лимит
  // они не тратят и не занимают; повтор ограничен ключом дедупа на сутки.
  search_response_waiting: {
    category: "transactional",
    cooldownHours: 24,
    preferenceKey: "notificationGames",
    respectQuietHours: true
  },
  game_outcome_pending: {
    category: "transactional",
    cooldownHours: 24,
    preferenceKey: "notificationGames",
    respectQuietHours: true
  }
} as const satisfies Record<string, CampaignDefinition>;

export type CampaignKey = keyof typeof CAMPAIGNS;

export const LIFECYCLE_CAMPAIGN_KEYS = (Object.keys(CAMPAIGNS) as CampaignKey[]).filter(
  (key) => CAMPAIGNS[key].category === "lifecycle"
);

export type CampaignVariant = "treatment" | "holdout";

export type EligibilityReason =
  | "ok"
  | "inactive_account"
  | "no_device"
  | "opted_out"
  | "quiet_hours"
  | "daily_cap"
  | "weekly_cap"
  | "campaign_cooldown"
  | "campaigns_disabled";

export type CampaignEligibilityInput = {
  campaignKey: CampaignKey;
  /** Локальный час пользователя, 0–23. */
  localHour: number;
  preferenceEnabled: boolean;
  hasActiveDevice: boolean;
  lifecycleDeliveriesLast24h: number;
  lifecycleDeliveriesLast7d: number;
  hoursSinceLastCampaignDelivery: number | null;
};

export type CampaignEligibility = {
  allowed: boolean;
  reason: EligibilityReason;
};

export function isQuietHour(localHour: number) {
  return localHour >= QUIET_HOURS_START || localHour < QUIET_HOURS_END;
}

/**
 * Чистая функция принятия решения — вся политика частоты живёт здесь, чтобы её
 * можно было проверять тестами без базы.
 */
export function evaluateCampaignEligibility(input: CampaignEligibilityInput): CampaignEligibility {
  const campaign: CampaignDefinition = CAMPAIGNS[input.campaignKey];

  if (!input.hasActiveDevice) {
    return { allowed: false, reason: "no_device" };
  }

  if (!input.preferenceEnabled) {
    return { allowed: false, reason: "opted_out" };
  }

  if (campaign.category === "transactional") {
    // По умолчанию транзакционный пуш идёт в любое время: он про событие,
    // которое случилось прямо сейчас. Напоминание — другое дело: долг подождёт
    // до утра, поэтому такая кампания включает тихие часы явно.
    if (campaign.respectQuietHours === true && isQuietHour(input.localHour)) {
      return { allowed: false, reason: "quiet_hours" };
    }

    return { allowed: true, reason: "ok" };
  }

  if (campaign.respectQuietHours !== false && isQuietHour(input.localHour)) {
    return { allowed: false, reason: "quiet_hours" };
  }

  if (
    input.hoursSinceLastCampaignDelivery != null &&
    input.hoursSinceLastCampaignDelivery < campaign.cooldownHours
  ) {
    return { allowed: false, reason: "campaign_cooldown" };
  }

  if (input.lifecycleDeliveriesLast24h >= (campaign.maxPerDay ?? DEFAULT_MAX_PER_DAY)) {
    return { allowed: false, reason: "daily_cap" };
  }

  if (input.lifecycleDeliveriesLast7d >= (campaign.maxPerWeek ?? DEFAULT_MAX_PER_WEEK)) {
    return { allowed: false, reason: "weekly_cap" };
  }

  return { allowed: true, reason: "ok" };
}

export function getHoldoutPercent() {
  const raw = Number(process.env.LIFECYCLE_HOLDOUT_PERCENT ?? "0");

  if (!Number.isFinite(raw)) {
    return 0;
  }

  return Math.min(50, Math.max(0, Math.trunc(raw)));
}

/** FNV-1a: стабильный бакет 0–99, одинаковый между процессами и деплоями. */
export function getHoldoutBucket(userId: string) {
  let hash = 0x811c9dc5;

  for (let index = 0; index < userId.length; index += 1) {
    hash ^= userId.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }

  return hash % 100;
}

/**
 * Холдаут глобальный, а не по кампаниям: игрок из контрольной группы не получает
 * никаких lifecycle-пушей, поэтому его retention сравним с остальными.
 */
export function resolveLifecycleVariant(userId: string, holdoutPercent = getHoldoutPercent()): CampaignVariant {
  if (holdoutPercent <= 0) {
    return "treatment";
  }

  return getHoldoutBucket(userId) < holdoutPercent ? "holdout" : "treatment";
}

export type CampaignSendStatus = "sent" | "holdout" | "duplicate" | "skipped" | "failed";

export type CampaignPreview = {
  title: string;
  body: string;
  href: string;
  locale: SupportedLocale;
};

export type CampaignSendResult = {
  status: CampaignSendStatus;
  reason: EligibilityReason;
  deliveryId?: string;
  /** Заполняется только в dry-run: что ушло бы этому игроку. */
  preview?: CampaignPreview;
};

/**
 * Разбивка прогона кампании: одна и та же форма у lifecycle-рассылок и у
 * напоминаний, поэтому ответ `/maintenance/game-requests` читается одинаково.
 */
export type CampaignStats = Record<CampaignSendStatus, number> & {
  scanned: number;
  samples: Array<{ userId: string } & CampaignPreview>;
};

const MAX_SAMPLES = 5;

export function emptyCampaignStats(): CampaignStats {
  return { sent: 0, holdout: 0, duplicate: 0, skipped: 0, failed: 0, scanned: 0, samples: [] };
}

export function collectCampaignResult(stats: CampaignStats, userId: string, result: CampaignSendResult) {
  stats[result.status] += 1;

  if (result.preview && stats.samples.length < MAX_SAMPLES) {
    stats.samples.push({ userId, ...result.preview });
  }
}

export type CampaignContent = {
  title: string;
  body: string;
};

/**
 * Текст пуша строится под язык игрока: рассылки идут из cron, где нет
 * Accept-Language, поэтому локаль резолвит сам движок.
 */
export type CampaignContentResolver = CampaignContent | ((locale: SupportedLocale) => CampaignContent);

export type CampaignSendInput = {
  userId: string;
  campaignKey: CampaignKey;
  /** Стабильный ключ идемпотентности, например `training_nudge:<userId>:2026-09-02`. */
  dedupeKey: string;
  content: CampaignContentResolver;
  href: string;
  context?: Prisma.InputJsonValue;
  now?: Date;
  /** Прогон без последствий: считает аудиторию и текст, но ничего не пишет и не шлёт. */
  dryRun?: boolean;
};

/**
 * Явный выбор языка → язык приложения на устройстве → страна проживания →
 * язык по умолчанию. Устройство идёт раньше страны: это то, что человек реально
 * видит в интерфейсе, и единственный сигнал у аккаунтов без города.
 */
export function resolveUserLocale(user: {
  localeOverride?: string | null;
  location?: { countryCode?: string | null } | null;
  pushDevices?: Array<{ locale?: string | null }> | null;
}): SupportedLocale {
  const deviceLocale = user.pushDevices
    ?.map((device) => normalizeSupportedLocale(device.locale))
    .find((locale): locale is SupportedLocale => locale != null);

  return (
    normalizeSupportedLocale(user.localeOverride) ??
    deviceLocale ??
    (user.location?.countryCode
      ? recommendLocaleForConfirmedCountry(user.location.countryCode)
      : DEFAULT_LOCALE)
  );
}

/**
 * Единая точка отправки lifecycle-пуша: проверяет лимиты, пишет строку доставки
 * (она же ключ идемпотентности и разметка для будущих моделей) и только потом
 * отдаёт пуш в APNs.
 */
export async function sendCampaignPush(input: CampaignSendInput): Promise<CampaignSendResult> {
  const now = input.now ?? new Date();
  const campaign: CampaignDefinition = CAMPAIGNS[input.campaignKey];

  const user = await prisma.user.findUnique({
    where: { id: input.userId },
    select: {
      id: true,
      accountStatus: true,
      timezone: true,
      localeOverride: true,
      location: {
        select: { countryCode: true }
      },
      notificationSound: true,
      notificationDigest: true,
      notificationGames: true,
      notificationMatches: true,
      notificationMessages: true,
      pushDevices: {
        where: ACTIVE_PUSH_DEVICE,
        select: { locale: true },
        orderBy: { lastRegisteredAt: "desc" },
        take: 3
      },
      _count: {
        select: {
          pushDevices: {
            where: ACTIVE_PUSH_DEVICE
          }
        }
      }
    }
  });

  if (!user || user.accountStatus !== "active") {
    return { status: "skipped", reason: "inactive_account" };
  }

  // Рубильник не мешает dry-run: смысл как раз в том, чтобы посмотреть
  // аудиторию на выключенных рассылках.
  if (!input.dryRun && campaign.category === "lifecycle" && !lifecycleCampaignsEnabled()) {
    return { status: "skipped", reason: "campaigns_disabled" };
  }

  const [lifecycleDeliveriesLast24h, lifecycleDeliveriesLast7d, lastCampaignDelivery] = await Promise.all([
    prisma.notificationDelivery.count({
      where: {
        userId: user.id,
        campaignKey: { in: LIFECYCLE_CAMPAIGN_KEYS },
        createdAt: { gte: new Date(now.getTime() - DAY_MS) }
      }
    }),
    prisma.notificationDelivery.count({
      where: {
        userId: user.id,
        campaignKey: { in: LIFECYCLE_CAMPAIGN_KEYS },
        createdAt: { gte: new Date(now.getTime() - 7 * DAY_MS) }
      }
    }),
    prisma.notificationDelivery.findFirst({
      where: {
        userId: user.id,
        campaignKey: input.campaignKey
      },
      orderBy: { createdAt: "desc" },
      select: { createdAt: true }
    })
  ]);

  const eligibility = evaluateCampaignEligibility({
    campaignKey: input.campaignKey,
    localHour: resolveLocalHour(user.timezone, now),
    preferenceEnabled: user[campaign.preferenceKey],
    hasActiveDevice: user._count.pushDevices > 0,
    lifecycleDeliveriesLast24h,
    lifecycleDeliveriesLast7d,
    hoursSinceLastCampaignDelivery: lastCampaignDelivery
      ? (now.getTime() - lastCampaignDelivery.createdAt.getTime()) / HOUR_MS
      : null
  });

  if (!eligibility.allowed) {
    return { status: "skipped", reason: eligibility.reason };
  }

  const locale = resolveUserLocale(user);
  const content = typeof input.content === "function" ? input.content(locale) : input.content;
  // Холдаут — инструмент измерения lifecycle-рассылок. Транзакционное
  // напоминание молча съесть нельзя: на том конце человек ждёт ответа.
  const variant = campaign.category === "lifecycle" ? resolveLifecycleVariant(user.id) : "treatment";

  if (input.dryRun) {
    const existing = await prisma.notificationDelivery.findUnique({
      where: { dedupeKey: input.dedupeKey },
      select: { id: true }
    });

    return {
      status: existing ? "duplicate" : variant === "holdout" ? "holdout" : "sent",
      reason: "ok",
      preview: { title: content.title, body: content.body, href: input.href, locale }
    };
  }

  let delivery: { id: string };

  try {
    delivery = await prisma.notificationDelivery.create({
      data: {
        userId: user.id,
        campaignKey: input.campaignKey,
        dedupeKey: input.dedupeKey,
        variant,
        title: content.title,
        body: content.body,
        href: input.href,
        context: input.context
      },
      select: { id: true }
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      return { status: "duplicate", reason: "ok" };
    }

    throw error;
  }

  // Контрольная группа получает строку доставки, но не получает пуш: так лимиты
  // расходуются одинаково в обеих группах и сравнение остаётся честным.
  if (variant === "holdout") {
    return { status: "holdout", reason: "ok", deliveryId: delivery.id };
  }

  try {
    await sendPushToUser({
      userId: user.id,
      title: content.title,
      body: content.body,
      href: input.href,
      sound: user.notificationSound ?? true,
      deliveryId: delivery.id
    });
  } catch (error) {
    console.error("Campaign push failed", { campaignKey: input.campaignKey, userId: user.id, error });
    return { status: "failed", reason: "ok", deliveryId: delivery.id };
  }

  await prisma.notificationDelivery.update({
    where: { id: delivery.id },
    data: { sentAt: now }
  });

  await recordUserEvent({
    userId: user.id,
    type: "push_sent",
    entityType: "notification_delivery",
    entityId: delivery.id,
    context: { campaignKey: input.campaignKey, variant, locale }
  });

  return { status: "sent", reason: "ok", deliveryId: delivery.id };
}

/** Отметка открытия пуша — вызывается из ingest-роута событий. */
export async function markNotificationOpened(userId: string, deliveryId: string, now = new Date()) {
  const updated = await prisma.notificationDelivery.updateMany({
    where: {
      id: deliveryId,
      userId,
      openedAt: null
    },
    data: { openedAt: now }
  });

  return updated.count > 0;
}

/**
 * Засчитывает целевое действие как конверсию последней доставки в окне 72 часа —
 * это и есть будущая метка для модели «слать / не слать».
 */
export async function markCampaignConversion(
  userId: string,
  campaignKeys: CampaignKey[] = LIFECYCLE_CAMPAIGN_KEYS,
  now = new Date()
) {
  try {
    return await findAndMarkConversion(userId, campaignKeys, now);
  } catch (error) {
    // Разметка для будущих моделей не стоит упавшего действия игрока.
    console.warn("Failed to mark campaign conversion", { userId, campaignKeys, error });
    return null;
  }
}

async function findAndMarkConversion(userId: string, campaignKeys: CampaignKey[], now: Date) {
  const delivery = await prisma.notificationDelivery.findFirst({
    where: {
      userId,
      campaignKey: { in: campaignKeys },
      convertedAt: null,
      sentAt: {
        not: null,
        gte: new Date(now.getTime() - CONVERSION_WINDOW_MS)
      }
    },
    orderBy: { sentAt: "desc" },
    select: { id: true, campaignKey: true }
  });

  if (!delivery) {
    return null;
  }

  await prisma.notificationDelivery.update({
    where: { id: delivery.id },
    data: { convertedAt: now }
  });

  await recordUserEvent({
    userId,
    type: "push_converted",
    entityType: "notification_delivery",
    entityId: delivery.id,
    context: { campaignKey: delivery.campaignKey }
  });

  return delivery.id;
}
