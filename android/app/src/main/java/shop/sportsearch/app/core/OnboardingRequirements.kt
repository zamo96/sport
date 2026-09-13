package shop.sportsearch.app.core

object OnboardingRequirements {
    fun hasCity(city: String?, location: GeoPlace?): Boolean =
        SupportedCity.resolve(city) != null ||
            (location != null && location.id.trim().length >= 3 && location.city.isNotBlank())

    fun submissionCity(city: String?, location: GeoPlace?): String =
        city?.trim()?.takeIf { it.isNotEmpty() } ?: location?.city?.trim().orEmpty()

    /** Retain existing account choices and the unsaved portions of onboarding. */
    fun resumeDraft(user: UserProfile, draft: GuestOnboardingDraft): GuestOnboardingDraft {
        val useAccountCity = hasCity(user.city, user.location)
        val useAccountSports = user.preferredSports.isNotEmpty()
        val sameCity = if (user.location != null && draft.location != null) {
            user.location.id == draft.location.id
        } else {
            SupportedCity.resolve(user.city)?.let { it == SupportedCity.resolve(draft.city) } == true
        }
        return draft.copy(
            name = user.name?.takeIf { it.trim().length >= 2 } ?: draft.name,
            age = user.age?.takeIf { it in 18..100 } ?: draft.age,
            genderRaw = user.genderRaw ?: draft.genderRaw,
            city = if (useAccountCity) user.city?.takeIf { it.isNotBlank() } ?: user.location?.city.orEmpty() else draft.city,
            location = if (useAccountCity) user.location else draft.location,
            locationSourceRaw = if (useAccountCity) user.locationSourceRaw else draft.locationSourceRaw,
            district = if (useAccountCity && !sameCity) user.district else user.district ?: draft.district,
            preferredDistricts = if (useAccountCity && !sameCity) user.preferredDistricts
                else user.preferredDistricts.ifEmpty { draft.preferredDistricts },
            preferredSports = if (useAccountSports) user.preferredSports else draft.preferredSports,
            sportLevels = if (useAccountSports) user.sportLevels else draft.sportLevels,
            preferredPlayFormatRaw = user.preferredPlayFormatRaw ?: draft.preferredPlayFormatRaw,
            preferredSurfaceRaw = user.preferredSurfaceRaw ?: draft.preferredSurfaceRaw,
            availableDays = user.availableDays.ifEmpty { draft.availableDays },
            availableTimeRanges = user.availableTimeRanges.ifEmpty { draft.availableTimeRanges },
            availabilityByDay = user.availabilityByDay.ifEmpty { draft.availabilityByDay },
            showOnMap = user.showOnMap && draft.showOnMap,
            onboardingCompleted = false,
        )
    }
}
