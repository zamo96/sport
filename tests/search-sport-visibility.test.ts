import { describe, expect, it } from "vitest";

import { scoreCandidate, type CandidateUser } from "@/lib/scoring";

const viewer = {
  id: "viewer",
  name: "Матвейка",
  age: 30,
  gender: null,
  city: "Санкт-Петербург",
  bio: null,
  avatarUrl: null,
  homeLat: 59.9386,
  homeLng: 30.3141,
  tennisLevel: 5,
  preferredSports: ["tennis", "squash"],
  sportLevels: { tennis: 5 },
  preferredPlayFormat: "both",
  preferredSurface: "any",
  availableDays: [],
  availableTimeRanges: [],
  availableTimeSlots: {},
  isLookingForGame: true
} as unknown as CandidateUser;

// Профиль — бадминтон и настольный теннис, а срочный поиск создан по теннису.
const evgeniy = {
  ...viewer,
  id: "evgeniy",
  name: "Evgeniy",
  preferredSports: ["badminton", "table_tennis"],
  sportLevels: { badminton: 5, table_tennis: 5 },
  gameSearches: [{ sport: "tennis", isActive: true }]
} as unknown as CandidateUser;

describe("search sport decides visibility on the search tabs", () => {
  it("shows the author on the hot tab through the sport of the search itself", () => {
    expect(scoreCandidate(viewer, evgeniy, { view: "hot" })).not.toBeNull();
  });

  it("does the same on the seeking tab", () => {
    expect(scoreCandidate(viewer, evgeniy, { view: "seeking" })).not.toBeNull();
  });

  it("keeps the swipe deck matching on profiles only", () => {
    expect(scoreCandidate(viewer, evgeniy, { view: "swipe" })).toBeNull();
  });

  it("keeps incoming likes matching on profiles only", () => {
    expect(scoreCandidate(viewer, evgeniy, {})).toBeNull();
  });

  it("ignores searches in a sport the viewer does not play", () => {
    const boxer = { ...evgeniy, gameSearches: [{ sport: "boxing", isActive: true }] } as unknown as CandidateUser;
    expect(scoreCandidate(viewer, boxer, { view: "hot" })).toBeNull();
  });

  it("still matches on the profile when the author has no searches", () => {
    const badmintonOnly = { ...evgeniy, gameSearches: [] } as unknown as CandidateUser;
    expect(scoreCandidate(viewer, badmintonOnly, { view: "hot" })).toBeNull();

    const shared = { ...badmintonOnly, preferredSports: ["squash"] } as unknown as CandidateUser;
    expect(scoreCandidate(viewer, shared, { view: "hot" })).not.toBeNull();
  });
});
