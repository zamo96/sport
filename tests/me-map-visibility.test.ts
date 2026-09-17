import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks = vi.hoisted(() => ({ session: vi.fn(), update: vi.fn(), place: vi.fn(), record: vi.fn() }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.session, getSessionUser: mocks.session, destroySession: vi.fn() }));
vi.mock("@/lib/prisma", () => ({ prisma: { user: { update: mocks.update } } }));
vi.mock("@/server/user-events", () => ({ recordUserEventsOnce: mocks.record }));
vi.mock("@/server/locations", () => ({
  getLocationPlace: mocks.place, ensureLegacyLocation: mocks.place,
  shouldPreserveCurrentGlobalLocation: () => false,
  serializeLocationRelation: () => null, emptyCoverage: () => ({ districtsEnabled: false })
}));
import { PATCH } from "@/app/me/route";

const current = { id: "user", showOnMap: true, onboardingCompleted: true, tennisLevel: 5, city: "Санкт-Петербург", preferredDistricts: ["primorsky"] };
const body = { name: "Анна", age: 30, city: "Санкт-Петербург", preferredDistricts: ["primorsky"], preferredSports: ["tennis"],
  sportLevels: { tennis: 5 }, preferredPlayFormat: "both", preferredSurface: "any", availableDays: [], availableTimeRanges: [] };
function request(data: object) { return new NextRequest("http://localhost/me", { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify(data) }); }

beforeEach(() => {
  vi.clearAllMocks();
  mocks.session.mockResolvedValue(current);
  mocks.place.mockResolvedValue({ id: "legacy:ru:saint-petersburg", city: "Санкт-Петербург", latitude: 59.9386, longitude: 30.3141,
    coverage: { districtsEnabled: true, legacyCity: "Санкт-Петербург" } });
  mocks.update.mockImplementation(async ({ data }) => ({ ...current, ...Object.fromEntries(Object.entries(data).filter(([, value]) => value !== undefined)) }));
});

describe("/me map opt-in persistence", () => {
  it("keeps a returning user's disabled setting when omitted", async () => {
    mocks.session.mockResolvedValueOnce({ ...current, showOnMap: false });
    mocks.update.mockImplementationOnce(async ({ data }) => ({ ...current, showOnMap: false, ...Object.fromEntries(Object.entries(data).filter(([, value]) => value !== undefined)) }));
    const response = await PATCH(request(body));
    expect(response.status).toBe(200);
    expect(mocks.update.mock.lastCall?.[0].data.showOnMap).toBeUndefined();
    expect((await response.json()).user.showOnMap).toBe(false);
  });
  it("saves an explicit onboarding opt-out", async () => {
    mocks.session.mockResolvedValueOnce({ ...current, onboardingCompleted: false });
    const response = await PATCH(request({ ...body, showOnMap: false }));
    expect(response.status).toBe(200);
    expect((await response.json()).user.showOnMap).toBe(false);
    expect(mocks.update.mock.lastCall?.[0].data.showOnMap).toBe(false);
  });
  it("preserves the existing choice when an older client omits showOnMap", async () => {
    const response = await PATCH(request(body));
    expect(response.status).toBe(200);
    expect(mocks.update.mock.calls[0][0].data.showOnMap).toBeUndefined();
    expect((await response.json()).user.showOnMap).toBe(true);
  });
  it("preserves narrow stored districts when an older client omits both preferences and map setting", async () => {
    const { preferredDistricts: _preferences, ...olderBody } = body;
    const response = await PATCH(request(olderBody));
    expect(response.status).toBe(200);
    expect(mocks.update.mock.lastCall?.[0].data.preferredDistricts).toEqual(["primorsky"]);
    const saved = (await response.json()).user;
    expect(saved.showOnMap).toBe(true);
    expect(saved.preferredDistricts).toEqual(["primorsky"]);
  });
  it("preserves stored null (no chosen districts) when the PATCH field is omitted", async () => {
    mocks.session.mockResolvedValueOnce({ ...current, preferredDistricts: null });
    const { preferredDistricts: _preferences, ...olderBody } = body;
    expect((await PATCH(request(olderBody))).status).toBe(200);
    expect(mocks.update.mock.lastCall?.[0].data.preferredDistricts).toBeUndefined();
  });
  it("stores an explicit opt-in and revocation", async () => {
    for (const showOnMap of [true, false]) {
      const response = await PATCH(request({ ...body, showOnMap }));
      expect(response.status).toBe(200);
      expect((await response.json()).user.showOnMap).toBe(showOnMap);
      expect(mocks.update.mock.lastCall?.[0].data.showOnMap).toBe(showOnMap);
    }
  });
  it("does not broaden wholly foreign districts while opting in or preserving an existing opt-in", async () => {
    for (const setting of [{ showOnMap: true }, {}]) {
      expect((await PATCH(request({ ...body, ...setting, preferredDistricts: ["moscow_central"] }))).status).toBe(400);
    }
    expect(mocks.update).not.toHaveBeenCalled();
  });
  it("allows explicit whole-city clearing and allows revocation despite stale districts", async () => {
    expect((await PATCH(request({ ...body, preferredDistricts: [], showOnMap: true }))).status).toBe(200);
    expect(mocks.update.mock.lastCall?.[0].data.preferredDistricts).toEqual([]);
    expect((await PATCH(request({ ...body, preferredDistricts: ["moscow_central"], showOnMap: false }))).status).toBe(200);
  });
  it.each([null, {}, [123], [""], ["   "], ["", " "], [","], [" , "], ["primorsky", 123], "", "[]", "primorsky"])(
    "rejects malformed raw districts without broadening an existing opt-in: %j",
    async (preferredDistricts) => {
      const response = await PATCH(request({ ...body, preferredDistricts }));
      expect(response.status).toBe(400);
      expect(mocks.update).not.toHaveBeenCalled();
    }
  );
  it("rejects malformed raw districts when enabling map visibility", async () => {
    mocks.session.mockResolvedValueOnce({ ...current, showOnMap: false });
    expect((await PATCH(request({ ...body, preferredDistricts: null, showOnMap: true }))).status).toBe(400);
    expect(mocks.update).not.toHaveBeenCalled();
  });
  it("normalizes stale districts for a city with no district coverage instead of blocking opt-in", async () => {
    mocks.place.mockResolvedValueOnce({ id: "catalog:fr:paris", city: "Paris", latitude: 48.85, longitude: 2.35,
      coverage: { districtsEnabled: false, legacyCity: null } });
    const response = await PATCH(request({ ...body, city: "Paris", preferredDistricts: ["primorsky"], showOnMap: true }));
    expect(response.status).toBe(200);
    expect(mocks.update.mock.lastCall?.[0].data.preferredDistricts).toEqual([]);
    expect(mocks.update.mock.lastCall?.[0].data.showOnMap).toBe(true);
  });
  it("rejects non-boolean consent values", async () => {
    expect((await PATCH(request({ ...body, showOnMap: "true" }))).status).toBe(400);
    expect(mocks.update).not.toHaveBeenCalled();
  });
});
