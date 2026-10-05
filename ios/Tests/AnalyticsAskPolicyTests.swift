import Foundation

@main
struct AnalyticsAskPolicyTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static let day: TimeInterval = 24 * 60 * 60

    static func main() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        func at(_ days: Double) -> Date { start.addingTimeInterval(days * day) }
        func show(_ state: AnalyticsAskState, _ when: Date, granted: Bool = false) -> Bool {
            AnalyticsAskPolicy.shouldShow(state, analyticsGranted: granted, now: when)
        }

        // Not on the first launches, and not on the first day.
        var state = AnalyticsAskState()
        expect(!show(state, at(0)), "A brand new account is not asked")
        AnalyticsAskPolicy.recordLaunch(&state, now: at(0))
        AnalyticsAskPolicy.recordLaunch(&state, now: at(0.2))
        AnalyticsAskPolicy.recordLaunch(&state, now: at(0.4))
        expect(state.launchCount == 3 && state.firstLaunchAt == at(0), "Launches are counted from the first one")
        expect(!show(state, at(0.5)), "Three launches on the first day are still too early")
        expect(show(state, at(1.01)), "Three launches and a day later, the card is due")
        var twoLaunches = AnalyticsAskState()
        AnalyticsAskPolicy.recordLaunch(&twoLaunches, now: at(0))
        AnalyticsAskPolicy.recordLaunch(&twoLaunches, now: at(0.1))
        expect(!show(twoLaunches, at(5)), "Two launches are not enough however long ago the first was")
        expect(!show(state, at(2), granted: true), "Someone who already agreed is never asked")

        // A round that is answered "Not now" comes back once, after two weeks.
        AnalyticsAskPolicy.recordShown(&state, now: at(2))
        expect(show(state, at(3)), "The card stays while its round is open")
        AnalyticsAskPolicy.recordDeclined(&state, now: at(3))
        expect(!show(state, at(3.5)), "Right after \"Not now\" the card is gone")
        expect(!show(state, at(16.9)), "Not before two weeks have passed")
        expect(show(state, at(17.01)), "Two weeks after the first decline it comes back")
        AnalyticsAskPolicy.recordShown(&state, now: at(17.5))
        AnalyticsAskPolicy.recordDeclined(&state, now: at(18))
        expect(state.isResolved && state.rounds == 2, "A second decline ends the asking for good")
        expect(!show(state, at(400)), "It is never offered a third time")

        // A card nobody touched ends by itself after its lifetime and counts as a round.
        var ignored = AnalyticsAskState()
        for step in 0 ..< 3 { AnalyticsAskPolicy.recordLaunch(&ignored, now: at(Double(step))) }
        AnalyticsAskPolicy.recordShown(&ignored, now: at(3))
        expect(show(ignored, at(5.9)), "An unanswered card is still there on the third day")
        expect(!show(ignored, at(6.01)), "After its three days it goes away by itself")
        expect(!show(ignored, at(19)), "Ignoring counts as a round: no repeat before two weeks after it ended")
        expect(show(ignored, at(20.1)), "The one repeat follows two weeks after the round ended")
        var settled = ignored
        AnalyticsAskPolicy.settle(&settled, now: at(10))
        expect(settled.rounds == 1 && settled.roundStartedAt == nil, "Settling closes an expired round")

        // Agreeing resolves it for good.
        var agreed = AnalyticsAskState()
        for step in 0 ..< 3 { AnalyticsAskPolicy.recordLaunch(&agreed, now: at(Double(step))) }
        AnalyticsAskPolicy.recordShown(&agreed, now: at(3))
        AnalyticsAskPolicy.recordGranted(&agreed)
        expect(!show(agreed, at(4)) && !show(agreed, at(100)), "After agreeing the card never returns, even if it is switched off later")

        // The store keeps each account apart.
        let suite = UserDefaults(suiteName: "analytics-ask-tests-\(UUID().uuidString)")!
        AnalyticsAskStore.update(userID: "A", defaults: suite) { AnalyticsAskPolicy.recordLaunch(&$0, now: at(0)) }
        AnalyticsAskStore.update(userID: "A", defaults: suite) { AnalyticsAskPolicy.recordLaunch(&$0, now: at(1)) }
        AnalyticsAskStore.update(userID: "B", defaults: suite) { AnalyticsAskPolicy.recordLaunch(&$0, now: at(1)) }
        expect(AnalyticsAskStore.load(userID: "A", defaults: suite).launchCount == 2, "Account A keeps its own launches")
        expect(AnalyticsAskStore.load(userID: "B", defaults: suite).launchCount == 1, "Account B is not affected by A")
        expect(AnalyticsAskStore.load(userID: "C", defaults: suite) == AnalyticsAskState(), "An unknown account starts empty")

        print("Analytics ask policy tests: \(checks) checks passed")
    }
}
