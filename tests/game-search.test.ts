import { describe, expect, it, vi } from "vitest";

import { isExpiredHotSearch, resolveHotSearchStartAt, resolveSearchNextStep } from "@/lib/game-search";
import { hasExplicitSportProfile } from "@/lib/sport-levels";

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

  it("requires explicit sport and level in profile before creating search", () => {
    expect(hasExplicitSportProfile(["tennis", "football"], { tennis: 6, football: 4 }, "football")).toBe(true);
    expect(hasExplicitSportProfile(["tennis"], { tennis: 6 }, "football")).toBe(false);
    expect(hasExplicitSportProfile(["tennis", "football"], { tennis: 6 }, "football")).toBe(false);
  });

  it("returns a confirmed-game next step for scheduled searches", () => {
    const nextStep = resolveSearchNextStep({
      searchType: "hot",
      status: "matched",
      approvedCount: 1,
      playersNeeded: 1,
      scheduledAt: "2026-03-18T19:30:00.000Z"
    });

    expect(nextStep.title).toBe("Игра подтверждена");
    expect(nextStep.description).toContain("Событие уже назначено");
  });

  it("returns a regular-pair next step when partner is already approved", () => {
    const nextStep = resolveSearchNextStep({
      searchType: "regular",
      status: "matched",
      approvedCount: 1,
      playersNeeded: 1,
      regularPairMatchId: "match-1"
    });

    expect(nextStep.title).toBe("Пара собрана");
    expect(nextStep.description).toContain("предложить ближайшую игру");
  });

  it("prefers confirmed-game next step over regular-pair wording once a game is scheduled", () => {
    const nextStep = resolveSearchNextStep({
      searchType: "regular",
      status: "matched",
      approvedCount: 1,
      playersNeeded: 1,
      scheduledAt: "2026-03-18T19:30:00.000Z",
      regularPairMatchId: "match-1"
    });

    expect(nextStep.title).toBe("Игра подтверждена");
    expect(nextStep.description).toContain("Событие уже назначено");
  });
});
