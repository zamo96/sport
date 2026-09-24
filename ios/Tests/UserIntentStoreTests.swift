import Foundation

@main
struct UserIntentStoreTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func main() {
        let suite = "SportSearch.UserIntentStoreTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserIntentStore(defaults: defaults)

        expect(store.selection(for: nil) == nil, "A new guest has no required intent")
        expect(store.selection(for: "A") == nil, "An existing account without a choice remains unselected")
        store.setSelection([.activity], for: nil)
        expect(store.selection(for: "A") == nil, "Reading another scope does not implicitly adopt the guest selection")
        expect(UserIntentStore(defaults: defaults).selection(for: nil) == Set([UserIntent.activity]), "Guest selection persists across store recreation")

        store.adoptGuestSelection(for: "A")
        expect(store.selection(for: "A") == Set([UserIntent.activity]), "Explicit successful sign-in can adopt the guest selection")
        expect(store.selection(for: nil) == nil, "Guest handoff is consumed after sign-in")
        expect(store.selection(for: "B") == nil, "The next account never inherits another account's selection")

        store.setSelection([.centers], for: "B")
        store.setSelection([.group], for: nil)
        store.adoptGuestSelection(for: "B")
        expect(store.selection(for: "B") == Set([UserIntent.centers]), "An existing account preference wins over a guest choice")
        expect(store.selection(for: nil) == nil, "A consumed guest selection cannot carry into another login")
        expect(store.selection(for: "A") == Set([UserIntent.activity]), "Another account's login does not overwrite the first account")

        store.setSelection([.partner], for: nil)
        store.clearGuestSelection()
        expect(store.selection(for: nil) == nil, "Logout clears the guest handoff")
        expect(store.selection(for: "A") == Set([UserIntent.activity]) && store.selection(for: "B") == Set([UserIntent.centers]), "Logout preserves separately scoped account preferences")
        expect(UserIntentStore(defaults: defaults).selection(for: "B") == Set([UserIntent.centers]), "Account selection persists across store recreation")

        defaults.set("retired-intent", forKey: "SportSearch.userIntent.account.C")
        expect(store.selection(for: "C") == nil, "An unknown stored value falls back to an optional choice")
        store.setSelection([.group], for: nil)
        store.adoptGuestSelection(for: "C")
        expect(store.selection(for: "C") == Set([UserIntent.group]), "A current guest choice can replace an obsolete account value")

        store.setSelection([.partner], for: "guest")
        expect(store.selection(for: nil) == nil, "An account ID cannot collide with the guest scope")
        expect(store.selection(for: "guest") == Set([UserIntent.partner]), "An account named guest keeps its own preference")
        store.setSelection([.partner, .group, .activity, .centers], for: "multi")
        expect(store.selection(for: "multi") == Set(UserIntent.allCases), "All four goals can be selected together")
        expect(defaults.stringArray(forKey: "SportSearch.userIntent.account.multi") == UserIntent.allCases.map(\.rawValue), "Selections have a deterministic persisted order")
        store.setSelection([], for: "multi")
        expect(UserIntentStore(defaults: defaults).selection(for: "multi") == Set<UserIntent>(), "Deselecting everything persists an explicit empty choice")
        store.setSelection([.partner, .centers], for: nil)
        store.adoptGuestSelection(for: "multi")
        expect(store.selection(for: "multi") == Set<UserIntent>(), "An explicitly empty account choice wins over guest goals")
        expect(store.selection(for: nil) == nil, "A guest handoff is consumed even when the account opted out")

        store.setSelection([], for: nil)
        store.adoptGuestSelection(for: "empty-guest")
        expect(store.selection(for: "empty-guest") == Set<UserIntent>(), "An explicitly empty guest preference transfers to a new account")

        defaults.set("group", forKey: "SportSearch.userIntent.account.legacy")
        expect(store.selection(for: "legacy") == Set([UserIntent.group]), "A previous single-goal selection migrates to a singleton set")
        expect(defaults.stringArray(forKey: "SportSearch.userIntent.account.legacy") == ["group"], "Legacy migration persists the new array format")
        store.setSelection([], for: "legacy")
        expect(store.selection(for: "legacy") == Set<UserIntent>(), "Clearing a migrated choice cannot resurrect its previous scalar")

