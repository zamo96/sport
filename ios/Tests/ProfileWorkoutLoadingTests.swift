import Foundation

@main
@MainActor
struct ProfileWorkoutLoadingTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("Controlled profile request did not start")
    }

    static func main() async {
        let guest = ProfileWorkoutLoaderHarness()
        guest.appModel.currentUser = nil
        guest.gameFeedRequests = [.init(id: "private-game")]
        guest.gameFeedVisits = [.init(id: "private-visit")]
        guest.gameFeedError = "old-error"
        await guest.run()
        expect(guest.appModel.repository.gameCalls == 0 && guest.appModel.repository.visitCalls == 0,
               "Guest profile never loads another user's private workout history")
        expect(guest.gameFeedRequests.isEmpty && guest.gameFeedVisits.isEmpty && guest.gameFeedAccountID == nil,
               "Losing authentication immediately clears both private history sources")
        expect(guest.gameFeedError == nil && !guest.isGameFeedLoading && !guest.isVisitFeedLoading,
               "Guest reset clears obsolete error and loading state")

        let partial = ProfileWorkoutLoaderHarness()
        partial.appModel.repository.games = { [.init(id: "game-A")] }
        partial.appModel.repository.visits = { [.init(id: "visit-A")] }
        await partial.run()
        expect(partial.gameFeedRequests.map(\.id) == ["game-A"] && partial.gameFeedVisits.map(\.id) == ["visit-A"],
               "Both authenticated sources populate personal history")
        expect(partial.gameFeedAccountID == "A" && !partial.isGameFeedLoading && !partial.isVisitFeedLoading,
               "History is scoped to its authenticated owner after loading")
        partial.appModel.repository.games = { throw ProfileLoadError.unavailable }
        partial.appModel.repository.visits = { [.init(id: "visit-updated")] }
        await partial.run()
        expect(partial.gameFeedError != nil && partial.visitFeedError == nil,
               "A games refresh failure is explicit rather than a false empty history")
        expect(partial.gameFeedRequests.map(\.id) == ["game-A"] && partial.gameFeedVisits.map(\.id) == ["visit-updated"],
               "An unavailable source retains its last good history while another source refreshes")
        let visitCalls = partial.appModel.repository.visitCalls
        partial.appModel.repository.games = { [.init(id: "game-retried")] }
        await partial.retryGames()
        expect(partial.gameFeedError == nil && partial.gameFeedRequests.map(\.id) == ["game-retried"],
               "Retry clears the error only after the requested source succeeds")
        expect(partial.appModel.repository.visitCalls == visitCalls, "Retrying games does not refetch successful visits")
        partial.appModel.repository.visits = { throw ProfileLoadError.unavailable }
        let gameCalls = partial.appModel.repository.gameCalls
        await partial.retryVisits()
        expect(partial.visitFeedError != nil && partial.gameFeedVisits.map(\.id) == ["visit-updated"],
               "Visits retain their last good records with a visible source-specific error")
        expect(partial.appModel.repository.gameCalls == gameCalls, "Retrying visits does not disturb successful games")

        let stale = ProfileWorkoutLoaderHarness()
        stale.appModel.currentUser = ProfileUser(id: "B")
        stale.reset()
        await stale.oldGames("A")
        await stale.oldVisits("A")
        expect(stale.appModel.repository.gameCalls == 0 && stale.appModel.repository.visitCalls == 0,
               "Queued old-account child loaders are rejected before starting network requests")
        expect(!stale.isGameFeedLoading && !stale.isVisitFeedLoading && stale.gameFeedAccountID == "B",
               "An old child cannot claim loading state for a newly selected account")

        let overlap = ProfileWorkoutLoaderHarness()
        var gameGates: [CheckedContinuation<[MatchGameRequest], Error>] = []
        overlap.appModel.repository.games = { try await withCheckedThrowingContinuation { gameGates.append($0) } }
        overlap.appModel.repository.visits = { [.init(id: "visit-" + overlap.appModel.currentUser!.id)] }
        let old = Task { await overlap.run() }
        await waitUntil { gameGates.count == 1 }
        overlap.appModel.currentUser = ProfileUser(id: "B")
        overlap.reset()
        let fresh = Task { await overlap.run() }
        await waitUntil { gameGates.count == 2 }
        let newToken = overlap.gameFeedRequestToken
        gameGates[0].resume(returning: [.init(id: "game-A")])
        await old.value
        expect(overlap.gameFeedRequests.isEmpty && overlap.gameFeedAccountID == "B",
               "A delayed old-account response cannot repopulate cleared private games")
        expect(overlap.isGameFeedLoading && overlap.gameFeedRequestToken == newToken,
               "An old request's cleanup cannot release the new account's loading state")
        gameGates[1].resume(returning: [.init(id: "game-B")])
        await fresh.value
        expect(overlap.gameFeedRequests.map(\.id) == ["game-B"] && overlap.gameFeedVisits.map(\.id) == ["visit-B"],
               "Only the newly authenticated account's results remain visible")

        let cancellation = ProfileWorkoutLoaderHarness()
        var canceledGate: CheckedContinuation<[PersonalActivity], Error>?
        cancellation.reset()
        cancellation.gameFeedVisits = [.init(id: "retained")]
        cancellation.appModel.repository.visits = { try await withCheckedThrowingContinuation { canceledGate = $0 } }
        let canceled = Task { await cancellation.retryVisits() }
        await waitUntil { canceledGate != nil }
        canceled.cancel()
        canceledGate!.resume(returning: [.init(id: "canceled-result")])
        await canceled.value
        expect(cancellation.gameFeedVisits.map(\.id) == ["retained"] && !cancellation.isVisitFeedLoading,
               "Cancellation rejects a late result and leaves previously loaded history intact")
        expect(cancellation.visitFeedError == nil, "Cancellation is not presented as a failed source")
        cancellation.appModel.currentUser = nil
        await cancellation.run()
        expect(cancellation.gameFeedRequests.isEmpty && cancellation.gameFeedVisits.isEmpty,
               "Logout clears retained history rather than carrying it to a future login")

        let deduplicated = ProfileWorkoutLoaderHarness()
        deduplicated.reset()
        var inFlight: CheckedContinuation<[MatchGameRequest], Error>?
        deduplicated.appModel.repository.games = { try await withCheckedThrowingContinuation { inFlight = $0 } }
        let first = Task { await deduplicated.retryGames() }
        await waitUntil { inFlight != nil }
        await deduplicated.retryGames()
        expect(deduplicated.appModel.repository.gameCalls == 1 && deduplicated.isGameFeedLoading,
               "An overlapping refresh does not duplicate the same source request")
        inFlight!.resume(returning: [.init(id: "only-result")])
        await first.value
        expect(deduplicated.gameFeedRequests.map(\.id) == ["only-result"] && !deduplicated.isGameFeedLoading,
               "The retained request completes normally after an overlapping refresh")
        print("Profile workout loading: \(checks) checks passed; owner-only integration checked")
    }
}
