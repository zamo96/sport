import { describe, expect, it } from "vitest";

import { calculateRecommendationScore } from "@/server/recommendations";
import { resolveHotDigestSlot } from "@/server/hot-search-digest";

const baseSignals = {
  baseScore: 100,
  inactiveDays: 8,
  viewerImpressionCount: 0,
  hoursSinceViewerLastImpression: null,
  candidateExposureCount: 0,
  averageExposureCount: 2,
  candidateInboundInterestCount: 0,
  averageInboundInterestCount: 1,
  hasActiveSearch: true,
  isLookingForGame: true,
  createdAt: new Date("2026-06-28T10:00:00.000Z"),
  lastActiveAt: new Date()
};

describe("recommendation re-ranking", () => {
  it("boosts comparable underexposed players over overloaded players", () => {
    const underexposed = calculateRecommendationScore(baseSignals);
    const overloaded = calculateRecommendationScore({
      ...baseSignals,
      candidateExposureCount: 12,
      candidateInboundInterestCount: 6
    });

    expect(underexposed).toBeGreaterThan(overloaded);
  });

  it("penalizes recently repeated cards for the same viewer", () => {
    const freshForViewer = calculateRecommendationScore(baseSignals);
    const repeatedForViewer = calculateRecommendationScore({
      ...baseSignals,
      viewerImpressionCount: 3,
      hoursSinceViewerLastImpression: 2
    });

    expect(repeatedForViewer).toBeLessThan(freshForViewer);
  });
});

describe("hot search digest slot", () => {
  it("opens the midday digest window in Moscow time", () => {
    const slot = resolveHotDigestSlot(new Date("2026-07-01T09:05:00.000Z"));

    expect(slot?.slotKey).toBe("2026-07-01:midday");
    expect(slot?.since.toISOString()).toBe("2026-06-30T15:00:00.000Z");
  });

  it("opens the evening digest window in Moscow time", () => {
    const slot = resolveHotDigestSlot(new Date("2026-07-01T15:30:00.000Z"));

    expect(slot?.slotKey).toBe("2026-07-01:evening");
    expect(slot?.since.toISOString()).toBe("2026-07-01T09:00:00.000Z");
  });

  it("does not send digest outside configured windows", () => {
    expect(resolveHotDigestSlot(new Date("2026-07-01T08:30:00.000Z"))).toBeNull();
  });
});