        defaults.set(["centers", "retired-intent", "partner", "centers"], forKey: "SportSearch.userIntent.account.mixed")
        expect(store.selection(for: "mixed") == Set([UserIntent.partner, .centers]), "Unknown values are ignored and duplicate goals are removed")
        expect(defaults.stringArray(forKey: "SportSearch.userIntent.account.mixed") == ["partner", "centers"], "An old unordered array is normalized deterministically")
        defaults.set(["retired-intent"], forKey: "SportSearch.userIntent.account.retired-array")
        expect(store.selection(for: "retired-array") == Set<UserIntent>(), "An unknown-only array normalizes to a saved empty preference")
        defaults.set(1234, forKey: "SportSearch.userIntent.account.corrupt")
        expect(store.selection(for: "corrupt") == nil, "A malformed stored object is treated as an absent usable choice")
        store.setSelection([.group, .activity], for: nil)
        store.adoptGuestSelection(for: "corrupt")
        expect(store.selection(for: "corrupt") == Set([UserIntent.group, .activity]), "A valid guest choice replaces a malformed account preference")

        expect(!store.hasDismissedFeatureGuide(for: nil), "A new guest can see the feature guide")
        expect(!store.hasDismissedFeatureGuide(for: "guide-A"), "An account without a dismissal can see the guide independently of its goals")
        store.dismissFeatureGuide(for: nil)
        expect(UserIntentStore(defaults: defaults).hasDismissedFeatureGuide(for: nil), "Guest dismissal survives store recreation")
        expect(store.selection(for: nil) == nil, "Dismissing the guide does not implicitly choose or skip goals")
        expect(!store.hasDismissedFeatureGuide(for: "guide-A"), "Guest dismissal does not hide an account's guide")
        store.setSelection([], for: nil)
        expect(store.hasDismissedFeatureGuide(for: nil), "Changing guest goals does not reopen the dismissed guide")
        store.adoptGuestSelection(for: "guide-A")
        expect(store.selection(for: "guide-A") == Set<UserIntent>(), "The explicit empty goal choice still adopts independently of guide state")
        expect(store.hasDismissedFeatureGuide(for: "guide-A"), "A new account adopts the guide the guest already closed on this device")
        expect(!store.hasDismissedFeatureGuide(for: nil), "Sign-in consumes the guest's guide state with its goal handoff")

        store.dismissFeatureGuide(for: "guide-A")
        expect(UserIntentStore(defaults: defaults).hasDismissedFeatureGuide(for: "guide-A"), "Account dismissal is persistent and repeated dismissal is harmless")
        expect(!store.hasDismissedFeatureGuide(for: "guide-B"), "One account's dismissal never hides another account's guide")
        store.setSelection([.partner, .centers], for: "guide-A")
        expect(store.hasDismissedFeatureGuide(for: "guide-A"), "Updating account goals does not reset its guide dismissal")
        store.setSelection([], for: "guide-B")
        expect(!store.hasDismissedFeatureGuide(for: "guide-B"), "Skipping all goals does not dismiss the separate feature guide")
        store.dismissFeatureGuide(for: nil)
        store.setSelection([.group], for: nil)
        store.adoptGuestSelection(for: "guide-A")
        expect(store.hasDismissedFeatureGuide(for: "guide-A") && store.selection(for: "guide-A") == Set([UserIntent.partner, .centers]), "Returning to an existing account preserves both its guide dismissal and chosen goals")

        store.dismissFeatureGuide(for: nil)
        store.clearGuestSelection()
        expect(!store.hasDismissedFeatureGuide(for: nil) && store.hasDismissedFeatureGuide(for: "guide-A"), "Logout clears guest guide state without reopening account guides")
        store.dismissFeatureGuide(for: "guest")
        expect(!store.hasDismissedFeatureGuide(for: nil) && store.hasDismissedFeatureGuide(for: "guest"), "An account named guest cannot collide with the guest guide scope")

