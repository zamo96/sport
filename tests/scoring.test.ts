import { describe, expect, it } from "vitest";
import { Gender, PlayFormat, Sport, Surface } from "@prisma/client";

import { overlapSlots, scoreCandidate, scoreCandidates } from "@/lib/scoring";

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
  isLookingForGame: true
};

describe("scoring", () => {
  it("uses stable place ids to separate same-named cities", () => {
    const ranked = scoreCandidates(
      { ...viewer, city: "Springfield", locationPlaceId: "place:us-il-springfield" },
      [
        { ...viewer, id: "same-place", city: "Springfield", locationPlaceId: "place:us-il-springfield" },
        { ...viewer, id: "different-place", city: "Springfield", locationPlaceId: "place:us-ma-springfield" }
      ]
    );

    expect(ranked.map((candidate) => candidate.id)).toEqual(["same-place"]);
  });

  it("does not match a global place id to an untrusted raw city", () => {
    const ranked = scoreCandidates(
      { ...viewer, city: "Berlin", locationPlaceId: "nominatim:relation:62422" },
      [{ ...viewer, id: "raw-berlin", city: "Berlin", locationPlaceId: null }]
    );
    expect(ranked).toEqual([]);
  });

  it("keeps migrated legacy place ids compatible with old raw city profiles", () => {
    const ranked = scoreCandidates(
      { ...viewer, city: "Москва", locationPlaceId: "legacy:ru:moscow" },
      [{ ...viewer, id: "old-moscow", city: "Moscow", locationPlaceId: null }]
    );
    expect(ranked.map((candidate) => candidate.id)).toEqual(["old-moscow"]);
  });

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

  it("prioritizes preferred district overlap over raw distance", () => {
    const ranked = scoreCandidates(
      {
        ...viewer,
        district: "primorsky",
        preferredDistricts: ["primorsky"],
        homeLat: 59.993,
        homeLng: 30.2398
      },
      [
        {
          ...viewer,
          id: "near-outside-district",
          name: "Near Outside",
          district: "central",
          preferredDistricts: ["central"],
          homeLat: 59.994,
          homeLng: 30.241
        },
        {
          ...viewer,
          id: "preferred-district",
          name: "Preferred District",
          district: "primorsky",
          preferredDistricts: ["primorsky"],
          homeLat: 60.03,
          homeLng: 30.31
        }
      ]
    );

    expect(ranked.map((candidate) => candidate.id)).toEqual(["preferred-district", "near-outside-district"]);
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

  it("does not require isLookingForGame in hot mode when sport matches", () => {
    const ranked = scoreCandidates(
      viewer,
      [
        {
          ...viewer,
          id: "hot-candidate",
          preferredSports: [Sport.tennis],
          sportLevels: { tennis: 5 },
          isLookingForGame: false
        }
      ],
      {
        view: "hot",
        sport: [Sport.tennis]
      }
    );

    expect(ranked.map((candidate) => candidate.id)).toEqual(["hot-candidate"]);
  });

  it("uses age as a soft recommendation signal", () => {
    const ranked = scoreCandidates(viewer, [
      {
        ...viewer,
        id: "older",
        age: 52
      },
      {
        ...viewer,
        id: "close-age",
        age: 29
      }
    ]);

    expect(ranked.map((candidate) => candidate.id)).toEqual(["close-age", "older"]);
    expect(ranked[0]?.ageGap).toBe(2);
  });

  it("excludes candidates outside the viewer city in default discover", () => {
    const ranked = scoreCandidates(viewer, [
      {
        ...viewer,
        id: "saint-petersburg",
        city: "Санкт-Петербург"
      },
      {
        ...viewer,
        id: "moscow-alias",
        city: "Москва"
      },
      {
        ...viewer,
        id: "kazan",
        city: "Kazan"
      },
      {
        ...viewer,
        id: "missing-city",
        city: null
      }
    ]);

    expect(ranked.map((candidate) => candidate.id)).toEqual(["moscow-alias"]);
  });

  it.each(["Санкт-Петербург", "Санкт Петербург", "Петербург", "СПб", "Saint Petersburg", "St. Petersburg", "St Petersburg"])(
    "treats %s as a Saint Petersburg alias in swipe discover",
    (candidateCity) => {
      const ranked = scoreCandidates(
        { ...viewer, city: "СПб" },
        [
          { ...viewer, id: "local", city: candidateCity },
          { ...viewer, id: "moscow", city: "Москва" },
          { ...viewer, id: "missing-city", city: null }
        ],
        { view: "swipe" }
      );

      expect(ranked.map((candidate) => candidate.id)).toEqual(["local"]);
    }
  );

  it("normalizes city aliases in explicit city filters", () => {
    const ranked = scoreCandidates(
      { ...viewer, city: null },
      [
        { ...viewer, id: "kazan", city: "Казань" },
        { ...viewer, id: "moscow", city: "Москва" },
        { ...viewer, id: "missing-city", city: null }
      ],
      { city: "Kazan", view: "likes" }
    );

    expect(ranked.map((candidate) => candidate.id)).toEqual(["kazan"]);
  });

  it.each(["hot", "seeking"] as const)(
    "isolates %s recommendations to the viewer canonical city",
    (view) => {
      const ranked = scoreCandidates(
        { ...viewer, city: "Kazan" },
        [
          { ...viewer, id: "kazan-alias", city: "Казань" },
          { ...viewer, id: "saint-petersburg", city: "Санкт-Петербург" },
          { ...viewer, id: "saint-petersburg-alias", city: "СПб" },
          { ...viewer, id: "missing-city", city: null }
        ],
        { view }
      );

      expect(ranked.map((candidate) => candidate.id)).toEqual(["kazan-alias"]);
    }
  );

  it("keeps likes cross-city while preserving canonical city aliases", () => {
    const ranked = scoreCandidates(
      { ...viewer, city: "Казань" },
      [
        { ...viewer, id: "kazan-alias", city: "Kazan" },
        { ...viewer, id: "saint-petersburg", city: "Санкт-Петербург" },
        { ...viewer, id: "saint-petersburg-alias", city: "СПб" },
        { ...viewer, id: "missing-city", city: null }
      ],
      { view: "likes" }
    );

    expect(ranked.map((candidate) => candidate.id)).toEqual(
      expect.arrayContaining([
        "kazan-alias",
        "saint-petersburg",
        "saint-petersburg-alias",
        "missing-city"
      ])
    );
  });

  it("does not compare districts across canonical cities", () => {
    const viewerWithDistrict = {
      ...viewer,
      district: "central",
      preferredDistricts: ["central"]
    };
    const matchingDistrict = scoreCandidate(
      viewerWithDistrict,
      { ...viewer, id: "matching-district", city: "Казань", district: "central", preferredDistricts: ["central"] },
      { view: "likes" }
    );
    const differentDistrict = scoreCandidate(
      viewerWithDistrict,
      { ...viewer, id: "different-district", city: "Kazan", district: "other", preferredDistricts: ["other"] },
      { view: "likes" }
    );

    expect(matchingDistrict?.score).toBe(differentDistrict?.score);
  });

  it("prioritizes exact day-time slot overlap over broad range overlap", () => {
    const ranked = scoreCandidates(
      {
        ...viewer,
        availableDays: ["monday"],
        availableTimeRanges: ["evening"],
        availableTimeSlots: ["monday-evening"]
      },
      [
        {
          ...viewer,
          id: "broad-evening",
          availableDays: ["monday"],
          availableTimeRanges: ["evening"],
          availableTimeSlots: []
        },
        {
          ...viewer,
          id: "exact-evening",
          availableDays: ["monday"],
          availableTimeRanges: ["evening"],
          availableTimeSlots: ["monday-evening"]
        }
      ]
    );

    expect(ranked.map((candidate) => candidate.id)).toEqual(["exact-evening", "broad-evening"]);
    expect(ranked[0]?.exactTimeSlotOverlapCount).toBe(1);
  });
});
