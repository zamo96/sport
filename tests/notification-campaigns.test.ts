import { afterEach, describe, expect, it } from "vitest";

import {
  DEFAULT_MAX_PER_DAY,
  DEFAULT_MAX_PER_WEEK,
  evaluateCampaignEligibility,
  getHoldoutBucket,
  isQuietHour,
  lifecycleCampaignsEnabled,
  resolveLifecycleVariant,
  resolveLocalHour,
  type CampaignEligibilityInput
} from "@/server/notification-campaigns";

const baseInput: CampaignEligibilityInput = {
  campaignKey: "training_nudge",
  localHour: 19,
  preferenceEnabled: true,
  hasActiveDevice: true,
  lifecycleDeliveriesLast24h: 0,
  lifecycleDeliveriesLast7d: 0,
  hoursSinceLastCampaignDelivery: null
};

describe("campaign eligibility", () => {
  it("allows a lifecycle push inside waking hours within caps", () => {
    expect(evaluateCampaignEligibility(baseInput)).toEqual({ allowed: true, reason: "ok" });
  });

  it("skips players without an active device before any other check", () => {
    expect(
      evaluateCampaignEligibility({ ...baseInput, hasActiveDevice: false, preferenceEnabled: false })
    ).toEqual({ allowed: false, reason: "no_device" });
  });

  it("respects the per-campaign notification toggle", () => {
    expect(evaluateCampaignEligibility({ ...baseInput, preferenceEnabled: false })).toEqual({
      allowed: false,
      reason: "opted_out"
    });
  });

  it("blocks quiet hours in the player's own timezone", () => {
    expect(evaluateCampaignEligibility({ ...baseInput, localHour: 23 }).reason).toBe("quiet_hours");
    expect(evaluateCampaignEligibility({ ...baseInput, localHour: 7 }).reason).toBe("quiet_hours");
    expect(evaluateCampaignEligibility({ ...baseInput, localHour: 9 }).allowed).toBe(true);
    expect(evaluateCampaignEligibility({ ...baseInput, localHour: 21 }).allowed).toBe(true);
  });

  it("enforces the daily cap", () => {
    expect(
      evaluateCampaignEligibility({ ...baseInput, lifecycleDeliveriesLast24h: DEFAULT_MAX_PER_DAY }).reason
    ).toBe("daily_cap");
  });

  it("enforces the weekly cap even when the daily budget is free", () => {
    expect(
      evaluateCampaignEligibility({
        ...baseInput,
        lifecycleDeliveriesLast24h: 0,
        lifecycleDeliveriesLast7d: DEFAULT_MAX_PER_WEEK
      }).reason
    ).toBe("weekly_cap");
  });

  it("keeps a campaign silent inside its own cooldown", () => {
    expect(
      evaluateCampaignEligibility({ ...baseInput, hoursSinceLastCampaignDelivery: 24 }).reason
    ).toBe("campaign_cooldown");
    expect(
      evaluateCampaignEligibility({ ...baseInput, hoursSinceLastCampaignDelivery: 200 }).allowed
    ).toBe(true);
  });

  it("lets the digest override the default daily cap", () => {
    const digestInput: CampaignEligibilityInput = {
      ...baseInput,
      campaignKey: "hot_search_digest",
      lifecycleDeliveriesLast24h: 1,
      hoursSinceLastCampaignDelivery: 6
    };

    expect(evaluateCampaignEligibility(digestInput).allowed).toBe(true);
    expect(evaluateCampaignEligibility({ ...digestInput, lifecycleDeliveriesLast24h: 2 }).reason).toBe(
      "daily_cap"
    );
  });

  it("treats the cooldown check as stricter than the caps", () => {
    const result = evaluateCampaignEligibility({
      ...baseInput,
      hoursSinceLastCampaignDelivery: 1,
      lifecycleDeliveriesLast24h: DEFAULT_MAX_PER_DAY
    });

    expect(result.reason).toBe("campaign_cooldown");
  });
});

describe("quiet hours", () => {
  it("covers the night window across midnight", () => {
    expect(isQuietHour(22)).toBe(true);
    expect(isQuietHour(3)).toBe(true);
    expect(isQuietHour(8)).toBe(true);
    expect(isQuietHour(9)).toBe(false);
    expect(isQuietHour(12)).toBe(false);
  });
});

describe("local hour resolution", () => {
  const noonUtc = new Date("2026-09-02T12:00:00.000Z");

  it("uses the player's timezone", () => {
    expect(resolveLocalHour("Europe/Moscow", noonUtc)).toBe(15);
    expect(resolveLocalHour("Europe/London", noonUtc)).toBe(13);
    expect(resolveLocalHour("Asia/Dubai", noonUtc)).toBe(16);
  });

  it("falls back to Moscow for empty or broken timezones", () => {
    expect(resolveLocalHour(null, noonUtc)).toBe(15);
    expect(resolveLocalHour("", noonUtc)).toBe(15);
    expect(resolveLocalHour("Not/AZone", noonUtc)).toBe(15);
  });
});

describe("lifecycle holdout", () => {
  it("is disabled when the percentage is zero", () => {
    expect(resolveLifecycleVariant("user-a", 0)).toBe("treatment");
  });

  it("is stable for the same player", () => {
    const first = resolveLifecycleVariant("user-a", 10);
    expect(resolveLifecycleVariant("user-a", 10)).toBe(first);
    expect(getHoldoutBucket("user-a")).toBe(getHoldoutBucket("user-a"));
  });

  it("splits the audience roughly by the configured percentage", () => {
    const users = Array.from({ length: 4000 }, (_, index) => `user-${index}`);
    const holdout = users.filter((userId) => resolveLifecycleVariant(userId, 10) === "holdout").length;

    expect(holdout / users.length).toBeGreaterThan(0.07);
    expect(holdout / users.length).toBeLessThan(0.13);
  });

  it("keeps buckets inside 0-99", () => {
    for (const userId of ["", "a", "cldz9k1x0000abcdefghijk", "🎾"]) {
      const bucket = getHoldoutBucket(userId);
      expect(bucket).toBeGreaterThanOrEqual(0);
      expect(bucket).toBeLessThan(100);
    }
  });
});

describe("lifecycle kill switch", () => {
  const original = process.env.LIFECYCLE_CAMPAIGNS_ENABLED;

  afterEach(() => {
    if (original === undefined) {
      delete process.env.LIFECYCLE_CAMPAIGNS_ENABLED;
    } else {
      process.env.LIFECYCLE_CAMPAIGNS_ENABLED = original;
    }
  });

  it("stays off unless explicitly enabled", () => {
    delete process.env.LIFECYCLE_CAMPAIGNS_ENABLED;
    expect(lifecycleCampaignsEnabled()).toBe(false);

    process.env.LIFECYCLE_CAMPAIGNS_ENABLED = "";
    expect(lifecycleCampaignsEnabled()).toBe(false);

    process.env.LIFECYCLE_CAMPAIGNS_ENABLED = "false";
    expect(lifecycleCampaignsEnabled()).toBe(false);
  });

  it("turns on for the documented values", () => {
    for (const value of ["1", "true", "TRUE", "yes"]) {
      process.env.LIFECYCLE_CAMPAIGNS_ENABLED = value;
      expect(lifecycleCampaignsEnabled()).toBe(true);
    }
  });
});
