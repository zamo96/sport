import { describe, expect, it } from "vitest";
import { Gender, PlayFormat, Sport, Surface } from "@prisma/client";

import { overlapSlots, scoreCandidates } from "@/lib/scoring";

const viewer = {
  id: "viewer",
  name: "Anna",
  age: 27,
  gender: Gender.female,
  city: "Moscow",
  bio: "",
  avatarUrl: null,
  homeLat: 55.75,
  homeLng: 37.61,
  tennisLevel: 5,
  preferredSports: ["tennis", "padel"],
  sportLevels: { tennis: 5, padel: 4 },
  preferredPlayFormat: PlayFormat.singles,
  preferredSurface: Surface.clay,
  availableDays: ["monday", "wednesday", "saturday"],
  availableTimeRanges: ["evening", "morning"],
  availableTimeSlots: ["monday-evening", "wednesday-evening", "saturday-morning"],
  searchRadiusKm: 20,
  isLookingForGame: true
};

describe("scoring", () => {
  it("ranks closer and better-matched players first", () => {
    const candidates = [
      {
        ...viewer,
        id: "best",
        name: "Best",
        homeLat: 55.76,
        homeLng: 37.62
      },
      {
        ...viewer,
        id: "worse",
        name: "Worse",
        homeLat: 55.9,
        homeLng: 37.9,
        tennisLevel: 8,
        preferredSports: ["squash"],
        sportLevels: { squash: 8 },
        preferredSurface: Surface.hard,
        availableDays: ["friday"],
        availableTimeRanges: ["day"],
        isLookingForGame: false
      }
    ];

    const ranked = scoreCandidates(viewer, candidates);

    expect(ranked[0]?.id).toBe("best");
    expect(ranked[0]?.score).toBeGreaterThan(ranked[1]?.score ?? 0);
  });

  it("applies explicit format and surface filters strictly", () => {
    const candidates = [
      {
        ...viewer,
        id: "exact",
        name: "Exact",
        preferredPlayFormat: PlayFormat.singles,
        preferredSurface: Surface.clay
      },
      {
        ...viewer,
        id: "broad",
        name: "Broad",
        preferredPlayFormat: PlayFormat.both,
        preferredSurface: Surface.any
      }
    ];

    const byFormat = scoreCandidates(viewer, candidates, { format: [PlayFormat.singles] });
    const bySurface = scoreCandidates(viewer, candidates, { surface: [Surface.clay] });

    expect(byFormat.map((candidate) => candidate.id)).toEqual(["exact"]);
    expect(bySurface.map((candidate) => candidate.id)).toEqual(["exact"]);
  });

  it("counts availability overlap from slot arrays", () => {
    expect(overlapSlots(["monday-evening", "wednesday-day"], ["monday-evening"])).toBe(1);
  });

  it("supports multi-select filters for sport, day and time", () => {
    const candidates = [
      {
        ...viewer,
        id: "padel-evening",
        name: "Padel Evening",
        preferredSports: [Sport.padel],
        sportLevels: { padel: 4 },
        availableDays: ["friday"],
        availableTimeRanges: ["evening"]
      },
      {
        ...viewer,
        id: "tennis-morning",
        name: "Tennis Morning",
        preferredSports: [Sport.tennis],
        sportLevels: { tennis: 5 },
        availableDays: ["sunday"],
        availableTimeRanges: ["morning"]
      },
      {
        ...viewer,
        id: "squash-day",
        name: "Squash Day",
        preferredSports: [Sport.squash],
        sportLevels: { squash: 6 },
        availableDays: ["thursday"],
        availableTimeRanges: ["day"]
      }
    ];

    const ranked = scoreCandidates(viewer, candidates, {
      sport: [Sport.tennis, Sport.padel],
      day: ["friday", "sunday"],
      timeRange: ["morning", "evening"]
    });

    expect(ranked.map((candidate) => candidate.id)).toEqual(["padel-evening", "tennis-morning"]);
  });

  it("filters by city and gender", () => {
    const candidates = [
      {
        ...viewer,
        id: "moscow-female",
        name: "Moscow Female",
        city: "Moscow",
        gender: Gender.female
      },
      {
        ...viewer,
        id: "moscow-male",
        name: "Moscow Male",
        city: "Moscow",
        gender: Gender.male
      },
      {
        ...viewer,
        id: "berlin-female",
        name: "Berlin Female",
        city: "Berlin",
        gender: Gender.female
      }
    ];

    const ranked = scoreCandidates(viewer, candidates, {
      city: "Moscow",
      gender: [Gender.female]
    });

    expect(ranked.map((candidate) => candidate.id)).toEqual(["moscow-female"]);
  });
});
