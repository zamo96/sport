import { PlayFormat, Surface, type Gender, type Sport, type User } from "@prisma/client";

import { SPORT_OPTIONS, type DistrictOption } from "@/lib/constants";
import { normalizeSportLevels, type SportLevelValue } from "@/lib/sport-levels";

export const GUEST_ONBOARDING_DRAFT_KEY = "guest-onboarding-draft:v1";

export type GuestOnboardingDraft = {
  name: string;
  age: number;
  gender: Gender | null;
  city: string;
  locationPlaceId?: string | null;
  district: DistrictOption | null;
  preferredDistricts: DistrictOption[];
  preferredSports: Sport[];
  sportLevels: Partial<Record<Sport, SportLevelValue>>;
  preferredPlayFormat: PlayFormat;
  preferredSurface: Surface;
  showOnMap: boolean;
  isLookingForGame: boolean;
  availableDays: string[];
  availableTimeRanges: string[];
  availabilityByDay: Partial<Record<string, string[]>>;
};

export function createDefaultGuestOnboardingDraft(): GuestOnboardingDraft {
  return {
    name: "",
    age: 0,
    gender: null,
    city: "",
    locationPlaceId: null,
    district: null,
    preferredDistricts: [],
    preferredSports: [],
    sportLevels: {},
    preferredPlayFormat: PlayFormat.both,
    preferredSurface: Surface.any,
    showOnMap: true,
    isLookingForGame: true,
    availableDays: [],
    availableTimeRanges: [],
    availabilityByDay: {}
  };
}

export function saveGuestOnboardingDraft(draft: GuestOnboardingDraft) {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(GUEST_ONBOARDING_DRAFT_KEY, JSON.stringify(draft));
}

export function loadGuestOnboardingDraft() {
  if (typeof window === "undefined") {
    return null;
  }

  const raw = window.localStorage.getItem(GUEST_ONBOARDING_DRAFT_KEY);

  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw) as Partial<GuestOnboardingDraft>;
    const defaultDraft = createDefaultGuestOnboardingDraft();
    const fallbackDistrict = parsed.district && typeof parsed.district === "string" ? parsed.district : null;
    const hasUserEnteredProfile =
      (typeof parsed.name === "string" && parsed.name.trim().length > 0) ||
      (Array.isArray(parsed.preferredSports) && parsed.preferredSports.length > 0);
    const normalizedAge = parsed.age === 28 && !hasUserEnteredProfile ? 0 : parsed.age;

    return {
      ...defaultDraft,
      ...parsed,
      age: normalizedAge ?? defaultDraft.age,
      showOnMap: typeof parsed.showOnMap === "boolean" ? parsed.showOnMap : defaultDraft.showOnMap,
      preferredDistricts: Array.isArray(parsed.preferredDistricts)
        ? parsed.preferredDistricts.filter((district): district is DistrictOption => typeof district === "string")
        : fallbackDistrict
          ? [fallbackDistrict]
          : []
    };
  } catch {
    return null;
  }
}

export function clearGuestOnboardingDraft() {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.removeItem(GUEST_ONBOARDING_DRAFT_KEY);
}

export function selectedOnboardingSports(value: unknown): Sport[] {
  return Array.isArray(value)
    ? value.filter((sport): sport is Sport => SPORT_OPTIONS.includes(sport as Sport))
    : [];
}

export function guestDraftHasProfileBasics(draft: GuestOnboardingDraft) {
  return typeof draft.name === "string" && draft.name.trim().length >= 2 && draft.age >= 18 && draft.age <= 100
    && selectedOnboardingSports(draft.preferredSports).length > 0;
}

export function guestDraftCanCompleteOnboarding(draft: GuestOnboardingDraft) {
  return guestDraftHasProfileBasics(draft)
    && typeof draft.city === "string" && draft.city.trim().length > 0;
}

// Resume an unfinished account without replacing its saved choices with the guest draft.
export function guestDraftFieldsForOnboarding(user: Partial<User>, draft: GuestOnboardingDraft): Partial<GuestOnboardingDraft> {
  const fields: Partial<GuestOnboardingDraft> = {};
  if (!user.name?.trim() && typeof draft.name === "string" && draft.name.trim().length >= 2) fields.name = draft.name.trim();
  if (user.age == null && Number.isInteger(draft.age) && draft.age >= 18 && draft.age <= 100) fields.age = draft.age;
  if (user.gender == null) fields.gender = draft.gender;
  if (!user.city?.trim() && typeof draft.city === "string") {
    fields.city = draft.city.trim();
    fields.locationPlaceId = draft.locationPlaceId ?? undefined;
  }
  if (selectedOnboardingSports(user.preferredSports).length === 0) {
    fields.preferredSports = selectedOnboardingSports(draft.preferredSports);
    fields.sportLevels = fields.preferredSports.length > 0
      ? normalizeSportLevels(draft.sportLevels, fields.preferredSports)
      : {};
  }
  // District choices belong to their city and must never follow a different saved city.
  if (!user.city?.trim() || user.city.trim() === draft.city?.trim()) {
    if (user.preferredDistricts == null) fields.preferredDistricts = draft.preferredDistricts;
    if (user.district == null) fields.district = draft.district;
  }
  if (user.availableDays == null) fields.availableDays = draft.availableDays;
  if (user.availableTimeRanges == null) fields.availableTimeRanges = draft.availableTimeRanges;
  if (user.availabilityByDay == null) fields.availabilityByDay = draft.availabilityByDay;
  if (user.preferredPlayFormat == null) fields.preferredPlayFormat = draft.preferredPlayFormat;
  if (user.preferredSurface == null) fields.preferredSurface = draft.preferredSurface;
  if (user.isLookingForGame == null) fields.isLookingForGame = draft.isLookingForGame;
  fields.showOnMap = mapVisibilityForGuestPromotion(user.showOnMap, draft.showOnMap);
  return fields;
}

export function buildGuestAuthHref(continueTo: string) {
  const params = new URLSearchParams({
    step: "email",
    continue: continueTo
  });

  return `/auth?${params.toString()}`;
}

// A guest draft can disable the saved choice, but must never re-enable a returning account.
export function mapVisibilityForGuestPromotion(savedShowOnMap: boolean | undefined, draftShowOnMap: boolean) {
  return savedShowOnMap === true && draftShowOnMap;
}
