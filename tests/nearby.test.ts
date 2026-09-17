import { describe, expect, it } from "vitest";
import { nearbyRadiusStages, selectNearby, validCoordinates } from "@/lib/nearby";
import { scoreCandidate, type CandidateUser } from "@/lib/scoring";

const viewer: CandidateUser = {
  id: "viewer", name: null, age: null, gender: null, city: "Origin", locationPlaceId: "origin",
  bio: null, avatarUrl: null, homeLat: 0, homeLng: 0, tennisLevel: 5,
  preferredSports: ["tennis"], sportLevels: { tennis: 5 }, preferredPlayFormat: "singles",
  preferredSurface: "hard", availableDays: ["monday"], availableTimeRanges: ["evening"],
  availableTimeSlots: ["monday-evening"], isLookingForGame: true
};
const candidate = { ...viewer, id: "nearby", city: "Other", locationPlaceId: "other", homeLat: 0.1 };

describe("bounded nearby selection", () => {
  it("uses the first populated stage and sorts distance before score", () => {
    const rows = [
      { id: "far", distanceKm: 51, score: 999 },
      { id: "b", distanceKm: 30, score: 1 },
      { id: "a", distanceKm: 30, score: 1 },
      { id: "near", distanceKm: 26, score: 0 }
    ];
    const selected = selectNearby(rows, "Origin", 2, undefined, (a, b) => b.score - a.score);
    expect(selected.map((row) => row.id)).toEqual(["near", "a"]);
    expect(selected[0].nearby).toEqual({ originCity: "Origin", radiusKm: 50, distanceKm: 26 });
    expect(rows.map((row) => row.id)).toEqual(["far", "b", "a", "near"]);
  });
  it("includes the 200 km boundary and excludes unknown, negative, infinite and farther distances", () => {
    const distances = [null, NaN, Infinity, -1, 200.001, 1000, 200];
    expect(selectNearby(distances.map((distanceKm, id) => ({ id: String(id), distanceKm })), "Origin", 12)
      .map((row) => row.distanceKm)).toEqual([200]);
    expect(selectNearby([{ id: "far", distanceKm: 201 }], "Origin", 12)).toEqual([]);
  });
  it("starts at the explicit radius then expands visibly, bounded at 200", () => {
    expect(nearbyRadiusStages()).toEqual([25, 50, 100, 200]);
    expect(nearbyRadiusStages(80)).toEqual([80, 100, 200]);
    expect(nearbyRadiusStages(500)).toEqual([200]);
    expect(selectNearby([{ id: "a", distanceKm: 90 }], "Origin", 12, 80)[0].nearby.radiusKm).toBe(100);
  });
  it("accepts genuine zero coordinates, rejects missing, NaN and out-of-range coordinates", () => {
    expect(validCoordinates({ lat: 0, lng: 0 })).toBe(true);
    for (const coordinates of [null, { lat: NaN, lng: 0 }, { lat: 91, lng: 0 }, { lat: 0, lng: -181 }]) {
      expect(validCoordinates(coordinates)).toBe(false);
    }
  });
});

describe("nearby scoring preserves non-geographic eligibility", () => {
  it("keeps ordinary scoring strict and explicitly allows nearby geography", () => {
    expect(scoreCandidate(viewer, candidate)).toBeNull();
    expect(scoreCandidate(viewer, candidate, {}, "nearby")?.distanceKm).toBeGreaterThan(11);
    expect(viewer.city).toBe("Origin");
    expect(candidate.city).toBe("Other");
  });
  it.each([
    { sport: ["padel"] }, { levelMin: 6 }, { gender: ["female"] },
    { format: ["doubles"] }, { surface: ["clay"] }, { day: ["tuesday"] }, { timeRange: ["morning"] }
  ] as Parameters<typeof scoreCandidate>[2][])("preserves filters %j", (filters) => {
    expect(scoreCandidate(viewer, candidate, filters, "nearby")).toBeNull();
  });
  it("does not transform an unknown origin or candidate into zero-distance results", () => {
    expect(scoreCandidate({ ...viewer, homeLat: null }, candidate, {}, "nearby")).toBeNull();
    expect(scoreCandidate(viewer, { ...candidate, homeLat: null }, {}, "nearby")).toBeNull();
    expect(scoreCandidate(viewer, { ...candidate, homeLng: Infinity }, {}, "nearby")).toBeNull();
  });
});
