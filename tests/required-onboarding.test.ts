import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createDefaultGuestOnboardingDraft, guestDraftCanCompleteOnboarding, guestDraftHasProfileBasics,
  loadGuestOnboardingDraft, selectedOnboardingSports, guestDraftFieldsForOnboarding
} from "@/lib/guest-draft";
import { guestDiscoverSchema, updateMeSchema } from "@/lib/validators";

const completeDraft = () => ({ ...createDefaultGuestOnboardingDraft(), name: "Анна", age: 28,
  city: "Санкт-Петербург", preferredSports: ["padel" as const], sportLevels: { padel: null } });

afterEach(() => vi.unstubAllGlobals());

describe("required onboarding selections", () => {
  it("does not silently choose a city or sport for new users", () => {
    const draft = createDefaultGuestOnboardingDraft();
    expect(draft.city).toBe("");
    expect(draft.preferredSports).toEqual([]);
    expect(selectedOnboardingSports(undefined)).toEqual([]);
    expect(selectedOnboardingSports([])).toEqual([]);
    expect(guestDraftCanCompleteOnboarding(draft)).toBe(false);
  });

  it("allows the profile step before choosing a city, but blocks completion", () => {
    const draft = { ...completeDraft(), city: "" };
    expect(guestDraftHasProfileBasics(draft)).toBe(true);
    expect(guestDraftCanCompleteOnboarding(draft)).toBe(false);
  });

  it.each(["", "   ", "\n\t"])("rejects missing city %j even with profile basics", (city) => {
    expect(guestDraftCanCompleteOnboarding({ ...completeDraft(), city })).toBe(false);
  });

  it("blocks removing the last selected sport", () => {
    expect(guestDraftCanCompleteOnboarding({ ...completeDraft(), preferredSports: [] })).toBe(false);
    expect(selectedOnboardingSports(["unsupported"])).toEqual([]);
  });

  it("allows valid choices without availability, districts, or a known level", () => {
    expect(guestDraftCanCompleteOnboarding(completeDraft())).toBe(true);
    expect(guestDiscoverSchema.safeParse({ draft: completeDraft() }).success).toBe(true);
    expect(updateMeSchema.safeParse({ ...completeDraft(), locationPlaceId: undefined }).success).toBe(true);
  });

  it("preserves saved choices while keeping missing city drafts incomplete", () => {
    let stored = JSON.stringify(completeDraft());
    vi.stubGlobal("window", { localStorage: { getItem: () => stored } });
    expect(loadGuestOnboardingDraft()).toMatchObject({ city: "Санкт-Петербург", preferredSports: ["padel"] });
    const { city: _city, ...incomplete } = completeDraft();
    stored = JSON.stringify(incomplete);
    expect(loadGuestOnboardingDraft()?.city).toBe("");
    expect(guestDraftCanCompleteOnboarding(loadGuestOnboardingDraft()!)).toBe(false);
  });

  it("rejects malformed saved sport or city values without throwing", () => {
    for (const fields of [{ preferredSports: null }, { preferredSports: ["unsupported"] }, { city: null }]) {
      vi.stubGlobal("window", { localStorage: { getItem: () => JSON.stringify({ ...completeDraft(), ...fields }) } });
      expect(guestDraftCanCompleteOnboarding(loadGuestOnboardingDraft()!)).toBe(false);
    }
  });

  it("requires guest discovery selections before applying draft defaults", () => {
    const { city: _city, ...withoutCity } = completeDraft();
    expect(guestDiscoverSchema.safeParse({ draft: withoutCity }).success).toBe(false);
    expect(guestDiscoverSchema.safeParse({ draft: { ...completeDraft(), preferredSports: [] } }).success).toBe(false);
  });
});


describe("resuming an incomplete guest profile after sign-in", () => {
  it("restores the entered name and sport while the unchosen city still blocks completion", () => {
    const draft = { ...completeDraft(), city: "", availableDays: ["monday"], availableTimeRanges: ["evening"],
      availabilityByDay: { monday: ["evening"] } };
    const fields = guestDraftFieldsForOnboarding({ name: null, age: null, city: null, preferredSports: null, showOnMap: true }, draft);
    const resumed = { ...createDefaultGuestOnboardingDraft(), ...fields };
    expect(resumed).toMatchObject({ name: "Анна", age: 28, city: "", preferredSports: ["padel"], sportLevels: { padel: null },
      availableDays: ["monday"], availabilityByDay: { monday: ["evening"] } });
    expect(guestDraftCanCompleteOnboarding(resumed)).toBe(false);
    expect(guestDraftCanCompleteOnboarding({ ...resumed, city: "Москва" })).toBe(true);
  });

  it("keeps a chosen city while requiring the missing sport", () => {
    const fields = guestDraftFieldsForOnboarding({}, { ...completeDraft(), preferredSports: [] });
    const resumed = { ...createDefaultGuestOnboardingDraft(), ...fields };
    expect(resumed).toMatchObject({ city: "Санкт-Петербург", preferredSports: [], sportLevels: {} });
    expect(guestDraftCanCompleteOnboarding(resumed)).toBe(false);
  });

  it("does not replace server choices or copy districts from a different guest city", () => {
    const fields = guestDraftFieldsForOnboarding({ name: "Мария", age: 35, city: "Москва", preferredSports: ["tennis"],
      sportLevels: { tennis: 7 }, showOnMap: false }, { ...completeDraft(), preferredDistricts: ["primorsky"], district: "primorsky" });
    expect(fields.name).toBeUndefined();
    expect(fields.age).toBeUndefined();
    expect(fields.city).toBeUndefined();
    expect(fields.preferredSports).toBeUndefined();
    expect(fields.sportLevels).toBeUndefined();
    expect(fields.district).toBeUndefined();
    expect(fields.preferredDistricts).toBeUndefined();
    expect(fields.showOnMap).toBe(false);
  });

  it.each([[true, false, false], [false, true, false], [true, true, true]])(
    "retains map preferences saved=%s draft=%s as %s", (saved, draft, expected) => {
      expect(guestDraftFieldsForOnboarding({ showOnMap: saved }, { ...completeDraft(), showOnMap: draft }).showOnMap).toBe(expected);
    }
  );

  it("preserves global location identity and does not add absent selections", () => {
    expect(guestDraftFieldsForOnboarding({}, { ...completeDraft(), city: "Paris", locationPlaceId: "catalog:fr:paris" }))
      .toMatchObject({ city: "Paris", locationPlaceId: "catalog:fr:paris" });
    expect(guestDraftFieldsForOnboarding({}, createDefaultGuestOnboardingDraft()))
      .toMatchObject({ city: "", preferredSports: [], sportLevels: {} });
  });
});
