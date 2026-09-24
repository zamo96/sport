import Foundation

@main
@MainActor
struct SportHomeLoadTests {
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
        fatalError("Controlled request did not start")
    }

    static func main() async {
        let guest = HomeLoadHarness()
        guest.appModel.currentUser = nil
        guest.gameRequests = [.init(id: "old")]
        guest.activities = [.init(id: "old")]
        guest.gameLoadFailed = true
        guest.activityLoadFailed = true
        await guest.run()
        expect(guest.appModel.repository.gameCalls == 0 && guest.appModel.repository.visitCalls == 0,
               "Guest Home never requests authenticated personal data")
        expect(guest.gameRequests.isEmpty && guest.activities.isEmpty && !guest.hasLoaded && !guest.isLoading,
               "Guest rendering clears any previous account's history")
        expect(!guest.gameLoadFailed && !guest.activityLoadFailed, "Guest access is not represented as a network error")

        let happy = HomeLoadHarness()
        happy.appModel.repository.games = { [.init(id: "game")] }
        happy.appModel.repository.visits = { [.init(id: "visit")] }
        await happy.run()
        expect(happy.gameRequests.map(\.id) == ["game"] && happy.activities.map(\.id) == ["visit"],
               "Both real sources populate Home after successful loading")
        expect(happy.hasLoaded && !happy.isLoading && !happy.gameLoadFailed && !happy.activityLoadFailed,
               "Successful loading leaves a complete non-error state")
        happy.appModel.repository.games = { throw LoadTestError.unavailable }
        await happy.run()
        expect(happy.gameLoadFailed && !happy.activityLoadFailed && happy.gameRequests.isEmpty,
               "A games error is explicitly flagged and stale games are not presented as current")
        expect(happy.activities.map(\.id) == ["visit"] && happy.hasLoaded,
               "A games error preserves the independently loaded personal visits")
        happy.appModel.repository.games = { [.init(id: "new-game")] }
        happy.appModel.repository.visits = { throw LoadTestError.unavailable }
        await happy.run()
        expect(!happy.gameLoadFailed && happy.activityLoadFailed && happy.activities.isEmpty,
               "A visits error is distinguished from an empty successful result")
        expect(happy.gameRequests.map(\.id) == ["new-game"], "A visits error leaves successful games visible")
        happy.appModel.repository.games = { throw LoadTestError.unavailable }
        await happy.run()
        expect(happy.gameLoadFailed && happy.activityLoadFailed && !happy.isLoading,
               "A total failure settles loading with two explicit errors")

        let switched = HomeLoadHarness()
        var accountGames: CheckedContinuation<[MatchGameRequest], Error>?
        switched.appModel.repository.games = { try await withCheckedThrowingContinuation { accountGames = $0 } }
        switched.appModel.repository.visits = { [.init(id: "A-visit")] }
        let oldAccountLoad = Task { await switched.run() }
        await waitUntil { accountGames != nil }
        switched.appModel.currentUser = User(id: "B")
        switched.appModel.sessionGeneration = UUID()
        accountGames!.resume(returning: [.init(id: "A-game")])
        await oldAccountLoad.value
        expect(switched.gameRequests.isEmpty && switched.activities.isEmpty && !switched.hasLoaded,
               "A delayed old-account result cannot populate another account's Home")

        let overlap = HomeLoadHarness()
        var requests: [CheckedContinuation<[MatchGameRequest], Error>] = []
        overlap.appModel.repository.games = { try await withCheckedThrowingContinuation { requests.append($0) } }
        let first = Task { await overlap.run() }
        await waitUntil { requests.count == 1 }
        let second = Task { await overlap.run() }
        await waitUntil { requests.count == 2 }
        requests[1].resume(returning: [.init(id: "newest")])
        await second.value
        expect(overlap.gameRequests.map(\.id) == ["newest"] && !overlap.isLoading,
               "The latest refresh may finish independently of an older request")
        requests[0].resume(returning: [.init(id: "stale")])
        await first.value
        expect(overlap.gameRequests.map(\.id) == ["newest"], "An out-of-order response cannot overwrite a newer refresh")

        let cancelled = HomeLoadHarness()
        var cancelledGames: CheckedContinuation<[MatchGameRequest], Error>?
        cancelled.appModel.repository.games = { try await withCheckedThrowingContinuation { cancelledGames = $0 } }
        let cancelledLoad = Task { await cancelled.run() }
        await waitUntil { cancelledGames != nil }
        cancelledLoad.cancel()
        cancelledGames!.resume(returning: [.init(id: "cancelled-result")])
        await cancelledLoad.value
        expect(cancelled.gameRequests.isEmpty && !cancelled.hasLoaded && !cancelled.isLoading,
               "Task cancellation rejects transport results even if the transport completes anyway")

        let departed = HomeLoadHarness()
        var departedGames: CheckedContinuation<[MatchGameRequest], Error>?
        departed.appModel.repository.games = { try await withCheckedThrowingContinuation { departedGames = $0 } }
        let departedLoad = Task { await departed.run() }
        await waitUntil { departedGames != nil }
        departed.loadToken = UUID()
        departedGames!.resume(returning: [.init(id: "offscreen-result")])
        await departedLoad.value
        expect(departed.gameRequests.isEmpty && !departed.hasLoaded,
               "Invalidating the load token on departure rejects a late result")
        print("Sport home loading: \(checks) checks passed")
    }
}
