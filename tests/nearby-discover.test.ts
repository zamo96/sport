import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  findUser: vi.fn(), findUsers: vi.fn(), findPlace: vi.fn(), findPlaces: vi.fn(),
  impressions: vi.fn(), rerank: vi.fn()
}));
vi.mock("@/lib/prisma", () => ({ prisma: {
  user: { findUnique: mocks.findUser, findMany: mocks.findUsers },
  geoPlace: { findUnique: mocks.findPlace, findMany: mocks.findPlaces }
} }));
vi.mock("@/server/recommendations", () => ({
  recordDiscoverImpressions: mocks.impressions,
  rerankDiscoverCandidates: mocks.rerank
}));

import { getDiscoverCandidates, getDiscoverCandidatesForGuestDraft, summarizeDiscoverCandidates } from "@/server/discover";
import { createDefaultGuestOnboardingDraft } from "@/lib/guest-draft";
import { resolveNearbyOrigin } from "@/server/nearby-location";

const viewer = {
  id: "viewer", name: "Viewer", age: 30, gender: "male", city: "Home", locationPlaceId: "place:home",
  district: null, preferredDistricts: [], bio: "", avatarUrl: null, homeLat: 0, homeLng: 0,
  tennisLevel: 5, preferredSports: ["tennis"], sportLevels: { tennis: 5 }, preferredPlayFormat: "singles",
  preferredSurface: "hard", availableDays: ["monday"], availableTimeRanges: ["evening"],
  availableTimeSlots: ["monday-evening"], isLookingForGame: true, createdAt: new Date(), lastActiveAt: new Date()
};
const place = { id: "place:home", provider: "nominatim", providerPlaceId: "1", city: "Home", latitude: 0, longitude: 0,
  countryCode: "GH", countryName: "Ghana", region: null, serviceArea: null };
const other = (id: string, homeLat: number | null) => ({ ...viewer, id, city: "Other", locationPlaceId: "place:other", homeLat,
  location: null, gameSearches: [] });

beforeEach(() => {
  vi.clearAllMocks();
  mocks.findUser.mockResolvedValue(viewer);
  mocks.findUsers.mockResolvedValue([]);
  mocks.findPlace.mockResolvedValue(place);
  mocks.findPlaces.mockResolvedValue([]);
  mocks.rerank.mockImplementation(async (_id, candidates) => candidates);
});

describe("nearby discover service", () => {
  it("retains the identical local list and order when it is nonempty", async () => {
    mocks.findUsers.mockResolvedValue([{ ...other("local", 0.05), city: viewer.city, locationPlaceId: viewer.locationPlaceId }, other("nearer", 0.001)]);
    const result = await getDiscoverCandidates(viewer.id);
    expect(result.map((user) => user.id)).toEqual(["local"]);
    expect(result[0].nearby).toBeUndefined();
  });
  it("reuses the fully protected candidate pool, measures nearby results and caps only after sorting", async () => {
    mocks.findUsers.mockResolvedValue([other("outside", 3), other("unknown", null),
      ...Array.from({ length: 16 }, (_, index) => other(`p${index}`, 0.1 + index / 100))]);
    const result = await getDiscoverCandidates(viewer.id);
    expect(result).toHaveLength(12);
    expect(result[0].id).toBe("p0");
    expect(result.every((user) => user.nearby?.radiusKm === 25)).toBe(true);
    expect(mocks.findUsers).toHaveBeenCalledTimes(1);
    expect(mocks.findUsers.mock.calls[0][0].where).toMatchObject({
      id: { not: viewer.id }, accountStatus: "active", onboardingCompleted: true, isVerified: true,
      blockedUsers: { none: { blockedUserId: viewer.id } },
      blockingUsers: { none: { blockerUserId: viewer.id } },
      swipesReceived: { none: { fromUserId: viewer.id } },
      matchesAsUser1: { none: { user2Id: viewer.id, status: "active" } },
      matchesAsUser2: { none: { user1Id: viewer.id, status: "active" } }
    });
    expect(mocks.impressions).toHaveBeenCalledTimes(1);
    expect(viewer.city).toBe("Home");
  });
  it("preserves filters and does not let a local wrong-sport candidate suppress fallback", async () => {
    mocks.findUsers.mockResolvedValue([
      { ...other("local-padel", 0), city: viewer.city, locationPlaceId: viewer.locationPlaceId, preferredSports: ["padel"] },
      other("tennis", 0.3), { ...other("wrong-level", 0.01), sportLevels: { tennis: 9 } }
    ]);
    const result = await getDiscoverCandidates(viewer.id, { sport: ["tennis"], levelMax: 6 });
    expect(result.map((user) => user.id)).toEqual(["tennis"]);
    expect(result[0].nearby?.radiusKm).toBe(50);
  });
  it("notification count uses the same capped eligible selection without recording impressions", async () => {
    mocks.findUsers.mockResolvedValue([other("near", 0.1)]);
    expect(await summarizeDiscoverCandidates(viewer.id)).toEqual({ total: 1, fresh: 0 });
    expect(mocks.impressions).not.toHaveBeenCalled();
    expect(mocks.rerank).not.toHaveBeenCalled();
  });
  it.each(["hot", "seeking", "likes", "upcoming"] as const)("never adds nearby metadata to %s", async (view) => {
    mocks.findUsers.mockResolvedValue([other("near", 0.1)]);
    expect((await getDiscoverCandidates(viewer.id, { view })).every((user) => user.nearby == null)).toBe(true);
  });
  it("supports guest canonical city and produces the same nearby geometry without impressions", async () => {
    mocks.findUsers.mockResolvedValue([other("near", 0.1)]);
    const draft = { ...createDefaultGuestOnboardingDraft(), city: "Home", locationPlaceId: place.id,
      preferredSports: ["tennis"] as ["tennis"], sportLevels: { tennis: 5 } };
    const result = await getDiscoverCandidatesForGuestDraft(draft);
    expect(result[0].nearby).toMatchObject({ originCity: "Home", radiusKm: 25 });
    expect(mocks.impressions).not.toHaveBeenCalled();
    expect(mocks.findUsers.mock.calls[0][0].where).toMatchObject({ accountStatus: "active", isVerified: true, onboardingCompleted: true });
  });
  it("does not use missing canonical coordinates or a distant same-name place as zero", async () => {
    mocks.findPlace.mockResolvedValue(null);
    mocks.findUsers.mockResolvedValue([other("near", 0.1)]);
    expect(await getDiscoverCandidates(viewer.id)).toEqual([]);
  });
});

describe("nearby origin identity", () => {
  it("never resolves invalid selected place ID using the old profile coordinates", async () => {
    mocks.findPlace.mockResolvedValue(null);
    expect(await resolveNearbyOrigin(viewer, "Other", "missing-place")).toBeNull();
  });
  it("does not choose an arbitrary same-named global city", async () => {
    mocks.findPlaces.mockResolvedValue([place, { ...place, id: "elsewhere", latitude: 40 }]);
    expect(await resolveNearbyOrigin(null, "Ambiguous")).toBeNull();
  });
});
