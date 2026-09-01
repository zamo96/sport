import { describe, expect, it } from "vitest";

import { GameSearchType, HotSearchWindow, PlayFormat, Sport, Surface } from "@prisma/client";

import {
  appleAuthSchema,
  courtsQuerySchema,
  createGameRequestSchema,
  createGameSearchSchema,
  guestOnboardingDraftSchema,
  requestLinkSchema,
  updateMeSchema,
  updateGameRequestSchema,
  updateGameSearchSchema,
  verifySchema
} from "@/lib/validators";
import { DISTRICT_LABELS, getDistrictArea } from "@/lib/constants";
import {
  LEGACY_USER_AGREEMENT_VERSION,
  buildLatestUserAgreementPayload,
  buildUserAgreementAcceptanceRecord
} from "@/lib/legal-contract";

const newDistrictIds = [
  "moscow_central",
  "moscow_northern",
  "moscow_northeastern",
  "moscow_eastern",
  "moscow_southeastern",
  "moscow_southern",
  "moscow_southwestern",
  "moscow_western",
  "moscow_northwestern",
  "moscow_zelenograd",
  "moscow_novomoskovsky",
  "moscow_troitsky",
  "kazan_aviastroitelny",
  "kazan_vakhitovsky",
  "kazan_kirovsky",
  "kazan_moskovsky",
  "kazan_novo_savinovsky",
  "kazan_privolzhsky",
  "kazan_sovetsky"
] as const;

describe("auth validators legal acceptance", () => {
  it("accepts the current user agreement version for email and Apple auth", () => {
    const userAgreement = buildLatestUserAgreementPayload();

    expect(requestLinkSchema.safeParse({ email: "player@example.com", userAgreement }).success).toBe(true);
    expect(verifySchema.safeParse({ email: "player@example.com", code: "123456", userAgreement }).success).toBe(true);
    expect(appleAuthSchema.safeParse({ identityToken: "identity-token", userAgreement }).success).toBe(true);
  });

  it("temporarily accepts and accurately records the production iOS legacy agreement", () => {
    const legacyAgreement = { accepted: true, version: LEGACY_USER_AGREEMENT_VERSION };

    expect(requestLinkSchema.safeParse({ email: "player@example.com", userAgreement: legacyAgreement }).success).toBe(true);
    expect(verifySchema.safeParse({ email: "player@example.com", code: "123456", userAgreement: legacyAgreement }).success).toBe(true);
    expect(appleAuthSchema.safeParse({ identityToken: "identity-token", userAgreement: legacyAgreement }).success).toBe(true);

    const record = buildUserAgreementAcceptanceRecord({
      userId: "user-1",
      source: "apple",
      agreementVersion: LEGACY_USER_AGREEMENT_VERSION
    });
    expect(record.agreementVersion).toBe(LEGACY_USER_AGREEMENT_VERSION);
    expect(record.personalDataConsentVersion).toBe(LEGACY_USER_AGREEMENT_VERSION);
  });

  it("rejects missing or stale user agreement acceptance", () => {
    expect(requestLinkSchema.safeParse({ email: "player@example.com" }).success).toBe(false);
    expect(
      verifySchema.safeParse({
        email: "player@example.com",
        code: "123456",
        userAgreement: { accepted: true, version: "2026-01-01" }
      }).success
    ).toBe(false);
    expect(
      appleAuthSchema.safeParse({
        identityToken: "identity-token",
        userAgreement: { accepted: false, version: buildLatestUserAgreementPayload().version }
      }).success
    ).toBe(false);
    expect(
      requestLinkSchema.safeParse({
        email: "player@example.com",
        userAgreement: { accepted: true, version: "2026-07-04" }
      }).success
    ).toBe(false);
  });
});

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

  it("game request schemas: allow appointing a game without a selected club", () => {
    expect(
      createGameRequestSchema.safeParse({
        matchId: "match-1",
        proposedCourtId: null,
        proposedDatetime: "2099-04-20T19:00:00.000Z",
        sport: Sport.tennis,
        format: PlayFormat.singles
      }).success
    ).toBe(true);

    expect(updateGameRequestSchema.safeParse({ proposedCourtId: null }).success).toBe(true);
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

  it("guestOnboardingDraftSchema: accepts an arbitrary city only with a server place id", () => {
    expect(
      guestOnboardingDraftSchema.safeParse({
        ...validGuestDraft,
        city: "Берлин",
        locationPlaceId: "nominatim:relation:62422"
      }).success
    ).toBe(true);
    expect(guestOnboardingDraftSchema.safeParse({ ...validGuestDraft, city: "Берлин" }).success).toBe(false);
  });

  it("updateMeSchema: accepts legacy profiles without tennisLevel when sport levels are present", () => {
    expect(
      updateMeSchema.safeParse({
        ...validGuestDraft,
        notificationMatches: true,
        notificationMessages: true,
        notificationGames: true,
        notificationSound: true
      }).success
    ).toBe(true);
  });

  it("updateMeSchema: accepts a server-issued global place without a legacy city", () => {
    const { city: _city, ...profile } = validGuestDraft;
    expect(
      updateMeSchema.safeParse({
        ...profile,
        locationPlaceId: "nominatim:relation:62422",
        locationSource: "manual"
      }).success
    ).toBe(true);
  });

  it("updateMeSchema: ignores compatibility city labels when a place id is present", () => {
    expect(
      updateMeSchema.safeParse({
        ...validGuestDraft,
        city: "Берлин",
        locationPlaceId: "nominatim:relation:62422"
      }).success
    ).toBe(true);
  });

  it("updateMeSchema: accepts an existing global city echoed by an old client", () => {
    expect(updateMeSchema.safeParse({ ...validGuestDraft, city: "Берлин" }).success).toBe(true);
  });

  it("updateMeSchema: requires either a place id or a supported legacy city", () => {
    const { city: _city, ...profile } = validGuestDraft;
    expect(updateMeSchema.safeParse(profile).success).toBe(false);
  });
});

describe("validators contract (district IDs)", () => {
  const validProfile = {
    name: "Матвей",
    age: 30,
    city: "Москва",
    preferredSports: [Sport.tennis],
    sportLevels: { tennis: 5 },
    preferredPlayFormat: PlayFormat.singles,
    preferredSurface: Surface.hard,
    availableDays: [],
    availableTimeRanges: [],
    availabilityByDay: {}
  };

  it("defines labels for every new globally unique district ID", () => {
    for (const district of newDistrictIds) {
      expect(DISTRICT_LABELS[district]).toBeTruthy();
    }
  });

  it("defines map areas for every new globally unique district ID", () => {
    for (const district of newDistrictIds) {
      const area = getDistrictArea(district);
      expect(area?.center).toBeTruthy();
      expect(area?.polygon.length).toBeGreaterThanOrEqual(3);
    }
  });

  it("accepts new district IDs in profile fields", () => {
    for (const district of newDistrictIds) {
      expect(
        updateMeSchema.safeParse({
          ...validProfile,
          district,
          preferredDistricts: [district]
        }).success
      ).toBe(true);
    }
  });

  it("accepts new district IDs in court queries", () => {
    for (const district of newDistrictIds) {
      expect(courtsQuerySchema.safeParse({ district }).success).toBe(true);
    }
  });
});
