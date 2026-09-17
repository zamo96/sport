import { describe, expect, it } from "vitest";
import { DISTRICT_MAP_AREAS, MOSCOW_DISTRICT_OPTIONS, SAINT_PETERSBURG_DISTRICT_OPTIONS } from "@/lib/constants";
import { publicPlayerMapAreas } from "@/lib/player-map-areas";
import { normalizeProfilePreferredDistricts } from "@/lib/profile-map-preferences";

const base = { showOnMap: true, city: "Санкт-Петербург", preferredDistricts: ["primorsky", "petrogradsky", "primorsky"] };
const moscow = { id: "legacy:ru:moscow", city: "Москва", countryCode: "RU", latitude: 55.7558, longitude: 37.6173,
  serviceArea: { isActive: true, districtsEnabled: true, legacyCity: "Москва" } };

describe("explicit player map membership", () => {
  it("requires an explicit true setting, including old response omissions", () => {
    expect(publicPlayerMapAreas({ ...base, showOnMap: false })).toEqual([]);
    expect(publicPlayerMapAreas({ ...base, showOnMap: undefined })).toEqual([]);
  });
  it("emits deduplicated selected areas in catalogue order using only public centers", () => {
    const profile = { ...base, district: "moscow_central", homeLat: 12.34567, homeLng: 76.54321 };
    const result = publicPlayerMapAreas(profile);
    expect(result.map((area) => area.districtId)).toEqual(["petrogradsky", "primorsky"]);
    expect(result[0]).toMatchObject({ cityId: "legacy:ru:saint-petersburg", cityName: "Санкт-Петербург", kind: "district",
      latitude: DISTRICT_MAP_AREAS.petrogradsky.center.lat, longitude: DISTRICT_MAP_AREAS.petrogradsky.center.lng });
    expect(JSON.stringify(result)).not.toContain("12.34567");
    expect(JSON.stringify(result)).not.toContain("76.54321");
  });
  it("treats an explicit empty preference array as whole-city membership, never the legacy primary district", () => {
    expect(publicPlayerMapAreas({ ...base, preferredDistricts: [], district: "central" } as typeof base).map((area) => area.districtId))
      .toEqual([...SAINT_PETERSBURG_DISTRICT_OPTIONS]);
  });
  it("treats persisted null as no selected districts and ignores the legacy primary district", () => {
    const profile = { ...base, preferredDistricts: null, district: "central" };
    expect(publicPlayerMapAreas(profile).map((area) => area.districtId)).toEqual([...SAINT_PETERSBURG_DISTRICT_OPTIONS]);
    expect(publicPlayerMapAreas({ ...profile, showOnMap: false })).toEqual([]);
  });
  it("does not broaden a partial projection with omitted or undefined districts", () => {
    expect(publicPlayerMapAreas({ showOnMap: true, city: base.city })).toEqual([]);
    expect(publicPlayerMapAreas({ ...base, preferredDistricts: undefined })).toEqual([]);
  });
  it("uses each Moscow district when canonical city preferences are empty", () => {
    expect(publicPlayerMapAreas({ ...base, locationPlaceId: moscow.id, location: moscow, preferredDistricts: [] })
      .map((area) => area.districtId)).toEqual([...MOSCOW_DISTRICT_OPTIONS]);
    expect(publicPlayerMapAreas({ ...base, locationPlaceId: moscow.id, location: moscow, preferredDistricts: null })
      .map((area) => area.districtId)).toEqual([...MOSCOW_DISTRICT_OPTIONS]);
  });
  it.each([["moscow_central"], ["invalid"], [123], "central", {}, [""]])("does not expand a nonempty invalid/foreign selection: %j", (preferredDistricts) => {
    expect(publicPlayerMapAreas({ ...base, preferredDistricts })).toEqual([]);
  });
  it("retains valid members of a mixed selection without broadening", () => {
    expect(publicPlayerMapAreas({ ...base, preferredDistricts: ["invalid", "primorsky", "moscow_central"] })
      .map((area) => area.districtId)).toEqual(["primorsky"]);
  });
  it("never borrows districts for a same-named city in another country", () => {
    const location = { ...moscow, id: "catalog:us:moscow", countryCode: "US", city: "Moscow", latitude: 46.73, longitude: -117.00 };
    expect(publicPlayerMapAreas({ ...base, locationPlaceId: location.id, location })).toEqual([{
      id: `${location.id}:city`, cityId: location.id, cityName: "Moscow", kind: "city", districtId: null,
      label: "Moscow", latitude: 46.73, longitude: -117.00
    }]);
  });
  it("uses one canonical city center when district coverage is unavailable", () => {
    const location = { ...moscow, serviceArea: { ...moscow.serviceArea, districtsEnabled: false } };
    expect(publicPlayerMapAreas({ ...base, location })).toHaveLength(1);
    expect(publicPlayerMapAreas({ ...base, location })[0]).toMatchObject({ kind: "city", districtId: null, latitude: location.latitude });
    expect(publicPlayerMapAreas({ ...base, location, preferredDistricts: null })).toHaveLength(1);
    expect(publicPlayerMapAreas({ ...base, city: "Казань" })[0]).toMatchObject({ kind: "city", cityName: "Казань" });
  });
  it("fails closed for unknown city identity, unresolved places, mismatches and invalid centers", () => {
    for (const profile of [
      { ...base, city: "Moscow Idaho" }, { ...base, locationPlaceId: "unresolved", city: "Moscow" },
      { ...base, locationPlaceId: "other-place", location: moscow },
      { ...base, location: { ...moscow, latitude: NaN } }, { ...base, location: { ...moscow, longitude: 181 } }
    ]) expect(publicPlayerMapAreas(profile)).toEqual([]);
  });
  it("web defaults preserve empty choices and invalid selections until explicit correction", () => {
    expect(normalizeProfilePreferredDistricts([])).toEqual([]);
    expect(normalizeProfilePreferredDistricts(null)).toEqual([]);
    expect(normalizeProfilePreferredDistricts(["primorsky", "primorsky"])).toEqual(["primorsky"]);
    expect(normalizeProfilePreferredDistricts(["invalid"])).toEqual(["invalid"]);
  });
});
