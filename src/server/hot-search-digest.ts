import { Prisma } from "@prisma/client";

import { translateServer } from "@/lib/i18n/server";
import { pluralKeySuffix } from "@/lib/i18n/server/notifications";
import { getAuthSportLabel } from "@/lib/i18n/web/auth";
import type { SupportedLocale } from "@/lib/locales";
import { prisma } from "@/lib/prisma";
import { normalizeSports } from "@/lib/sport-levels";
import { DEFAULT_TIMEZONE, getLocalDateParts, localDateTimeToUtc } from "@/lib/timezone";
import {
  sendCampaignPush,
  type CampaignPreview,
  type CampaignSendStatus
} from "@/server/notification-campaigns";

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_SEARCHES_PER_DIGEST = 5;
const USER_BATCH_SIZE = 500;

const MIDDAY_HOUR = 12;
const EVENING_HOUR = 18;
/** Ширина окна в часах: джоба должна успеть попасть в него даже при почасовом cron. */
const WINDOW_HOURS = 3;

type HotDigestSlot = {
  slotKey: string;
  since: Date;
  until: Date;
  label: "midday" | "evening";
};

/**
 * Слот считается в локальной зоне игрока: после выхода на глобальные локации
 * общий московский слот отправлял бы дайджест в случайное время суток.
 */
export function resolveHotDigestSlot(now = new Date(), timezone: string | null = DEFAULT_TIMEZONE): HotDigestSlot | null {
  const parts = getLocalDateParts(timezone, now);
  const todayNoon = localDateTimeToUtc(timezone, parts.year, parts.month, parts.day, MIDDAY_HOUR);
  const todayEvening = localDateTimeToUtc(timezone, parts.year, parts.month, parts.day, EVENING_HOUR);

  if (parts.hour >= MIDDAY_HOUR && parts.hour < MIDDAY_HOUR + WINDOW_HOURS) {
    return {
      slotKey: `${parts.dateKey}:midday`,
      since: new Date(todayEvening.getTime() - DAY_MS),
      until: now,
      label: "midday"
    };
  }

  if (parts.hour >= EVENING_HOUR && parts.hour < EVENING_HOUR + WINDOW_HOURS) {
    return {
      slotKey: `${parts.dateKey}:evening`,
      since: todayNoon,
      until: now,
      label: "evening"
    };
  }

  return null;
}

const DIGEST_AUDIENCE = {
  onboardingCompleted: true,
  isVerified: true,
  notificationGames: true,
  pushDevices: {
    some: {
      platform: "ios",
      isActive: true
    }
  }
} satisfies Prisma.UserWhereInput;

/**
 * Cron ходит раз в 5 минут, а окна теперь локальные, поэтому сначала дешёвым
 * группирующим запросом выясняем, открыто ли окно хоть в одной зоне: в
 * большинстве запусков дальше идти не нужно.
 */
async function resolveActiveZoneFilter(now: Date): Promise<Prisma.UserWhereInput | null> {
  const zones = await prisma.user.groupBy({
    by: ["timezone"],
    where: DIGEST_AUDIENCE
  });
  const activeZones = zones
    .map((zone) => zone.timezone)
    .filter((timezone) => resolveHotDigestSlot(now, timezone) !== null);

  if (activeZones.length === 0) {
    return null;
  }

  const namedZones = activeZones.filter((timezone): timezone is string => timezone !== null);
  const includesFallbackZone = activeZones.length > namedZones.length;

  if (!includesFallbackZone) {
    return { timezone: { in: namedZones } };
  }

  return { OR: [{ timezone: { in: namedZones } }, { timezone: null }] };
}

