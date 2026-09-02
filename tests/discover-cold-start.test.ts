import { describe, expect, it } from "vitest";

import { scoreCandidate, scoreCandidates, type CandidateUser } from "@/lib/scoring";
import { widenCandidateSearch } from "@/server/discover";

function player(overrides: Partial<CandidateUser> & { id: string }): CandidateUser {
  return {
    name: "Игрок",
    age: 30,
    gender: null,
    city: "Санкт-Петербург",
    locationPlaceId: null,
    district: null,
    preferredDistricts: [],
    bio: null,
    avatarUrl: null,
    homeLat: 59.9343,
    homeLng: 30.3351,
    tennisLevel: 5,
    preferredSports: ["tennis"],
    sportLevels: { tennis: 5 },
    preferredPlayFormat: "both",
    preferredSurface: "any",
    availableDays: ["monday"],
    availableTimeRanges: ["evening"],
    availableTimeSlots: [],
    searchRadiusKm: 20,
    isLookingForGame: true,
    ...overrides
  } as CandidateUser;
}

const viewer = player({ id: "viewer" });
// Выборг — примерно 120 км от Петербурга.
const otherCity = player({ id: "vyborg", city: "Выборг", homeLat: 60.7146, homeLng: 28.7529 });

describe("nearby city fallback", () => {
  it("hides other cities by default", () => {
    expect(scoreCandidate(viewer, otherCity)).toBeNull();
  });

  it("lets them in once the radius covers them", () => {
    expect(scoreCandidate(viewer, otherCity, {}, { nearbyRadiusKm: 60 })).toBeNull();

    const scored = scoreCandidate(viewer, otherCity, {}, { nearbyRadiusKm: 200 });
    expect(scored).not.toBeNull();
    expect(scored?.isNearbyFallback).toBe(true);
    expect(scored?.distanceKm).toBeGreaterThan(100);
  });

  it("never overrides a city the player picked explicitly", () => {
    expect(
      scoreCandidate(viewer, otherCity, { city: "Санкт-Петербург" }, { nearbyRadiusKm: 500 })
    ).toBeNull();
  });

  it("does not mark same-city players as a fallback", () => {
    const neighbour = player({ id: "neighbour" });
    const scored = scoreCandidate(viewer, neighbour, {}, { nearbyRadiusKm: 200 });
    expect(scored?.isNearbyFallback).toBeUndefined();
  });
});

describe("widening", () => {
  it("stops at the first step that fills the screen", () => {
    const calls: Array<number | undefined> = [];
    const result = widenCandidateSearch((radius) => {
      calls.push(radius);
      return radius == null ? [] : new Array(6).fill(0);
    });

    expect(calls).toEqual([undefined, 60]);
    expect(result).toHaveLength(6);
  });

  it("does not widen when there are already enough players", () => {
    const calls: Array<number | undefined> = [];
    widenCandidateSearch((radius) => {
      calls.push(radius);
      return new Array(9).fill(0);
    });

    expect(calls).toEqual([undefined]);
  });

  it("returns the widest attempt when nothing fills the screen", () => {
    const calls: Array<number | undefined> = [];
    const result = widenCandidateSearch((radius) => {
      calls.push(radius);
      return radius === 200 ? new Array(2).fill(0) : [];
    });

    expect(calls).toEqual([undefined, 60, 200]);
    expect(result).toHaveLength(2);
  });
});

describe("scoreCandidates passes the radius through", () => {
  it("includes the other city only when widened", () => {
    expect(scoreCandidates(viewer, [otherCity])).toHaveLength(0);
    expect(scoreCandidates(viewer, [otherCity], {}, { nearbyRadiusKm: 200 })).toHaveLength(1);
  });
});
