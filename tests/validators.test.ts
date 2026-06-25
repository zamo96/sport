import { describe, expect, it } from "vitest";

import { GameSearchType, HotSearchWindow, PlayFormat, Sport, Surface } from "@prisma/client";

import { createGameRequestSchema, createGameSearchSchema, guestOnboardingDraftSchema, updateGameSearchSchema } from "@/lib/validators";

describe("validators contract (sport x format)", () => {
  it("createGameSearchSchema: accepts exact weekly time preferences", () => {
    const result = createGameSearchSchema.safeParse({
      preferredDays: ["wednesday", "friday"],
      preferredTimeRanges: ["wednesday@19:00", "friday@08:30", "20:15"],
      searchType: GameSearchType.regular,
      sport: Sport.tennis,
      format: PlayFormat.singles,
      playersNeeded: 1
    });

    expect(result.success).toBe(true);
  });

  it("createGameSearchSchema: rejects padel + singles with a clear format error", () => {
    const result = createGameSearchSchema.safeParse({
      preferredTimeRanges: ["evening"],
      searchType: GameSearchType.hot,
      hotWindow: HotSearchWindow.today,
      hotStartTime: "19:30",
      durationMinutes: 90,
      sport: Sport.padel,
      format: PlayFormat.singles
    });

    expect(result.success).toBe(false);
    if (result.success) {
      return;
    }

    const formatIssue = result.error.issues.find((issue) => issue.path.join(".") === "format");
    expect(formatIssue?.message).toBe("Этот формат недоступен для выбранного вида спорта");
  });

  it("createGameSearchSchema: accepts explicit hotStartsAt without a quick window", () => {
    const result = createGameSearchSchema.safeParse({
      preferredTimeRanges: ["evening"],
      searchType: GameSearchType.hot,
      hotStartsAt: "2026-04-20T19:00:00.000Z",
      durationMinutes: 90,
      sport: Sport.tennis,
      format: PlayFormat.singles
    });

    expect(result.success).toBe(true);
  });

  it("createGameRequestSchema: rejects padel + singles with a clear format error", () => {
    const result = createGameRequestSchema.safeParse({
      matchId: "match-1",
      proposedCourtId: "court-1",
      proposedDatetime: "2026-04-20T19:00:00.000Z",
      sport: Sport.padel,
      format: PlayFormat.singles
    });

    expect(result.success).toBe(false);
    if (result.success) {
      return;
    }

    const formatIssue = result.error.issues.find((issue) => issue.path.join(".") === "format");
    expect(formatIssue?.message).toBe("Этот формат недоступен для выбранного вида спорта");
  });
});

describe("validators contract (patch safety)", () => {
  it("updateGameSearchSchema: rejects padel + singles when both fields are present", () => {
    const result = updateGameSearchSchema.safeParse({
      sport: Sport.padel,
      format: PlayFormat.singles
    });

    expect(result.success).toBe(false);
    if (result.success) {
      return;
    }

    const formatIssue = result.error.issues.find((issue) => issue.path.join(".") === "format");
    expect(formatIssue?.message).toBe("Этот формат недоступен для выбранного вида спорта");
  });

  it("updateGameSearchSchema: keeps PATCH permissive when only format is provided", () => {
    const result = updateGameSearchSchema.safeParse({
      format: PlayFormat.singles
    });

    expect(result.success).toBe(true);
  });

  it("updateGameSearchSchema: rejects when desiredLevelMin > desiredLevelMax", () => {
    const result = updateGameSearchSchema.safeParse({
      desiredLevelMin: 7,
      desiredLevelMax: 3
    });

    expect(result.success).toBe(false);
    if (result.success) {
      return;
    }

    const issue = result.error.issues.find((item) => item.path.join(".") === "desiredLevelMin");
    expect(issue?.message).toBe("Минимальный уровень не может быть выше максимального");
  });
});

describe("validators contract (profile age)", () => {
  const validGuestDraft = {
    name: "Матвей",
    age: 100,
    city: "Санкт-Петербург",
    preferredSports: [Sport.tennis],
    sportLevels: { tennis: 5 },
    preferredPlayFormat: PlayFormat.singles,
    preferredSurface: Surface.hard,
    preferredDistricts: [],
    availableDays: [],
    availableTimeRanges: [],
    availabilityByDay: {}
  };

  it("guestOnboardingDraftSchema: accepts age 100", () => {
    expect(guestOnboardingDraftSchema.safeParse(validGuestDraft).success).toBe(true);
  });

  it("guestOnboardingDraftSchema: rejects age above 100", () => {
    const result = guestOnboardingDraftSchema.safeParse({
      ...validGuestDraft,
      age: 101
    });

    expect(result.success).toBe(false);
  });
});
