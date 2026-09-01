import { Prisma } from "@prisma/client";

import { sendPushToUser } from "@/lib/apns";
import { SPORT_LABELS } from "@/lib/constants";
import { prisma } from "@/lib/prisma";
import { normalizeSports } from "@/lib/sport-levels";

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_SEARCHES_PER_DIGEST = 5;

type HotDigestSlot = {
  slotKey: string;
  since: Date;
  until: Date;
  label: "midday" | "evening";
};

export function resolveHotDigestSlot(now = new Date()): HotDigestSlot | null {
  const parts = getMoscowDateParts(now);
  const hour = Number(parts.hour);
  const todayNoon = moscowDateToUtc(parts.year, parts.month, parts.day, 12);
  const todayEvening = moscowDateToUtc(parts.year, parts.month, parts.day, 18);
  const dateKey = `${parts.year}-${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;

  if (hour >= 12 && hour < 15) {
    return {
      slotKey: `${dateKey}:midday`,
      since: new Date(todayEvening.getTime() - DAY_MS),
      until: now,
      label: "midday"
    };
  }

  if (hour >= 18 && hour < 21) {
    return {
      slotKey: `${dateKey}:evening`,
      since: todayNoon,
      until: now,
      label: "evening"
    };
  }

  return null;
}

export async function runHotSearchDigestMaintenance(now = new Date()) {
  const slot = resolveHotDigestSlot(now);

  if (!slot) {
    return { sent: 0, skipped: true };
  }

  const users = await prisma.user.findMany({
    where: {
      onboardingCompleted: true,
      isVerified: true,
      notificationGames: true,
      pushDevices: {
        some: {
          platform: "ios",
          isActive: true
        }
      }
    },
    select: {
      id: true,
      city: true,
      locationPlaceId: true,
      preferredSports: true,
      notificationSound: true
    },
    take: 1000
  });

  let sent = 0;

  for (const user of users) {
    const searches = await getDigestSearchesForUser(user.id, user.preferredSports, slot, now, {
      city: user.city,
      locationPlaceId: user.locationPlaceId
    });

    if (searches.length === 0) {
      continue;
    }

    const searchIds = searches.map((search) => search.id);
    const created = await createDigestDelivery(user.id, slot.slotKey, searchIds);

    if (!created) {
      continue;
    }

    await sendPushToUser({
      userId: user.id,
      title: buildDigestTitle(searches.length),
      body: buildDigestBody(searches),
      href: "/discover?view=hot",
      sound: user.notificationSound ?? true
    });
    sent += 1;
  }

  return { sent, skipped: false };
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
      ...(location.locationPlaceId
        ? { locationPlaceId: location.locationPlaceId }
        : location.city
          ? { createdByUser: { city: location.city } }
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

async function createDigestDelivery(userId: string, slotKey: string, searchIds: string[]) {
  try {
    await prisma.hotSearchDigestDelivery.create({
      data: {
        userId,
        slotKey,
        searchIds,
        deliveredCount: searchIds.length
      }
    });
    return true;
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      return false;
    }

    throw error;
  }
}

function buildDigestTitle(count: number) {
  return count === 1 ? "Есть срочная игра рядом" : `Есть ${count} срочные игры`;
}

function buildDigestBody(searches: Awaited<ReturnType<typeof getDigestSearchesForUser>>) {
  const sports = Array.from(new Set(searches.map((search) => SPORT_LABELS[search.sport] ?? search.sport))).slice(0, 3);
  const firstCourt = searches.find((search) => search.preferredCourt)?.preferredCourt?.name;

  return [sports.join(", "), firstCourt ? `например ${firstCourt}` : "можно откликнуться во вкладке «Срочно»"]
    .filter(Boolean)
    .join(" · ");
}

function getMoscowDateParts(date: Date) {
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

  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: parts.hour ?? "00"
  };
}

function moscowDateToUtc(year: number, month: number, day: number, hour: number) {
  return new Date(Date.UTC(year, month - 1, day, hour - 3, 0, 0, 0));
}
