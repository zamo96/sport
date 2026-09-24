import Foundation

/// Familiarity with app features, separate from a user's goals or actual sports activity.
struct FeatureGuideProgress: Equatable {
    var hasAcknowledgedSwipeTutorial = false
    var openedIntents: Set<UserIntent> = []
    var isDismissed = false
}

/// A local presentation preference, isolated from profile and authentication data.
struct UserIntentStore {
    private let defaults: UserDefaults
    private let keyPrefix = "SportSearch.userIntent."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// nil is an absent preference; an empty set is an intentional saved choice.
    func selection(for accountID: String?) -> Set<UserIntent>? {
        let storageKey = key(for: accountID)
        if let rawValues = defaults.array(forKey: storageKey) as? [String] {
            let intents = Set(rawValues.compactMap(UserIntent.init(rawValue:)))
            let normalized = serialized(intents)
            if rawValues != normalized {
                defaults.set(normalized, forKey: storageKey)
            }
            return intents
        }
        if let rawValue = defaults.string(forKey: storageKey),
           let legacyIntent = UserIntent(rawValue: rawValue) {
            let intents: Set<UserIntent> = [legacyIntent]
            setSelection(intents, for: accountID)
            return intents
        }
        return nil
    }

    func setSelection(_ intents: Set<UserIntent>, for accountID: String?) {
        defaults.set(serialized(intents), forKey: key(for: accountID))
    }

    /// Only an explicit successful sign-in transfers the current guest's choice and guide progress.
    /// Existing account state takes precedence; the guest handoff is consumed.
    func adoptGuestSelection(for accountID: String) {
        if selection(for: accountID) == nil, let guestSelection = selection(for: nil) {
            setSelection(guestSelection, for: accountID)
        }
        // Signing in right after guest onboarding otherwise replayed the guide and the swipe tutorial.
        if defaults.object(forKey: featureGuideProgressKey(for: accountID)) == nil,
           defaults.object(forKey: featureGuideProgressKey(for: nil)) != nil {
            setFeatureGuideProgress(featureGuideProgress(for: nil), for: accountID)
        }
        clearGuestSelection()
    }

    func clearGuestSelection() {
        defaults.removeObject(forKey: key(for: nil))
        defaults.removeObject(forKey: guideKey(for: nil))
        defaults.removeObject(forKey: featureGuideProgressKey(for: nil))
    }

    func hasDismissedFeatureGuide(for accountID: String?) -> Bool {
        featureGuideProgress(for: accountID).isDismissed
    }

    func dismissFeatureGuide(for accountID: String?) {
        var progress = featureGuideProgress(for: accountID)
        progress.isDismissed = true
        setFeatureGuideProgress(progress, for: accountID)
    }

    func featureGuideProgress(for accountID: String?) -> FeatureGuideProgress {
        // v1 dismissal also happened after a single CTA. It cannot prove that the
        // tutorial was acknowledged, any particular feature was opened, or all four were seen.
        guard let stored = defaults.dictionary(forKey: featureGuideProgressKey(for: accountID)) else {
            return FeatureGuideProgress()
        }
        let rawIntents = stored["openedIntents"] as? [String] ?? []
        let progress = FeatureGuideProgress(
            hasAcknowledgedSwipeTutorial: stored["swipeTutorialAcknowledged"] as? Bool ?? false,
            openedIntents: Set(rawIntents.compactMap(UserIntent.init(rawValue:))),
            isDismissed: stored["dismissed"] as? Bool ?? false
        )
        if rawIntents != serialized(progress.openedIntents) {
            setFeatureGuideProgress(progress, for: accountID)
        }
        return progress
    }

    func completeFeatureGuideSwipeTutorial(for accountID: String?) {
        var progress = featureGuideProgress(for: accountID)
        progress.hasAcknowledgedSwipeTutorial = true
        setFeatureGuideProgress(progress, for: accountID)
    }

    func markFeatureGuideOpened(_ intent: UserIntent, for accountID: String?) {
        var progress = featureGuideProgress(for: accountID)
        progress.openedIntents.insert(intent)
        setFeatureGuideProgress(progress, for: accountID)
    }

    private func setFeatureGuideProgress(_ progress: FeatureGuideProgress, for accountID: String?) {
        defaults.set([
            "swipeTutorialAcknowledged": progress.hasAcknowledgedSwipeTutorial,
            "openedIntents": serialized(progress.openedIntents),
            "dismissed": progress.isDismissed
        ], forKey: featureGuideProgressKey(for: accountID))
    }

    private func featureGuideProgressKey(for accountID: String?) -> String {
        "SportSearch.featureGuide.v2." + (accountID.map { "account." + $0 } ?? "guest")
    }

    private func guideKey(for accountID: String?) -> String {
        "SportSearch.featureGuide.v1." + (accountID.map { "account." + $0 } ?? "guest")
    }

    private func key(for accountID: String?) -> String {
        guard let accountID else { return keyPrefix + "guest" }
        return keyPrefix + "account." + accountID
    }

    private func serialized(_ intents: Set<UserIntent>) -> [String] {
        UserIntent.allCases.filter { intents.contains($0) }.map(\.rawValue)
    }
}
