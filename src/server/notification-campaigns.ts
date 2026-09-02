import { Prisma } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
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

/** Частотные лимиты по умолчанию для lifecycle-кампаний. */
export const DEFAULT_MAX_PER_DAY = 1;
export const DEFAULT_MAX_PER_WEEK = 3;

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
  | "campaign_cooldown";

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

export type CampaignSendResult = {
  status: CampaignSendStatus;
  reason: EligibilityReason;
  deliveryId?: string;
};

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
};

/** Явный выбор языка → страна проживания → язык по умолчанию. */
export function resolveUserLocale(user: {
  localeOverride?: string | null;
  location?: { countryCode?: string | null } | null;
}): SupportedLocale {
  return (
    normalizeSupportedLocale(user.localeOverride) ??
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
      _count: {
        select: {
          pushDevices: {
            where: {
              platform: "ios",
              isActive: true
            }
          }
        }
      }
    }
  });

  if (!user || user.accountStatus !== "active") {
    return { status: "skipped", reason: "inactive_account" };
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
  const variant = resolveLifecycleVariant(user.id);
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
