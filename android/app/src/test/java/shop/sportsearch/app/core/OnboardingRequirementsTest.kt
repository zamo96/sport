package shop.sportsearch.app.core

import org.junit.Assert.*
import org.junit.Test

class OnboardingRequirementsTest {
    private val draft = GuestOnboardingDraft(
        name = "Анна",
        age = 28,
        city = "Москва",
        preferredSports = listOf(Sport.TENNIS),
        onboardingCompleted = true,
    )

    @Test fun profileStepDoesNotRequireTheCityFromTheNextStep() {
        val withoutCity = draft.copy(city = "")
        assertTrue(withoutCity.hasProfileBasics)
        assertFalse(withoutCity.hasRequiredOnboardingFields)
        assertFalse(withoutCity.hasCompletedOnboarding)
    }

    @Test fun completedFlagCannotAdmitMissingOrInvalidRequiredFields() {
        listOf(
            draft.copy(city = "   "),
            draft.copy(city = "Unknown city"),
            draft.copy(preferredSports = emptyList()),
            draft.copy(name = " "),
            draft.copy(age = 17),
            draft.copy(onboardingCompleted = false),
            draft.copy(city = "", location = GeoPlace(id = "")),
            draft.copy(city = "", location = GeoPlace(id = " ab ", city = "Paris")),
        ).forEach { assertFalse(it.toString(), it.hasCompletedOnboarding) }
    }

    @Test fun scheduleAndDistrictsRemainOptional() {
        assertTrue(draft.hasCompletedOnboarding)
        assertTrue(draft.copy(city = "", location = GeoPlace(id = "place-1", city = "Paris")).hasCompletedOnboarding)
    }

    @Test fun selectedLocationSuppliesRequiredCityInProfileSubmission() {
        val location = GeoPlace(id = "place-1", city = " Paris ")
        assertEquals("Paris", OnboardingRequirements.submissionCity("", location))
        assertEquals("Paris", OnboardingRequirements.submissionCity(" \n ", location))
        assertEquals("Paris", OnboardingRequirements.submissionCity(null, location))
        assertEquals("Москва", OnboardingRequirements.submissionCity(" Москва ", null))
        assertEquals("", OnboardingRequirements.submissionCity(" ", null))
    }

    @Test fun authenticatedProfilesAlsoRequireSportCityAndCompletion() {
        val user = UserProfile(id = "user", name = "Анна", age = 28, city = "Москва", preferredSports = draft.preferredSports, onboardingCompleted = true)
        assertTrue(user.hasCompletedOnboarding)
        assertFalse(user.copy(city = null).hasCompletedOnboarding)
        assertFalse(user.copy(preferredSports = emptyList()).hasCompletedOnboarding)
        assertFalse(user.copy(onboardingCompleted = false).hasCompletedOnboarding)
        assertFalse(user.copy(name = " ").hasCompletedOnboarding)
        assertFalse(user.copy(age = 17).hasCompletedOnboarding)
    }

    @Test fun resumingIncompleteAccountRetainsDraftSelectionsAndOptionalSchedule() {
        val savedDraft = draft.copy(preferredDistricts = listOf("moscow_center"), availableDays = listOf("monday"))
        val resumed = OnboardingRequirements.resumeDraft(UserProfile(id = "user", name = "Мария"), savedDraft)
        assertEquals("Мария", resumed.name)
        assertEquals(savedDraft.city, resumed.city)
        assertEquals(savedDraft.preferredSports, resumed.preferredSports)
        assertEquals(savedDraft.preferredDistricts, resumed.preferredDistricts)
        assertEquals(savedDraft.availableDays, resumed.availableDays)
        assertTrue(resumed.hasRequiredOnboardingFields)
        assertFalse(resumed.hasCompletedOnboarding)
    }

    @Test fun accountCityAndSportsOverrideUnrelatedGuestChoices() {
        val user = UserProfile(id = "user", city = "Санкт-Петербург", preferredSports = listOf(Sport.PADEL))
        val resumed = OnboardingRequirements.resumeDraft(user, draft.copy(preferredDistricts = listOf("moscow_center")))
        assertEquals(user.city, resumed.city)
        assertEquals(user.preferredSports, resumed.preferredSports)
        assertTrue(resumed.preferredDistricts.isEmpty())
        assertFalse(resumed.hasCompletedOnboarding)
    }

    @Test fun resumingInSameCityPreservesUnsavedDistricts() {
        val savedDraft = draft.copy(preferredDistricts = listOf("moscow_center"))
        val resumed = OnboardingRequirements.resumeDraft(UserProfile(id = "user", city = "Москва"), savedDraft)
        assertEquals(savedDraft.preferredDistricts, resumed.preferredDistricts)
    }
}
