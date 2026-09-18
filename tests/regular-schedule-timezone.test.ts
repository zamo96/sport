import { describe, expect, it, vi, afterEach } from "vitest";

vi.mock("@/lib/prisma", () => ({ prisma: {} }));

import { buildWeeklySchedule } from "@/lib/game-search";
import { syncRegularPairOccurrences } from "@/server/regular-occurrences";

/** Как слот выглядит на часах игрока, а не сервера. */
function wallClock(timezone: string, date: Date) {
  return new Intl.DateTimeFormat("ru-RU", {
    timeZone: timezone,
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function createPair(options: {
  timezone: string | null;
  preferredDays: string[];
  preferredTimeRanges: string[];
}) {
  const created: Array<{ id: string; scheduledAt: Date }> = [];
  const db = {
    regularPair: {
      findUnique: vi.fn(async () => ({
        id: "pair-1",
        createdByUserId: "organizer",
        partnerUserId: "partner",
        preferredCourtId: null,
        sport: "tennis",
        format: "singles",
        preferredDays: options.preferredDays,
        preferredTimeRanges: options.preferredTimeRanges,
        createdByUser: { timezone: options.timezone },
        occurrences: []
      }))
    },
    regularPairOccurrence: {
      upsert: vi.fn(async ({ create }: { create: { scheduledAt: Date } }) => {
        const occurrence = { id: `occurrence-${created.length + 1}`, scheduledAt: create.scheduledAt };
        created.push(occurrence);
        return occurrence;
      }),
      update: vi.fn(async () => ({}))
    },
    regularPairOccurrenceConfirmation: {
      createMany: vi.fn(async () => ({ count: 2 }))
    }
  };

  return {
    created,
    sync: () =>
      syncRegularPairOccurrences(db as unknown as Parameters<typeof syncRegularPairOccurrences>[0], "pair-1")
  };
}

afterEach(() => {
  vi.useRealTimers();
});

describe("weekly schedule labels", () => {
  // 19:00 в Москве и 19:00 в Новосибирске — разные моменты времени, но обе
  // подписи должны читаться как «понедельник, 19:00» у своей пары.
  const mondayEveningMoscow = new Date("2026-09-21T16:00:00.000Z");

  it("writes the day and time in the pair's zone", () => {
    expect(buildWeeklySchedule([{ scheduledAt: mondayEveningMoscow }], "Europe/Moscow")).toEqual({
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@19:00"]
    });
  });

  it("does not fall back to the server zone", () => {
    expect(buildWeeklySchedule([{ scheduledAt: mondayEveningMoscow }], "Asia/Novosibirsk")).toEqual({
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@23:00"]
    });
  });

  it("keeps the calendar day of the player, not of UTC", () => {
    // 01:30 понедельника по Москве — это ещё воскресенье по UTC.
    const mondayNightMoscow = new Date("2026-09-20T22:30:00.000Z");

    expect(buildWeeklySchedule([{ scheduledAt: mondayNightMoscow }], "Europe/Moscow")).toEqual({
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@01:30"]
    });
  });

  it("accepts ISO strings and skips broken values", () => {
    expect(
      buildWeeklySchedule(
        [{ scheduledAt: mondayEveningMoscow.toISOString() }, { scheduledAt: "не дата" }],
        "Europe/Moscow"
      )
    ).toEqual({
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@19:00"]
    });
  });
});

describe("regular pair occurrences", () => {
  it("puts a slot at the hour the pair chose, whatever the server zone is", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-17T09:00:00.000Z"));

    const pair = createPair({
      timezone: "Europe/Moscow",
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@19:00"]
    });

    await pair.sync();

    expect(pair.created).toHaveLength(2);
    expect(pair.created.map((occurrence) => occurrence.scheduledAt.toISOString())).toEqual([
      "2026-09-21T16:00:00.000Z",
      "2026-09-28T16:00:00.000Z"
    ]);
    expect(wallClock("Europe/Moscow", pair.created[0].scheduledAt)).toContain("19:00");
  });

  // Две зоны с разным смещением: зона машины совпадёт максимум с одной из них,
  // поэтому подстановка серверной зоны провалит проверку на любом хосте.
  it("uses the pair's zone, not the one the process happens to run in", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-17T09:00:00.000Z"));

    const novosibirsk = createPair({
      timezone: "Asia/Novosibirsk",
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@19:00"]
    });

    await novosibirsk.sync();

    expect(novosibirsk.created[0].scheduledAt.toISOString()).toBe("2026-09-21T12:00:00.000Z");
    expect(wallClock("Asia/Novosibirsk", novosibirsk.created[0].scheduledAt)).toContain("19:00");
  });

  it("round-trips a schedule it wrote itself", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-17T09:00:00.000Z"));

    const chosenSlot = new Date("2026-09-21T16:00:00.000Z");
    const schedule = buildWeeklySchedule([{ scheduledAt: chosenSlot }], "Europe/Moscow");
    const pair = createPair({
      timezone: "Europe/Moscow",
      preferredDays: schedule.preferredDays,
      preferredTimeRanges: schedule.preferredTimeRanges
    });

    await pair.sync();

    expect(pair.created[0].scheduledAt.toISOString()).toBe(chosenSlot.toISOString());
  });

  it("keeps the named hour across a daylight saving change", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-20T09:00:00.000Z"));

    // Лондон переводит часы в ночь на 25 октября 2026: смещение меняется
    // между двумя соседними слотами, а 19:00 должно остаться 19:00.
    const pair = createPair({
      timezone: "Europe/London",
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@19:00"]
    });

    await pair.sync();

    expect(pair.created.map((occurrence) => occurrence.scheduledAt.toISOString())).toEqual([
      "2026-10-26T19:00:00.000Z",
      "2026-11-02T19:00:00.000Z"
    ]);
  });

  it("falls back to the default zone when the organizer has none", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-17T09:00:00.000Z"));

    const pair = createPair({
      timezone: null,
      preferredDays: ["monday"],
      preferredTimeRanges: ["monday@19:00"]
    });

    await pair.sync();

    expect(pair.created[0].scheduledAt.toISOString()).toBe("2026-09-21T16:00:00.000Z");
  });
});
