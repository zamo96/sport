import Foundation

@main
@MainActor
struct RequiredOnboardingTests {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }

    static func validDraft() -> GuestOnboardingDraft {
        var draft = GuestOnboardingDraft.default
        draft.name = "Alex"
        draft.age = 28
        draft.preferredSports = [.tennis]
        draft.city = "Санкт-Петербург"
        return draft
    }

    static func main() async throws {
        var draft = GuestOnboardingDraft.default
        expect(!draft.hasProfileBasics && !draft.hasSelectedCity, "New profiles have no implicit sport or city")
        draft.name = "Alex"
        draft.age = 28
        draft.preferredSports = [.tennis]
        expect(draft.hasProfileBasics, "The profile step can continue before city selection")
        expect(!draft.hasRequiredOnboardingFields, "The entire onboarding cannot finish before city selection")
        draft.onboardingCompleted = true
        expect(!draft.isOnboardingComplete, "A persisted completion flag cannot bypass missing city")
        draft.city = " \n "
        expect(!draft.isOnboardingComplete, "Whitespace is not a city")
        draft.city = "Москва"
        expect(draft.isOnboardingComplete, "Sport and selected city complete a valid profile without a schedule")
        draft.preferredSports = []
        expect(!draft.isOnboardingComplete, "A city cannot compensate for a missing sport")
        for age in [0, 17, 101] {
            draft = validDraft()
            draft.age = age
            expect(!draft.hasProfileBasics, "The existing age limits remain enforced")
        }
        draft = validDraft()
        draft.name = " \n "
        expect(!draft.hasRequiredOnboardingFields, "Whitespace name remains invalid")

        let globalPlace = GeoPlace(id: "geonames:2988507", provider: "geonames", countryCode: "FR", countryName: "France", region: nil, city: "Paris", latitude: 48.85, longitude: 2.35, coverage: .unavailable)
        draft = validDraft()
        draft.city = ""
        draft.location = globalPlace
        expect(draft.hasRequiredOnboardingFields, "A resolved global city works without legacy city text or local coverage")
        expect(!draft.isOnboardingComplete, "Required fields alone do not skip the explicit completion step")
        draft.onboardingCompleted = true
        expect(draft.isOnboardingComplete, "A completed global draft is eligible for promotion")
        draft.location = GeoPlace(id: " ", provider: "geonames", countryCode: "FR", countryName: "France", region: nil, city: "Paris", latitude: 48.85, longitude: 2.35, coverage: .unavailable)
        expect(!draft.hasSelectedCity, "A malformed place identifier cannot unlock onboarding")
        draft.location = GeoPlace(id: "geonames:2988507", provider: "geonames", countryCode: "FR", countryName: "France", region: nil, city: " \n ", latitude: 48.85, longitude: 2.35, coverage: .unavailable)
        expect(!draft.hasSelectedCity, "A place without its actual city is incomplete")

        let model = OnboardingModelHarness()
        draft = validDraft()
        draft.city = ""
        draft.onboardingCompleted = true
        let invalidCompletion = await model.completeGuestOnboarding(draft)
        expect(!invalidCompletion && model.draftWrites == 0 && model.profileWrites == 0, "Completion rejects missing city before any persistence")
        model.guestDraft = draft
        expect(!model.isGuestModeAvailable, "An old flagged guest draft without city cannot open the app")
        draft = validDraft()
        draft.preferredSports = []
        let invalidSportCompletion = await model.completeGuestOnboarding(draft)
        expect(!invalidSportCompletion && model.draftWrites == 0, "Completion rejects missing sport before persistence")
        let guestCompletion = await model.completeGuestOnboarding(validDraft())
        expect(guestCompletion && model.guestDraft.onboardingCompleted && model.isGuestModeAvailable, "Valid guest completion sets the flag and opens browsing")

        var saved = UserProfile(id: "existing", name: "Saved Player", age: 31, city: "Москва", preferredSports: [.padel], showOnMap: false, onboardingCompleted: false)
        saved.availableDays = ["monday"]
        saved.availableTimeRanges = ["evening"]
        saved.availabilityByDay = ["monday": ["evening"]]
        let restored = OnboardingModelHarness()
        restored.restore(saved)
        expect(restored.isAuthenticated && !restored.isOnboardingComplete && !restored.isGuestModeAvailable, "Restoring an incomplete account does not unlock the main app")
        expect(restored.guestDraft.name == saved.name && restored.guestDraft.age == 31 && restored.guestDraft.preferredSports == [.padel] && restored.guestDraft.city == "Москва", "Restoring incomplete onboarding retains saved fields")
        expect(!restored.guestDraft.showOnMap, "Restoring onboarding retains the saved map opt-out")
        expect(restored.guestDraft.availabilityByDay == saved.availabilityByDay, "Restoring an incomplete profile retains its existing optional schedule")
        let restoredCompletion = await restored.completeGuestOnboarding(restored.guestDraft)
        expect(restoredCompletion && restored.isOnboardingComplete, "An incomplete signed-in profile can finish onboarding")
        expect(!restored.currentUser!.showOnMap, "Completion cannot re-enable a saved map opt-out")

        saved.onboardingCompleted = true
        saved.preferredSports = []
        let repair = OnboardingModelHarness()
        repair.restore(saved)
        expect(!repair.isOnboardingComplete, "A historical true flag cannot hide missing sport")
        draft = validDraft()
        draft.showOnMap = false
        let repairCompletion = await repair.completeGuestOnboarding(draft)
        expect(repairCompletion && repair.profileWrites == 1 && repair.isOnboardingComplete, "A historically invalid completed account can be repaired")

        let repairPrivacy = OnboardingModelHarness()
        saved.showOnMap = true
        repairPrivacy.restore(saved)
        draft = validDraft()
        draft.showOnMap = false
        let privacyCompletion = await repairPrivacy.completeGuestOnboarding(draft)
        expect(privacyCompletion && repairPrivacy.currentUser?.showOnMap == false, "Repairing historical onboarding honors a new map opt-out")
        saved.showOnMap = false

        let preserved = OnboardingModelHarness()
        draft = validDraft()
        draft.name = "Draft Player"
        draft.city = ""
        draft.showOnMap = false
        preserved.guestDraft = draft
        saved.onboardingCompleted = false
        preserved.restore(saved)
        expect(preserved.guestDraft.name == "Draft Player" && preserved.guestDraft.preferredSports == [.tennis], "Login keeps the user's partially entered draft")
        expect(preserved.guestDraft.city == "Москва" && !preserved.guestDraft.onboardingCompleted, "Login fills the missing city without silently completing the draft")

        let global = OnboardingModelHarness()
        saved.city = nil
        saved.location = globalPlace
        saved.preferredSports = [.tennis]
        saved.onboardingCompleted = true
        global.restore(saved)
        expect(global.isOnboardingComplete, "A completed global account needs no legacy city string")
        let guestGlobal = OnboardingModelHarness()
        saved.onboardingCompleted = false
        guestGlobal.restore(saved)
        expect(guestGlobal.guestDraft.city == "Paris" && guestGlobal.guestDraft.hasSelectedCity, "A restored global place provides its actual city")
        let globalCompletion = await guestGlobal.completeGuestOnboarding(guestGlobal.guestDraft)
        expect(globalCompletion && guestGlobal.currentUser?.city == "Paris", "A global profile persists the resolved city")

        let retry = OnboardingModelHarness()
        retry.restore(UserProfile(id: "new"))
        retry.saveSucceeds = false
        let failedSave = await retry.completeGuestOnboarding(validDraft())
        expect(!failedSave && !retry.isOnboardingComplete && retry.guestDraft.hasRequiredOnboardingFields, "A failed server save keeps the draft for retry and leaves the main app closed")

        let persisted = try JSONDecoder().decode(GuestOnboardingDraft.self, from: Data("{\"name\":\"Alex\",\"age\":28,\"city\":\"Москва\",\"onboardingCompleted\":true}".utf8))
        expect(!persisted.isOnboardingComplete && persisted.preferredSports.isEmpty, "Old persisted drafts cannot acquire implicit tennis during decoding")
        print("Required onboarding: \(assertions) assertions passed")
    }
}
