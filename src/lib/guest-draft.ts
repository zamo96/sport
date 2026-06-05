import { PlayFormat, Surface, type Gender, type Sport } from "@prisma/client";

import { DEFAULT_CITY, type DistrictOption } from "@/lib/constants";
import { type SportLevelValue } from "@/lib/sport-levels";

export const GUEST_ONBOARDING_DRAFT_KEY = "guest-onboarding-draft:v1";

export type GuestOnboardingDraft = {
  name: string;
  age: number;
  gender: Gender | null;
  city: string;
  district: DistrictOption | null;
  preferredDistricts: DistrictOption[];
  preferredSports: Sport[];
  sportLevels: Partial<Record<Sport, SportLevelValue>>;
  preferredPlayFormat: PlayFormat;
  preferredSurface: Surface;
  searchRadiusKm: number;
  isLookingForGame: boolean;
  availableDays: string[];
  availableTimeRanges: string[];
  availabilityByDay: Partial<Record<string, string[]>>;
};

export function createDefaultGuestOnboardingDraft(): GuestOnboardingDraft {
  return {
    name: "",
    age: 28,
    gender: null,
    city: DEFAULT_CITY,
    district: null,
    preferredDistricts: [],
    preferredSports: [],
    sportLevels: {},
    preferredPlayFormat: PlayFormat.both,
    preferredSurface: Surface.any,
    searchRadiusKm: 20,
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
    const fallbackDistrict = parsed.district && typeof parsed.district === "string" ? parsed.district : null;

    return {
      ...createDefaultGuestOnboardingDraft(),
      ...parsed,
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

export function guestDraftHasProfileBasics(draft: GuestOnboardingDraft) {
  return draft.name.trim().length >= 2 && draft.age >= 18 && draft.preferredSports.length > 0;
}

export function buildGuestAuthHref(continueTo: string) {
  const params = new URLSearchParams({
    step: "email",
    continue: continueTo
  });

  return `/auth?${params.toString()}`;
}
