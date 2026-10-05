import { apiFetch } from "@/lib/client-api";
import {
  guestDraftCanCompleteOnboarding,
  mapVisibilityForGuestPromotion,
  type GuestOnboardingDraft
} from "@/lib/guest-draft";
import { getPrimarySportLevel } from "@/lib/sport-levels";

export type SignedInUser = { onboardingCompleted: boolean; showOnMap?: boolean };

/**
 * После любого входа (email, SMS, VK ID) переносит заполненный гостем черновик
 * в профиль нового аккаунта. Возвращает, завершена ли анкета.
 */
export async function promoteGuestDraftAfterSignIn(user: SignedInUser, draft: GuestOnboardingDraft) {
  if (user.onboardingCompleted || !guestDraftCanCompleteOnboarding(draft)) {
    return user.onboardingCompleted;
  }
  await apiFetch("/me", {
    method: "PATCH",
    body: JSON.stringify({
      name: draft.name.trim(),
      age: draft.age,
      gender: draft.gender ?? null,
      city: draft.city,
      locationPlaceId: draft.locationPlaceId ?? undefined,
      district: draft.preferredDistricts[0] ?? draft.district ?? null,
      preferredDistricts: draft.preferredDistricts,
      tennisLevel: getPrimarySportLevel(draft.preferredSports, draft.sportLevels, draft.sportLevels[draft.preferredSports[0]] ?? 5),
      preferredSports: draft.preferredSports,
      sportLevels: draft.sportLevels,
      preferredPlayFormat: draft.preferredPlayFormat,
      preferredSurface: draft.preferredSurface,
      bio: "",
      avatarUrl: null,
      availableDays: draft.availableDays,
      availableTimeRanges: draft.availableTimeRanges,
      availabilityByDay: draft.availabilityByDay,
      showOnMap: mapVisibilityForGuestPromotion(user.showOnMap, draft.showOnMap),
      isLookingForGame: draft.isLookingForGame,
      notificationGames: true,
      notificationMatches: true,
      notificationMessages: true,
      notificationSound: true
    })
  });
  return true;
}
