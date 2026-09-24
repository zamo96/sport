import SwiftUI

extension AppModel {
    var selectedUserIntents: Set<UserIntent> {
        UserIntentStore().selection(for: currentUser?.id) ?? []
    }

    var hasChosenUserIntents: Bool {
        UserIntentStore().selection(for: currentUser?.id) != nil
    }

    var shouldShowFeatureGuide: Bool {
        !featureGuideProgress.isDismissed
    }

    var featureGuideProgress: FeatureGuideProgress {
        UserIntentStore().featureGuideProgress(for: currentUser?.id)
    }

    func completeFeatureGuideSwipeTutorial() {
        objectWillChange.send()
        UserIntentStore().completeFeatureGuideSwipeTutorial(for: currentUser?.id)
    }

    func markFeatureGuideOpened(_ intent: UserIntent) {
        objectWillChange.send()
        UserIntentStore().markFeatureGuideOpened(intent, for: currentUser?.id)
    }

    /// The guide opens by itself only once. However it closes, the Players deck explains swiping next.
    func dismissFeatureGuide() {
        objectWillChange.send()
        UserIntentStore().dismissFeatureGuide(for: currentUser?.id)
        if !featureGuideProgress.hasAcknowledgedSwipeTutorial {
            queueDiscoverSimilarPlayersHint()
        }
    }

    func setUserIntents(_ intents: Set<UserIntent>) {
        objectWillChange.send()
        UserIntentStore().setSelection(intents, for: currentUser?.id)
    }

    func toggleUserIntent(_ intent: UserIntent) {
        var intents = selectedUserIntents
        if intents.contains(intent) {
            intents.remove(intent)
        } else {
            intents.insert(intent)
        }
        setUserIntents(intents)
    }

    func adoptGuestUserIntentIfNeeded() {
        guard let accountID = currentUser?.id else { return }
        objectWillChange.send()
        UserIntentStore().adoptGuestSelection(for: accountID)
    }

    func clearGuestUserIntent() {
        UserIntentStore().clearGuestSelection()
    }
}
