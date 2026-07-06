import { describe, expect, it, vi } from "vitest";

import {
  getGameRequestDetailsLabel,
  getGameRequestHeading,
  getGameRequestNextStep,
  isAcceptedUpcomingGameRequest
} from "@/lib/game-requests";
import {
  buildAutoConfirmedGameReportConfirmations,
  buildCompletedGameSimulationDatetime,
  hasGameRequestEnded
} from "@/server/game-reports";

describe("game request helpers", () => {
  it("recognizes accepted upcoming games", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-20T10:00:00.000Z"));

    expect(isAcceptedUpcomingGameRequest("accepted", "2026-04-20T19:00:00.000Z")).toBe(true);
    expect(isAcceptedUpcomingGameRequest("accepted", "2026-04-19T19:00:00.000Z")).toBe(false);
    expect(isAcceptedUpcomingGameRequest("pending", "2026-04-20T19:00:00.000Z")).toBe(false);

    vi.useRealTimers();
  });

  it("uses confirmed game wording for accepted upcoming games", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-20T10:00:00.000Z"));

    expect(getGameRequestHeading({ status: "accepted", proposedDatetime: "2026-04-20T19:00:00.000Z" })).toBe(
      "Подтвержденная игра"
    );
    expect(
      getGameRequestDetailsLabel({ status: "accepted", proposedDatetime: "2026-04-20T19:00:00.000Z" })
    ).toBe("Открыть подтвержденную игру");

    vi.useRealTimers();
  });

  it("describes the next step for pending and accepted requests", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-20T10:00:00.000Z"));

    expect(
      getGameRequestNextStep({
        status: "pending",
        proposedDatetime: "2026-04-20T19:00:00.000Z",
        isCreator: true
      })
    ).toContain("Ждём подтверждение");

    expect(
      getGameRequestNextStep({
        status: "accepted",
        proposedDatetime: "2026-04-20T19:00:00.000Z"
      })
    ).toContain("Игра подтверждена");

    vi.useRealTimers();
  });
});

describe("game report helpers", () => {
  it("requires the proposed duration to elapse before a game report is allowed", () => {
    const gameRequest = {
      proposedDatetime: new Date("2026-04-20T10:00:00.000Z"),
      durationMinutes: 90
    };

    expect(hasGameRequestEnded(gameRequest, new Date("2026-04-20T11:29:00.000Z"))).toBe(false);
    expect(hasGameRequestEnded(gameRequest, new Date("2026-04-20T11:30:00.000Z"))).toBe(true);
  });

  it("builds a simulated start time that is already past the game end", () => {
    const now = new Date("2026-04-20T12:00:00.000Z");
    const proposedDatetime = buildCompletedGameSimulationDatetime(60, now);

    expect(proposedDatetime.toISOString()).toBe("2026-04-20T10:55:00.000Z");
    expect(hasGameRequestEnded({ proposedDatetime, durationMinutes: 60 }, now)).toBe(true);
  });

  it("auto-confirms report confirmations for every participant", () => {
    expect(buildAutoConfirmedGameReportConfirmations(["user-1", "user-2"])).toEqual([
      { userId: "user-1", status: "confirmed" },
      { userId: "user-2", status: "confirmed" }
    ]);
  });
});
