import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createDefaultGuestOnboardingDraft, loadGuestOnboardingDraft,
  mapVisibilityForGuestPromotion, saveGuestOnboardingDraft
} from "@/lib/guest-draft";

afterEach(() => vi.unstubAllGlobals());

describe("map visibility during guest onboarding", () => {
  it("starts enabled and preserves an explicit disabled choice through draft storage", () => {
    let value: string | null = null;
    vi.stubGlobal("window", { localStorage: {
      setItem: (_key: string, next: string) => { value = next; },
      getItem: () => value
    } });
    const draft = createDefaultGuestOnboardingDraft();
    expect(draft.showOnMap).toBe(true);
    saveGuestOnboardingDraft({ ...draft, showOnMap: false });
    expect(loadGuestOnboardingDraft()?.showOnMap).toBe(false);
    value = JSON.stringify({ name: "Player", preferredDistricts: [] });
    expect(loadGuestOnboardingDraft()?.showOnMap).toBe(true);
  });

  it.each([
    [true, true, true], [true, false, false], [false, true, false],
    [false, false, false], [undefined, true, false]
  ])("promotes saved=%s, draft=%s to %s without resetting returning opt-outs", (saved, draft, expected) => {
    expect(mapVisibilityForGuestPromotion(saved, draft!)).toBe(expected);
  });
});
