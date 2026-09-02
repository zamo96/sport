import { afterEach, describe, expect, it, vi } from "vitest";

import { resolveHotSearchStartAt, resolveSearchDays } from "@/lib/game-search";

afterEach(() => {
  vi.useRealTimers();
});

/** Сервер живёт в UTC — именно из-за этого 9:00 превращались в 12:00. */
function freezeUtc(iso: string) {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(iso));
}

describe("hot search start time", () => {
  it("keeps the hour the player picked", () => {
    freezeUtc("2026-09-02T05:00:00.000Z");

    const startsAt = resolveHotSearchStartAt("today", "09:00", "Europe/Moscow");
    // 09:00 в Москве — это 06:00 UTC, а не 09:00 UTC.
    expect(startsAt?.toISOString()).toBe("2026-09-02T06:00:00.000Z");
  });

  it("works for other zones too", () => {
    freezeUtc("2026-09-02T05:00:00.000Z");

    expect(resolveHotSearchStartAt("today", "09:00", "Asia/Novosibirsk")?.toISOString()).toBe(
      "2026-09-02T02:00:00.000Z"
    );
    expect(resolveHotSearchStartAt("today", "19:30", "Europe/London")?.toISOString()).toBe(
      "2026-09-02T18:30:00.000Z"
    );
  });

  it("counts tomorrow in the player's calendar", () => {
    // 22:30 UTC — в Москве уже 3 сентября, значит «завтра» это 4-е.
    freezeUtc("2026-09-02T22:30:00.000Z");

    expect(resolveHotSearchStartAt("tomorrow", "09:00", "Europe/Moscow")?.toISOString()).toBe(
      "2026-09-04T06:00:00.000Z"
    );
    expect(resolveHotSearchStartAt("tomorrow", "09:00", "Europe/London")?.toISOString()).toBe(
      "2026-09-03T08:00:00.000Z"
    );
  });

  it("rolls over the end of a month", () => {
    freezeUtc("2026-09-30T05:00:00.000Z");

    expect(resolveHotSearchStartAt("tomorrow", "10:00", "Europe/Moscow")?.toISOString()).toBe(
      "2026-10-01T07:00:00.000Z"
    );
  });

  it("rejects impossible times", () => {
    expect(resolveHotSearchStartAt("today", "25:00", "Europe/Moscow")).toBeNull();
    expect(resolveHotSearchStartAt("today", "09:71", "Europe/Moscow")).toBeNull();
    expect(resolveHotSearchStartAt("today", "утро", "Europe/Moscow")).toBeNull();
  });
});

describe("hot search day", () => {
  it("uses the player's calendar day, not the server's", () => {
    // 22:30 UTC во вторник — в Москве уже среда.
    const startsAt = new Date("2026-09-01T22:30:00.000Z");

    expect(resolveSearchDays("hot", [], null, startsAt, "Europe/Moscow")).toEqual(["wednesday"]);
    expect(resolveSearchDays("hot", [], null, startsAt, "Europe/London")).toEqual(["tuesday"]);
  });

  it("leaves regular searches alone", () => {
    expect(resolveSearchDays("regular", ["monday", "friday"], null, null, "Europe/Moscow")).toEqual([
      "monday",
      "friday"
    ]);
  });
});
