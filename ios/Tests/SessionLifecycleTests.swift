import Foundation

@MainActor
final class Gate<Value> {
    var continuation: CheckedContinuation<Value, Never>?
    func wait() async -> Value { await withCheckedContinuation { continuation = $0 } }
    func waitUntilSuspended() async {
        while continuation == nil { await Task.yield() }
    }
    func release(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}

@main
@MainActor
struct SessionLifecycleTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func main() async {
        let offline = LifecycleModelHarness()
        offline.repository.fetch = { throw URLError(.notConnectedToInternet) }
        await offline.bootstrap()
        expect(offline.sessionRestoreState == .failed && offline.currentUser == nil, "Offline restore blocks normal guest actions")
        expect(offline.repository.clearCount == 0 && offline.repository.logoutTokens.isEmpty, "Retryable restore failure preserves credentials")
        offline.repository.fetch = { UserProfile(id: "A") }
        await offline.bootstrap()
        expect(offline.sessionRestoreState == .ready && offline.currentUser?.id == "A", "Retry successfully restores the preserved session")
        offline.repository.fetch = { throw APIError.unauthorized }
        await offline.bootstrap()
        expect(offline.sessionRestoreState == .ready && offline.repository.clearCount == 1, "Expired session clears authentication and permits guest access")

        let boot = LifecycleModelHarness()
        let bootGate = Gate<UserProfile>()
        boot.repository.fetch = { await bootGate.wait() }
        let bootTask = Task { await boot.bootstrap() }
        await bootGate.waitUntilSuspended()
        boot.guestDraft.isOnboardingComplete = true
        boot.pendingPersonalVisit = "guest-selected-court"
        boot.matchMoment = "match-with-previous-account"
        boot.gameConfirmation = "game-with-previous-account"
        expect(boot.sessionRestoreState == .restoring, "Normal content stays gated while startup awaits authentication")
        boot.logout()
        bootGate.release(UserProfile(id: "A"))
        await bootTask.value
        expect(boot.currentUser == nil && !boot.notificationManager.monitoring, "Delayed bootstrap cannot restore a logged-out account")
        expect(!boot.guestDraft.isOnboardingComplete, "Logout clears the previous account onboarding draft")
        expect(boot.pendingPersonalVisit == nil, "Logout clears a guest visit continuation before the next account")
        expect(boot.matchMoment == nil, "Logout closes a match moment that belongs to the previous account")
        expect(boot.gameConfirmation == nil, "Logout closes a game confirmation that belongs to the previous account")
        expect(boot.repository.logoutTokens == ["device-token"], "Logout passes the device token captured before state clearing")
        expect(boot.notificationManager.cleared == 1 && UpcomingGamesWidgetStore.account == nil, "Logout clears notification and widget state directly")
        expect(RemoteImagePipeline.shared.clearCount > 0, "Logout clears the image cache")

        let edit = LifecycleModelHarness()
        edit.currentUser = UserProfile(id: "A")
        let oldGeneration = edit.sessionGeneration
        let editGate = Gate<UserProfile>()
        edit.repository.update = { _ in await editGate.wait() }
        let editTask = Task { await edit.saveProfile(UserProfile(id: "A")) }
        await editGate.waitUntilSuspended()
        edit.logout()
        edit.authEmail = "b@example.com"
        edit.repository.fetch = { UserProfile(id: "B") }
        await edit.verify(code: "123456", userAgreementAccepted: true)
        editGate.release(UserProfile(id: "A"))
        let saved = await editTask.value
        expect(!saved && edit.currentUser?.id == "B", "A delayed profile save cannot overwrite the next account")
        expect(!edit.isCurrentSession(oldGeneration), "The old profile view cannot send work with the next account credentials")
        expect(UpcomingGamesWidgetStore.account == "B", "New account owns the widget after authentication")

        for apple in [false, true] {
            let model = LifecycleModelHarness()
            let authGate = Gate<Void>()
            model.repository.authenticate = { await authGate.wait() }
            let authTask = Task {
                if apple {
                    await model.signInWithApple(identityToken: "apple", email: nil, givenName: nil, familyName: nil, userAgreementAccepted: true)
                } else {
                    await model.verify(code: "123456", userAgreementAccepted: true)
                }
            }
            await authGate.waitUntilSuspended()
            model.logout()
            model.isBusy = true // The next operation owns this flag.
            authGate.release(())
            await authTask.value
            expect(model.currentUser == nil && model.repository.fetchCount == 0, "Delayed authentication must not fetch or adopt a profile after logout")
            expect(model.isBusy, "Stale authentication cleanup cannot reset another operation's busy state")
        }

        for apple in [false, true] {
            let model = LifecycleModelHarness()
            model.guestDraft.isOnboardingComplete = true
            model.repository.fetch = { throw URLError(.notConnectedToInternet) }
            if apple {
                await model.signInWithApple(identityToken: "apple", email: nil, givenName: nil, familyName: nil, userAgreementAccepted: true)
            } else {
                await model.verify(code: "123456", userAgreementAccepted: true)
            }
            expect(model.currentUser == nil && model.repository.logoutTokens.count == 1, "Failure hydrating a new session revokes its otherwise hidden authentication")
            expect(model.guestDraft.isOnboardingComplete && model.errorMessage != nil, "Hydration failure retains the guest draft and actionable error")
        }

        for apple in [false, true] {
            let incomplete = LifecycleModelHarness()
            incomplete.guestDraft.isOnboardingComplete = true
            incomplete.repository.fetch = { UserProfile(id: "incomplete", isOnboardingComplete: false) }
            incomplete.repository.update = { _ in throw URLError(.notConnectedToInternet) }
            if apple {
                await incomplete.signInWithApple(identityToken: "apple", email: nil, givenName: nil, familyName: nil, userAgreementAccepted: true)
            } else {
                await incomplete.verify(code: "123456", userAgreementAccepted: true)
            }
            expect(incomplete.currentUser?.id == "incomplete" && incomplete.notificationManager.monitoring, "Draft promotion failure retains monitoring for the adopted authenticated account")
            expect(UpcomingGamesWidgetStore.account == "incomplete" && incomplete.repository.logoutTokens.isEmpty, "Draft promotion failure retains widget ownership and authenticated session")
        }

        let challenge = LifecycleModelHarness()
        let codeGate = Gate<AuthChallenge>()
        challenge.repository.challenge = { await codeGate.wait() }
        let codeTask = Task { await challenge.requestCode(userAgreementAccepted: true) }
        await codeGate.waitUntilSuspended()
        challenge.logout()
        codeGate.release(AuthChallenge())
        let challengeAccepted = await codeTask.value
        expect(!challengeAccepted && challenge.debugCode == nil && challenge.authMessage == nil, "Delayed OTP response cannot repopulate logged-out auth state")
        print("Session lifecycle tests: \(checks) checks passed")
    }
}