export async function runHotSearchDigestMaintenance(
  now = new Date(),
  options: { dryRun?: boolean; simulatedDeliveries?: Map<string, number> } = {}
) {
  const stats: Record<CampaignSendStatus, number> = {
    sent: 0,
    holdout: 0,
    duplicate: 0,
    skipped: 0,
    failed: 0
  };
  const samples: Array<{ userId: string } & CampaignPreview> = [];
  let scanned = 0;
  let cursor: string | null = null;

  const zoneFilter = await resolveActiveZoneFilter(now);

  if (!zoneFilter) {
    return { ...stats, scanned, samples };
  }

  for (;;) {
    const page: { cursor?: { id: string }; skip?: number } = cursor
      ? { cursor: { id: cursor }, skip: 1 }
      : {};
    const users = await prisma.user.findMany({
      where: {
        ...DIGEST_AUDIENCE,
        ...zoneFilter
      },
      select: {
        id: true,
        city: true,
        locationPlaceId: true,
        preferredSports: true,
        timezone: true
      },
      orderBy: { id: "asc" },
      ...page,
      take: USER_BATCH_SIZE
    });

    if (users.length === 0) {
      break;
    }

    cursor = users[users.length - 1].id;

    for (const user of users) {
      const slot = resolveHotDigestSlot(now, user.timezone);

      if (!slot) {
        continue;
      }

      scanned += 1;

      const searches = await getDigestSearchesForUser(user.id, user.preferredSports, slot, now, {
        city: user.city,
        locationPlaceId: user.locationPlaceId
      });

      if (searches.length === 0) {
        continue;
      }

      const result = await sendCampaignPush({
        userId: user.id,
        campaignKey: "hot_search_digest",
        dedupeKey: `hot_search_digest:${user.id}:${slot.slotKey}`,
        content: (locale) => ({
          title: buildDigestTitle(locale, searches.length),
          body: buildDigestBody(locale, searches)
        }),
        href: "/discover?view=hot",
        context: {
          slotKey: slot.slotKey,
          label: slot.label,
          searchIds: searches.map((search) => search.id)
        },
        now,
        dryRun: options.dryRun
      });

      stats[result.status] += 1;

      if (result.preview && samples.length < 5) {
        samples.push({ userId: user.id, ...result.preview });
      }

      // Дайджест идёт первым и расходует общий дневной лимит, поэтому в dry-run
      // его отправки должны учитываться в кампаниях, которые считаются после.
      if (options.dryRun && options.simulatedDeliveries && (result.status === "sent" || result.status === "holdout")) {
        const counters = options.simulatedDeliveries;
        counters.set(user.id, (counters.get(user.id) ?? 0) + 1);
      }
    }
  }

  return { ...stats, scanned, samples };
}

/**
 * Те же условия, что и во вкладке «Срочно»: без них дайджест обещает игры,
 * которых игрок на экране не увидит. Городской фолбэк живёт здесь же, иначе он
 * перезаписал бы фильтр целиком.
 */
function buildCreatorFilter(userId: string, location: { city: string | null; locationPlaceId: string | null }) {
  return {
    accountStatus: "active",
    onboardingCompleted: true,
    isVerified: true,
    ...(!location.locationPlaceId && location.city ? { city: location.city } : {}),
    blockedUsers: {
      none: {
        blockedUserId: userId
      }
    },
    blockingUsers: {
      none: {
        blockerUserId: userId
      }
    }
  } satisfies Prisma.UserWhereInput;
}

async function getDigestSearchesForUser(
  userId: string,
  preferredSports: unknown,
  slot: HotDigestSlot,
  now: Date,
  location: { city: string | null; locationPlaceId: string | null }
) {
  const sports = normalizeSports(preferredSports);

  if (sports.length === 0) {
    return [];
  }

  const searches = await prisma.gameSearch.findMany({
    where: {
      createdAt: {
        gte: slot.since,
        lte: slot.until
      },
      isActive: true,
      status: {
        in: ["active", "in_review"]
      },
      searchType: "hot",
      hotStartsAt: {
        gt: now
      },
      sport: {
        in: sports
      },
      createdByUserId: {
        not: userId
      },
      createdByUser: buildCreatorFilter(userId, location),
      ...(location.locationPlaceId
        ? { locationPlaceId: location.locationPlaceId }
        : location.city
          ? {}
          : { id: "__no_location__" }),
      responses: {
        none: {
          responderUserId: userId
        }
      }
    },
    include: {
      createdByUser: {
        select: {
          id: true,
          name: true
        }
      },
      preferredCourt: true,
      responses: {
        select: {
          id: true
        }
      }
    },
    orderBy: [
      {
        hotStartsAt: "asc"
      },
      {
        createdAt: "desc"
      }
    ],
    take: 30
  });

  return searches
    .filter((search) => search.responses.length < Math.max(3, search.playersNeeded * 2))
    .sort((left, right) => {
      const responseDelta = left.responses.length - right.responses.length;
      if (responseDelta !== 0) {
        return responseDelta;
      }

      return (left.hotStartsAt?.getTime() ?? 0) - (right.hotStartsAt?.getTime() ?? 0);
    })
    .slice(0, MAX_SEARCHES_PER_DIGEST);
}

function buildDigestTitle(locale: SupportedLocale, count: number) {
  return translateServer(locale, `push.hotDigest.title.${pluralKeySuffix(locale, count)}`, { count });
}

function buildDigestBody(
  locale: SupportedLocale,
  searches: Awaited<ReturnType<typeof getDigestSearchesForUser>>
) {
  const sports = Array.from(new Set(searches.map((search) => getAuthSportLabel(locale, search.sport)))).slice(0, 3);
  const firstCourt = searches.find((search) => search.preferredCourt)?.preferredCourt?.name;

  return firstCourt
    ? translateServer(locale, "push.hotDigest.body.court", { sports: sports.join(", "), court: firstCourt })
    : translateServer(locale, "push.hotDigest.body.plain", { sports: sports.join(", ") });
}
