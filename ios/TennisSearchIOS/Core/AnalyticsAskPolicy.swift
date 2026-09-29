import Foundation

/// Where the quiet "help us improve the app" card stands for one account. It is offered from the
/// third launch, on a calm screen, for a few days; after "Not now" — or after it was simply left
/// alone — it comes back once about two weeks later, and never again.
struct AnalyticsAskState: Codable, Equatable {
    var launchCount = 0
    var firstLaunchAt: Date?
    /// Finished asking rounds: declined, or shown for its whole life and left alone.
    var rounds = 0
    var roundStartedAt: Date?
    var lastRoundEndedAt: Date?
    var isResolved = false
}

enum AnalyticsAskPolicy {
    static let minimumLaunches = 3
    static let minimumAge: TimeInterval = 24 * 60 * 60
    /// How long one round keeps the card on screen if nobody answers.
    static let roundLifetime: TimeInterval = 3 * 24 * 60 * 60
    static let repeatAfter: TimeInterval = 14 * 24 * 60 * 60
    static let maximumRounds = 2

    static func recordLaunch(_ state: inout AnalyticsAskState, now: Date) {
        state.launchCount += 1
        if state.firstLaunchAt == nil { state.firstLaunchAt = now }
    }

    /// A round nobody answered ends by itself; call before reading the state.
    static func settle(_ state: inout AnalyticsAskState, now: Date) {
        guard let start = state.roundStartedAt, now.timeIntervalSince(start) >= roundLifetime else { return }
        finishRound(&state, at: start.addingTimeInterval(roundLifetime))
    }

    static func shouldShow(_ state: AnalyticsAskState, analyticsGranted: Bool, now: Date) -> Bool {
        var current = state
        settle(&current, now: now)
        if analyticsGranted || current.isResolved { return false }
        if current.roundStartedAt != nil { return true }
        guard current.launchCount >= minimumLaunches,
              let first = current.firstLaunchAt,
              now.timeIntervalSince(first) >= minimumAge else { return false }
        if current.rounds == 0 { return true }
        guard current.rounds < maximumRounds, let ended = current.lastRoundEndedAt else { return false }
        return now.timeIntervalSince(ended) >= repeatAfter
    }

    /// The card appeared: its round starts the first time.
    static func recordShown(_ state: inout AnalyticsAskState, now: Date) {
        settle(&state, now: now)
        if state.roundStartedAt == nil { state.roundStartedAt = now }
    }

    static func recordDeclined(_ state: inout AnalyticsAskState, now: Date) {
        finishRound(&state, at: now)
    }

    static func recordGranted(_ state: inout AnalyticsAskState) {
        state.isResolved = true
        state.roundStartedAt = nil
    }

    private static func finishRound(_ state: inout AnalyticsAskState, at date: Date) {
        state.rounds += 1
        state.roundStartedAt = nil
        state.lastRoundEndedAt = date
        if state.rounds >= maximumRounds { state.isResolved = true }
    }
}

/// Keeps each account's state on the phone. A decline is not sent anywhere: only an answer that
/// switches analytics on is a consent, and that is logged by the server.
enum AnalyticsAskStore {
    private static func key(_ userID: String) -> String { "analyticsAsk.v1." + userID }

    static func load(userID: String, defaults: UserDefaults = .standard) -> AnalyticsAskState {
        guard let data = defaults.data(forKey: key(userID)),
              let state = try? JSONDecoder().decode(AnalyticsAskState.self, from: data) else { return AnalyticsAskState() }
        return state
    }

    static func update(userID: String, defaults: UserDefaults = .standard, _ change: (inout AnalyticsAskState) -> Void) {
        var state = load(userID: userID, defaults: defaults)
        change(&state)
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key(userID)) }
    }
}
