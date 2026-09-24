import Foundation

@main
@MainActor
struct PersonalVisitContinuationTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func main() {
        let court = Court(id: "selected-club-in-another-city")
        let model = PersonalVisitContinuationHarness()
        let continuationID = model.deferPersonalVisit(court: court, sport: .football)
        expect(model.pendingPersonalVisit?.id == continuationID, "The pending visit keeps a stable identity for delayed presentation")
        expect(!model.canResumePendingPersonalVisit && model.consumePendingPersonalVisit() == nil, "A guest cannot consume a protected visit action")

        model.presentedAuthStep = "email"
        model.authenticationSheetDidDismiss()
        expect(model.pendingPersonalVisit != nil, "Replacing email with another auth step does not cancel the guest context")
        model.presentedAuthStep = "code"
        model.currentUser = TestUser(id: "new-account", isOnboardingComplete: false)
        model.isBusy = true
        expect(model.consumePendingPersonalVisit() == nil, "An account adopted during sign-in does not resume before authentication settles")

        model.presentedAuthStep = nil
        model.authenticationSheetDidDismiss()
        model.isBusy = false
        expect(model.consumePendingPersonalVisit() == nil, "Incomplete onboarding remains a gate even after the auth sheet closes")
        model.currentUser?.isOnboardingComplete = true
        expect(model.canResumePendingPersonalVisit, "A finished account becomes eligible to resume")
        let resumed = model.consumePendingPersonalVisit()
        expect(resumed?.court == court && resumed?.sport == .football, "Resuming preserves the exact court and sport without a city-list lookup")
        expect(model.consumePendingPersonalVisit() == nil, "A successful continuation is consumed exactly once")

        let canceled = PersonalVisitContinuationHarness()
        _ = canceled.deferPersonalVisit(court: court, sport: nil)
        canceled.presentedAuthStep = "email"
        canceled.dismissPresentedAuth()
        expect(canceled.pendingPersonalVisit == nil, "An explicit guest cancel clears the deferred visit")
        canceled.currentUser = TestUser(id: "other-account", isOnboardingComplete: true)
        canceled.authenticationSheetDidDismiss()
        expect(canceled.consumePendingPersonalVisit() == nil, "A later login cannot revive a canceled court")

        let swipedAway = PersonalVisitContinuationHarness()
        _ = swipedAway.deferPersonalVisit(court: court, sport: nil)
        swipedAway.isBusy = true
        swipedAway.presentedAuthStep = nil
        swipedAway.authenticationSheetDidDismiss()
        expect(swipedAway.pendingPersonalVisit == nil, "Interactive auth dismissal cancels even an in-flight guest sign-in")

        let dismissing = PersonalVisitContinuationHarness()
        _ = dismissing.deferPersonalVisit(court: court, sport: .football)
        dismissing.currentUser = TestUser(id: "A", isOnboardingComplete: true)
        expect(dismissing.consumePendingPersonalVisit() == nil, "A second sheet waits for actual auth dismissal")
        dismissing.authenticationSheetDidDismiss()
        dismissing.isBusy = true
        expect(dismissing.consumePendingPersonalVisit() == nil, "A busy profile save delays continuation without losing the court")
        dismissing.isBusy = false
        expect(dismissing.consumePendingPersonalVisit()?.court == court, "Finishing the save resumes the preserved action")

        print("Personal visit continuation: \(checks) checks passed")
    }
}
