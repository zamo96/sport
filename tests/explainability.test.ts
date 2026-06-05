import { describe, expect, it } from "vitest";
import { Gender, PlayFormat, Sport, Surface } from "@prisma/client";

import { buildDiscoverExplainabilityReasons } from "@/lib/scoring";

const viewer = {
  id: "viewer",
  name: "Анна",
  age: 27,
  gender: Gender.female,
  city: "Moscow",
  bio: "",
  avatarUrl: null,
  homeLat: 55.75,
  homeLng: 37.61,
  tennisLevel: 5,
  preferredSports: [Sport.tennis, Sport.padel],
  sportLevels: { tennis: 5, padel: 4 },
  preferredPlayFormat: PlayFormat.singles,
  preferredSurface: Surface.clay,
  availableDays: ["monday", "wednesday"],
  availableTimeRanges: ["evening"],
  availableTimeSlots: ["monday-evening", "wednesday-evening"],
  searchRadiusKm: 20,
  isLookingForGame: true
};

describe("discover explainability", () => {
  it("returns up to 4 reasons when distance and availability are known", () => {
    const candidate = {
      ...viewer,
      id: "candidate",
      name: "Игорь",
      preferredSports: [Sport.tennis],
      sportLevels: { tennis: 6 },
      homeLat: 55.751,
      homeLng: 37.62,
      availableDays: ["wednesday"],
      availableTimeRanges: ["evening"]
    };

    const reasons = buildDiscoverExplainabilityReasons(viewer, candidate);

    expect(reasons.length).toBe(4);
    expect(reasons.join(" · ")).toContain("Совпадает спорт");
    expect(reasons.join(" · ")).toContain("Уровень рядом");
    expect(reasons.join(" · ")).toContain("Недалеко:");
    expect(reasons).toContain("Пересекается расписание");
  });

  it("falls back to 2 reasons when there is no distance/availability data", () => {
    const viewerNoData = {
      ...viewer,
      id: "viewer-no-data",
      homeLat: null,
      homeLng: null,
      availableDays: [],
      availableTimeRanges: [],
      availableTimeSlots: []
    };
    const candidateNoData = {
      ...viewerNoData,
      id: "candidate-no-data",
      preferredSports: [Sport.tennis],
      sportLevels: { tennis: 5 },
      homeLat: null,
      homeLng: null,
      availableDays: [],
      availableTimeRanges: [],
      availableTimeSlots: []
    };

    const reasons = buildDiscoverExplainabilityReasons(viewerNoData, candidateNoData);

    expect(reasons.length).toBe(2);
    expect(reasons.join(" · ")).toContain("Совпадает спорт");
    expect(reasons.join(" · ")).toContain("Уровень рядом");
  });

  it("prefers latest search sport in seeking/hot views when available", () => {
    const candidate = {
      ...viewer,
      id: "candidate-seeking",
      preferredSports: [Sport.tennis, Sport.padel],
      sportLevels: { tennis: 5, padel: 4 },
      gameSearches: [{ sport: Sport.padel }]
    } as typeof viewer & { gameSearches: Array<{ sport: Sport }> };

    const reasons = buildDiscoverExplainabilityReasons(viewer, candidate, { view: "seeking" });

    expect(reasons[0]).toContain("Падел");
  });

  it("is deterministic and keeps a stable reason order when distance and schedule are present", () => {
    const candidate = {
      ...viewer,
      id: "candidate-stable",
      name: "Мария",
      preferredSports: [Sport.tennis],
      sportLevels: { tennis: 6 },
      homeLat: 55.751,
      homeLng: 37.62,
      availableDays: ["wednesday"],
      availableTimeRanges: ["evening"]
    };

    const first = buildDiscoverExplainabilityReasons(viewer, candidate);
    const second = buildDiscoverExplainabilityReasons(viewer, candidate);

    expect(first).toEqual(second);
    expect(first.length).toBe(4);
    expect(first[0]).toMatch(/^Совпадает спорт:/);
    expect(first[1]).toMatch(/^Уровень рядом:/);
    expect(first[2]).toMatch(/^Недалеко:/);
    expect(first[3]).toBe("Пересекается расписание");
  });

  it("does not leak private strings (name/id/district) in fallback district explainability", () => {
    const viewerWithDistrict = {
      ...viewer,
      id: "viewer-private",
      name: "Секретный зритель",
      homeLat: null,
      homeLng: null,
      district: "Арбат",
      preferredDistricts: ["Арбат"],
      availableDays: [],
      availableTimeRanges: [],
      availableTimeSlots: []
    };
    const candidateWithDistrict = {
      ...viewerWithDistrict,
      id: "candidate-private",
      name: "Секретный кандидат",
      district: "Арбат",
      preferredDistricts: ["Арбат"]
    };

    const reasons = buildDiscoverExplainabilityReasons(viewerWithDistrict, candidateWithDistrict);
    const text = reasons.join(" · ");

    expect(reasons[0]).toMatch(/^Совпадает спорт:/);
    expect(reasons[1]).toMatch(/^Уровень рядом:/);
    expect(reasons[2]).toBe("Рядом по району");
    expect(text).not.toContain("Секретный кандидат");
    expect(text).not.toContain("candidate-private");
    expect(text).not.toContain("Арбат");
  });
});
