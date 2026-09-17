import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({
  findUser: vi.fn(), findCourts: vi.fn(), memberships: vi.fn(), findPlace: vi.fn(), findPlaces: vi.fn(),
  searches: vi.fn(), maintenance: vi.fn()
}));
vi.mock("@/lib/prisma", () => ({ prisma: {
  user: { findUnique: mocks.findUser }, userCourt: { findMany: mocks.memberships },
  court: { findMany: mocks.findCourts }, geoPlace: { findUnique: mocks.findPlace, findMany: mocks.findPlaces },
  gameSearch: { findMany: mocks.searches, updateMany: mocks.maintenance }
} }));
import { getCourtsForUser, getEmptyDeckClubSections } from "@/server/app-data";

const user = { id: "viewer", city: "Home", locationPlaceId: "place:home", homeLat: 0, homeLng: 0,
  preferredSports: ["tennis", "padel"], preferredDistricts: [], district: null };
const place = { id: "place:home", city: "Home", latitude: 0, longitude: 0 };
const court = (id: string, latitude: number, sport = "tennis", city = "Other") => ({
  id, city, name: id, locationLat: latitude, locationLng: 0, supportedSports: [sport],
  status: "active", district: null, nearestMetro: null, metroLinks: [], members: [], _count: { members: 0 }, rating: 4
});

beforeEach(() => {
  vi.clearAllMocks();
  mocks.findUser.mockResolvedValue(user);
  mocks.memberships.mockResolvedValue([]);
  mocks.findPlace.mockResolvedValue(place);
  mocks.findPlaces.mockResolvedValue([]);
  mocks.searches.mockResolvedValue([]);
  mocks.maintenance.mockResolvedValue({ count: 0 });
  mocks.findCourts.mockResolvedValue([]);
});

describe("nearby courts service", () => {
  it("keeps local courts and does not query an expanded region when matches exist", async () => {
    mocks.findCourts.mockResolvedValue([court("local", 0.01, "tennis", "Home")]);
    const result = await getCourtsForUser(user.id, { sport: "tennis" });
    expect(result.map((row) => row.id)).toEqual(["local"]);
    expect(result[0].nearby).toBeUndefined();
    expect(mocks.findCourts).toHaveBeenCalledTimes(1);
    expect(mocks.findCourts.mock.calls[0][0].where.city).toBe("Home");
  });
  it("a local wrong-sport court does not suppress nearby requested-sport courts", async () => {
    mocks.findCourts.mockImplementation(async ({ where }) => where.city ? [court("padel", 0.01, "padel", "Home")]
      : [court("tennis", 0.3), court("wrong-sport", 0.001, "padel"), court("far", 3), court("invalid", NaN)]);
    const result = await getCourtsForUser(user.id, { sport: "tennis" });
    expect(result.map((row) => row.id)).toEqual(["tennis"]);
    expect(result[0].nearby).toMatchObject({ originCity: "Home", radiusKm: 50 });
    expect(result[0].distanceKm).toBeGreaterThan(33);
    expect(mocks.findCourts.mock.calls[1][0].where).toMatchObject({ status: "active", city: undefined, district: undefined });
  });
  it("does not mistake a same-named faraway city for the selected canonical city", async () => {
    mocks.findCourts.mockImplementation(async ({ where }) => where.city ? [court("wrong-country", 40, "tennis", "Home")]
      : [court("nearby", 0.1)]);
    const result = await getCourtsForUser(user.id, { city: "Home", locationPlaceId: "place:home", sport: "tennis" });
    expect(result.map((row) => row.id)).toEqual(["nearby"]);
    expect(result[0].nearby?.radiusKm).toBe(25);
  });
  it("uses selected canonical city coordinates instead of old home even if city names are identical", async () => {
    mocks.findPlace.mockResolvedValue({ ...place, id: "selected", latitude: 40 });
    mocks.findCourts.mockResolvedValue([court("new-location", 40.01, "tennis", "Home")]);
    const result = await getCourtsForUser(user.id, { city: "Home", locationPlaceId: "selected", sport: "tennis" });
    expect(result[0].distanceKm).toBeLessThan(2);
    expect(result[0].nearby).toBeUndefined();
    expect(user.homeLat).toBe(0);
  });
  it("caps nearby output after nearest-first sorting and filters unsafe player previews", async () => {
    mocks.findCourts.mockImplementation(async ({ where }) => where.city ? []
      : Array.from({ length: 10 }, (_, i) => court(`c${9 - i}`, 0.1 + (9 - i) / 100)));
    const result = await getCourtsForUser(user.id, { city: "Home", sport: "tennis" });
    expect(result.map((row) => row.id)).toEqual(["c0", "c1", "c2", "c3", "c4", "c5"]);
    const memberWhere = mocks.findCourts.mock.calls[1][0].include.members.where;
    expect(memberWhere).toMatchObject({ userId: { not: user.id }, user: {
      accountStatus: "active", isVerified: true, onboardingCompleted: true,
      blockedUsers: { none: { blockedUserId: user.id } }, blockingUsers: { none: { blockerUserId: user.id } }
    } });
    expect(mocks.searches.mock.calls[0][0].where.createdByUser).toMatchObject({ accountStatus: "active",
      blockedUsers: { none: { blockedUserId: user.id } } });
  });
  it("supports guest empty-deck clubs with independent sport radii and no membership queries", async () => {
    mocks.findCourts.mockImplementation(async ({ where }) => where.city ? [] : [court("t", 0.1), court("p", 0.7, "padel")]);
    const sections = await getEmptyDeckClubSections(null, { city: "Home", locationPlaceId: "place:home", sport: ["tennis", "padel"] });
    expect(sections.map((section) => [section.sport, section.courts[0].nearby?.radiusKm])).toEqual([["tennis", 25], ["padel", 100]]);
    expect(mocks.findUser).not.toHaveBeenCalled();
    expect(mocks.memberships).not.toHaveBeenCalled();
  });
  it("does not query the world when guest origin is absent or selected canonical place is invalid", async () => {
    expect(await getCourtsForUser(null)).toEqual([]);
    mocks.findPlace.mockResolvedValue(null);
    expect(await getCourtsForUser(user.id, { city: "Home", locationPlaceId: "invalid" })).toEqual([]);
    expect(mocks.findCourts).not.toHaveBeenCalled();
  });
});