        let freshProgress = FeatureGuideProgress()
        expect(store.featureGuideProgress(for: "progress-A") == freshProgress, "New progress requires explicit tutorial acknowledgement and actual feature taps")
        store.setSelection([.centers], for: "progress-A")
        expect(store.featureGuideProgress(for: "progress-A") == freshProgress, "Choosing an onboarding goal does not mark its feature as viewed")
        store.completeFeatureGuideSwipeTutorial(for: "progress-A")
        let acknowledged = store.featureGuideProgress(for: "progress-A")
        expect(acknowledged.hasAcknowledgedSwipeTutorial && acknowledged.openedIntents.isEmpty && !acknowledged.isDismissed,
               "Acknowledging the swipe tutorial advances only that checkpoint")
        store.completeFeatureGuideSwipeTutorial(for: "progress-A")
        expect(UserIntentStore(defaults: defaults).featureGuideProgress(for: "progress-A") == acknowledged,
               "Tutorial acknowledgement is idempotent and persists independently of view recreation")
        store.markFeatureGuideOpened(.activity, for: "progress-A")
        store.markFeatureGuideOpened(.activity, for: "progress-A")
        let oneViewed = store.featureGuideProgress(for: "progress-A")
        expect(oneViewed.openedIntents == [.activity] && !oneViewed.isDismissed,
               "The first CTA checks only its own feature and does not dismiss the whole guide")
        expect(oneViewed.hasAcknowledgedSwipeTutorial && store.selection(for: "progress-A") == [.centers],
               "Feature taps preserve the tutorial checkpoint and the separate user goals")
        expect(UserIntentStore(defaults: defaults).featureGuideProgress(for: "progress-A") == oneViewed,
               "Partial viewed progress survives reopening the store")
        store.markFeatureGuideOpened(.group, for: "progress-A")
        expect(store.featureGuideProgress(for: "progress-A").openedIntents == [.activity, .group],
               "Opening another feature accumulates progress without clearing the earlier checkmark")
        store.dismissFeatureGuide(for: "progress-A")
        let closed = store.featureGuideProgress(for: "progress-A")
        expect(closed.isDismissed && closed.openedIntents == [.activity, .group] && closed.hasAcknowledgedSwipeTutorial,
               "Explicit close preserves the partial checklist and acknowledged tutorial")
        store.markFeatureGuideOpened(.partner, for: "progress-A")
        expect(store.featureGuideProgress(for: "progress-A").openedIntents == [.partner, .group, .activity],
               "A manually reopened guide can record another feature even after automatic presentation was dismissed")
        expect(store.featureGuideProgress(for: "progress-A").isDismissed,
               "Manual interaction does not silently re-enable automatic presentation")

        for intent in UserIntent.allCases { store.markFeatureGuideOpened(intent, for: "all-viewed") }
        let allViewed = store.featureGuideProgress(for: "all-viewed")
        expect(allViewed.openedIntents == Set(UserIntent.allCases) && !allViewed.isDismissed,
               "Four viewed features are distinct from explicitly dismissing the guide")
        expect(!allViewed.hasAcknowledgedSwipeTutorial, "Feature route taps cannot falsely claim that the swipe tutorial was acknowledged")
        store.setSelection([], for: "all-viewed")
        expect(store.featureGuideProgress(for: "all-viewed") == allViewed, "Changing or clearing goals never erases feature familiarity")
        expect(store.featureGuideProgress(for: "progress-B") == freshProgress, "One account's tutorial and viewed features cannot leak into another account")

