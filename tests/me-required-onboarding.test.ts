import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({ session: vi.fn(), update: vi.fn(), place: vi.fn(), record: vi.fn() }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.session, getSessionUser: mocks.session, destroySession: vi.fn() }));
vi.mock("@/lib/prisma", () => ({ prisma: { user: { update: mocks.update } } }));
vi.mock("@/server/user-events", () => ({ recordUserEventsOnce: mocks.record }));
vi.mock("@/server/serializers", () => ({ serializeMe: (user: unknown) => user }));
vi.mock("@/server/locations", () => ({ getLocationPlace: mocks.place, ensureLegacyLocation: mocks.place,
  shouldPreserveCurrentGlobalLocation: () => false }));
import { PATCH } from "@/app/me/route";

const current = { id: "user", onboardingCompleted: false, showOnMap: false, tennisLevel: 5, timezone: "Europe/Moscow" };
const profile = { name: "Анна", age: 28, city: "Санкт-Петербург", preferredSports: ["padel"],
  sportLevels: { padel: null }, preferredPlayFormat: "both", preferredSurface: "any" };
const request = (body: object) => new NextRequest("http://localhost/me", {
  method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify(body)
});

beforeEach(() => {
  vi.clearAllMocks();
  mocks.session.mockResolvedValue(current);
  mocks.place.mockResolvedValue({ id: "legacy:ru:saint-petersburg", city: "Санкт-Петербург", latitude: 59.9386,
    longitude: 30.3141, coverage: { districtsEnabled: true, legacyCity: "Санкт-Петербург" } });
  mocks.update.mockImplementation(async ({ data }) => ({ ...current, ...data }));
});

describe("/me onboarding completion invariant", () => {
  it.each([undefined, [], ["unsupported"]])("rejects missing or invalid sports %j without completion", async (preferredSports) => {
    expect((await PATCH(request({ ...profile, preferredSports }))).status).toBe(400);
    expect(mocks.update).not.toHaveBeenCalled();
    expect(mocks.record).not.toHaveBeenCalled();
  });

  it.each([undefined, "", "   "])("rejects missing or blank city %j without completion", async (city) => {
    expect((await PATCH(request({ ...profile, city }))).status).toBe(400);
    expect(mocks.update).not.toHaveBeenCalled();
    expect(mocks.record).not.toHaveBeenCalled();
  });

  it("rejects an unresolved place without saving completion", async () => {
    mocks.place.mockResolvedValueOnce(null);
    expect((await PATCH(request({ ...profile, city: undefined, locationPlaceId: "missing-place" }))).status).toBe(404);
    expect(mocks.update).not.toHaveBeenCalled();
    expect(mocks.record).not.toHaveBeenCalled();
  });

  it.each([
    { city: "Санкт-Петербург" },
    { city: undefined, locationPlaceId: "legacy:ru:saint-petersburg" }
  ])("completes with a resolved city or place and a sport, without optional profile fields: %j", async (location) => {
    const response = await PATCH(request({ ...profile, ...location }));
    expect(response.status).toBe(200);
    const user = (await response.json()).user;
    expect(user).toMatchObject({ onboardingCompleted: true, preferredSports: ["padel"], sportLevels: { padel: null },
      city: "Санкт-Петербург", availableDays: [], availableTimeRanges: [] });
    expect(mocks.record).toHaveBeenCalledTimes(1);
  });
});
