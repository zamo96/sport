#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-session-lifecycle.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / 'TennisSearchIOS'
model = (root / 'App/AppModel.swift').read_text()
def declaration(source, name):
    start = source.index(name)
    index = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index]
scaffold = '''import Foundation
enum APIError: Error { case unauthorized }
struct UserProfile: Equatable { let id: String; var isOnboardingComplete = true }
struct GuestDraft { var isOnboardingComplete = false; var showOnMap = false }
struct AuthChallenge { let message = "Sent"; let debugCode: String? = "123456" }
enum LegalDocuments { static let userAgreementVersion = "v1"; static let acceptanceError = "Accept terms" }
@MainActor final class NotificationManager {
    var pushDeviceToken: String? = "device-token"
    var cleared = 0
    var monitoring = false
    func configure() async {}
    func startMonitoring(repository: FakeRepository) { monitoring = true }
    func clearAccountState() { cleared += 1; monitoring = false }
}
@MainActor enum UpcomingGamesWidgetStore {
    static var account: String?
    static func setCurrentAccount(_ id: String) { account = id }
    static func clear() { account = nil }
}
@MainActor final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()
    var clearCount = 0
    func clear() { clearCount += 1 }
}
struct DiscoverHintStore {
    func hasPendingSimilarPlayersHint() -> Bool { false }
    func hasPendingFirstInterestHint() -> Bool { false }
}
@MainActor final class FakeRepository {
    var fetch: () async throws -> UserProfile = { UserProfile(id: "A") }
    var update: (UserProfile) async throws -> UserProfile = { $0 }
    var authenticate: () async throws -> Void = {}
    var challenge: () async throws -> AuthChallenge = { AuthChallenge() }
    var fetchCount = 0
    var logoutTokens: [String?] = []
    var clearCount = 0
    func clearAuthSession() { clearCount += 1 }
    func fetchCurrentUser() async throws -> UserProfile { fetchCount += 1; return try await fetch() }
    func updateProfile(_ user: UserProfile) async throws -> UserProfile { try await update(user) }
    func requestCode(email: String, userAgreementAccepted: Bool, userAgreementVersion: String) async throws -> AuthChallenge { try await challenge() }
    func verifyCode(email: String, code: String, userAgreementAccepted: Bool, userAgreementVersion: String, showOnMap: Bool?) async throws { try await authenticate() }
    func signInWithApple(identityToken: String, email: String?, givenName: String?, familyName: String?, userAgreementAccepted: Bool, userAgreementVersion: String, showOnMap: Bool?) async throws { try await authenticate() }
    func logout(pushDeviceToken: String?) { logoutTokens.append(pushDeviceToken) }
}
@MainActor final class LifecycleModelHarness {
    let repository = FakeRepository()
    let notificationManager = NotificationManager()
    let discoverHintStore = DiscoverHintStore()
    var currentUser: UserProfile?
    var guestDraft = GuestDraft()
    var sessionGeneration = UUID()
    enum SessionRestoreState { case restoring, failed, ready }
    var sessionRestoreState = SessionRestoreState.restoring
    var isBusy = false
    var isUsingMockData = false
    var tabContentLoadingKeys: Set<String> = []
    var pendingLocaleRecommendation: String?
    var dismissedDiscoverSummary: String?
    var acknowledgedIncomingLikes: String?
    var authEmail = "a@example.com"
    var authMessage: String?
    var debugCode: String?
    var errorMessage: String?
    var authUserAgreementAccepted = false
    var presentedAuthStep: String?
    var pendingNavigationTarget: String?
    var pendingChatMatchID: String?
    var pendingSearchLobbyID: String?
    var pendingCreateSearchPrefill: String?
    var pendingCourtID: String?
    var pendingPersonalVisit: String?
    enum Bar { case expanded }
    var bottomBarDisplayMode = Bar.expanded
    var pendingHighlightedDiscoverUserID: String?
    var pendingHighlightedSearchID: String?
    var pendingHighlightedGameRequestID: String?
    var pendingDiscoverSimilarPlayersHint = false
    var pendingDiscoverFirstInterestHint = false
    var hasActiveUpcomingGameRequests = false
    var serverRecoveryNotice: String?
    func resetGuestDraft() { guestDraft = GuestDraft() }
    func adoptGuestUserIntentIfNeeded() {}
    func clearGuestUserIntent() {}
    func checkForAppUpdate() async {}
    func reconcileLocalePreference(_ user: UserProfile) async -> UserProfile { user }
    func prepareOnboardingDraft(for user: UserProfile) {}
    func makeProfileFromGuestDraft(_ user: UserProfile) -> UserProfile { user }
    func present(error: Error) { errorMessage = error.localizedDescription }
'''
for name in ['    func isCurrentSession(', '    func bootstrap()', '    func requestCode(', '    func verify(', '    func signInWithApple(', '    func saveProfile(', '    func logout()']:
    scaffold += '\n' + declaration(model, name)
scaffold += '\n}\n'
(Path(sys.argv[2]) / 'LifecycleProduction.swift').write_text(scaffold)
PY
swiftc "$temp_dir/LifecycleProduction.swift" "$test_dir/SessionLifecycleTests.swift" -o "$temp_dir/session-lifecycle-tests"
"$temp_dir/session-lifecycle-tests"