        store.completeFeatureGuideSwipeTutorial(for: nil)
        store.markFeatureGuideOpened(.partner, for: nil)
        store.dismissFeatureGuide(for: nil)
        store.setSelection([.activity], for: nil)
        store.adoptGuestSelection(for: "new-progress-account")
        expect(store.selection(for: "new-progress-account") == [.activity], "Guest goals still adopt when guide progress is also present")
        expect(store.featureGuideProgress(for: "new-progress-account") == FeatureGuideProgress(hasAcknowledgedSwipeTutorial: true, openedIntents: [.partner], isDismissed: true),
               "Signing in after guest onboarding keeps the acknowledged tutorial, viewed features, and closed guide")
        expect(store.featureGuideProgress(for: nil) == freshProgress, "Successful sign-in consumes every part of guest guide progress")
        expect(store.featureGuideProgress(for: "progress-A").openedIntents == [.partner, .group, .activity],
               "Guest handoff leaves another account's accumulated progress untouched")
        store.markFeatureGuideOpened(.centers, for: nil)
        store.adoptGuestSelection(for: "progress-A")
        expect(store.featureGuideProgress(for: "progress-A").openedIntents == [.partner, .group, .activity],
               "An account's own stored progress wins over the guest's")
        expect(store.featureGuideProgress(for: nil) == freshProgress, "The unused guest progress is still consumed")
        store.adoptGuestSelection(for: "no-guest-progress")
        expect(defaults.object(forKey: "SportSearch.featureGuide.v2.account.no-guest-progress") == nil,
               "Without guest progress, sign-in stores nothing for the account")

        defaults.set(true, forKey: "SportSearch.featureGuide.v1.account.old-dismissed")
        expect(store.featureGuideProgress(for: "old-dismissed") == freshProgress && !store.hasDismissedFeatureGuide(for: "old-dismissed"),
               "An ambiguous v1 dismissal cannot invent tutorial acknowledgement or four viewed features")
        defaults.set(true, forKey: "SportSearch.featureGuide.v1.guest")
        store.completeFeatureGuideSwipeTutorial(for: nil)
        store.markFeatureGuideOpened(.centers, for: nil)
        store.clearGuestSelection()
        expect(store.featureGuideProgress(for: nil) == freshProgress && defaults.object(forKey: "SportSearch.featureGuide.v1.guest") == nil,
               "Logout clears both the old guest dismissal and new guest progress")
        expect(store.featureGuideProgress(for: "progress-A").hasAcknowledgedSwipeTutorial,
               "Guest cleanup never resets an account's acknowledged tutorial")

        let mixedKey = "SportSearch.featureGuide.v2.account.mixed-progress"
        defaults.set(["swipeTutorialAcknowledged": true, "openedIntents": ["centers", "retired", "partner", "centers"], "dismissed": false], forKey: mixedKey)
        let normalized = store.featureGuideProgress(for: "mixed-progress")
        expect(normalized.hasAcknowledgedSwipeTutorial && normalized.openedIntents == [.partner, .centers] && !normalized.isDismissed,
               "Unknown and duplicate stored features do not fabricate additional checkmarks")
        expect(defaults.dictionary(forKey: mixedKey)?["openedIntents"] as? [String] == ["partner", "centers"],
               "Stored feature progress normalizes to stable canonical ordering")
        defaults.set(["swipeTutorialAcknowledged": "wrong", "openedIntents": ["group"], "dismissed": "wrong"], forKey: "SportSearch.featureGuide.v2.account.malformed-flags")
        let malformedFlags = store.featureGuideProgress(for: "malformed-flags")
        expect(!malformedFlags.hasAcknowledgedSwipeTutorial && !malformedFlags.isDismissed && malformedFlags.openedIntents == [.group],
               "Malformed boolean flags default safely while retaining valid individual feature progress")
        defaults.set(1234, forKey: "SportSearch.featureGuide.v2.account.malformed-object")
        expect(store.featureGuideProgress(for: "malformed-object") == freshProgress, "Malformed progress objects fall back to a fresh guide")
        defaults.set(["dismissed": true], forKey: "SportSearch.featureGuide.v2.account.partial-object")
        let partialObject = store.featureGuideProgress(for: "partial-object")
        expect(partialObject.isDismissed && !partialObject.hasAcknowledgedSwipeTutorial && partialObject.openedIntents.isEmpty,
               "Missing progress fields cannot imply that features were viewed")
        store.markFeatureGuideOpened(.group, for: "guest")
        expect(store.featureGuideProgress(for: nil) == freshProgress && store.featureGuideProgress(for: "guest").openedIntents == [.group],
               "An account literally named guest has an isolated feature checklist")
        print("User intent store: \(checks) checks passed")
    }
}
