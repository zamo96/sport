import { describe, expect, it, vi } from "vitest";

import { isExpiredHotSearch, resolveHotSearchStartAt } from "@/lib/game-search";

describe("game search helpers", () => {
  it("builds a hot search datetime from day window and time", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-17T10:00:00.000Z"));

    const startsAt = resolveHotSearchStartAt("tomorrow", "19:30");

    expect(startsAt?.getHours()).toBe(19);
    expect(startsAt?.getMinutes()).toBe(30);
    expect(startsAt?.getDate()).toBe(18);

    vi.useRealTimers();
  });

  it("marks hot search as expired when start time is in the past", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-17T10:00:00.000Z"));

    expect(isExpiredHotSearch("2026-03-17T09:59:00.000Z")).toBe(true);
    expect(isExpiredHotSearch("2026-03-17T10:01:00.000Z")).toBe(false);

    vi.useRealTimers();
  });
});
