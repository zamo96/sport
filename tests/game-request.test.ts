import { describe, expect, it, vi } from "vitest";

import {
  getGameRequestDetailsLabel,
  getGameRequestHeading,
  getGameRequestNextStep,
  isAcceptedUpcomingGameRequest
} from "@/lib/game-requests";

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
    ).toContain("Игра создана");

    expect(
      getGameRequestNextStep({
        status: "accepted",
        proposedDatetime: "2026-04-20T19:00:00.000Z"
      })
    ).toContain("Игра подтверждена");

    vi.useRealTimers();
  });
});
