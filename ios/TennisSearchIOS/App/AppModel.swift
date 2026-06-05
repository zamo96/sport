import Foundation
import SwiftUI

enum BottomBarDisplayMode {
    case expanded
    case compact
    case hidden
}

@MainActor
final class AppModel: ObservableObject {
    struct ServerRecoveryNotice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published var currentUser: UserProfile?
    @Published var guestDraft: GuestOnboardingDraft
    @Published var isBusy = false
    @Published var authEmail = ""
    @Published var debugCode: String?
    @Published var authMessage: String?
    @Published var errorMessage: String?
    @Published var presentedAuthStep: AuthStep?
    @Published var pendingNavigationTarget: AppNavigationTarget?
    @Published var pendingChatMatchID: String?
    @Published var bottomBarDisplayMode: BottomBarDisplayMode = .expanded
    @Published var pendingHighlightedDiscoverUserID: String?
    @Published var pendingHighlightedSearchID: String?
    @Published var pendingHighlightedGameRequestID: String?
    @Published var pendingDiscoverSimilarPlayersHint = false
    @Published var pendingDiscoverFirstInterestHint = false
    @Published var lastSelectedDiscoverTab: DiscoverTab = .swipe
    @Published var hasActiveUpcomingGameRequests = false
    @Published var serverRecoveryNotice: ServerRecoveryNotice?

    let repository: TennisRepository
    let isUsingMockData: Bool
    let notificationManager = NotificationManager()

    private let guestDraftStore = GuestDraftStore()
    private let discoverHintStore = DiscoverHintStore()
    private var guestDraftSaveTask: Task<Void, Never>?

    init() {
        let useMock = AppConfig.useMockData
        isUsingMockData = useMock
        guestDraft = guestDraftStore.load()
        pendingDiscoverSimilarPlayersHint = discoverHintStore.hasPendingSimilarPlayersHint()
        pendingDiscoverFirstInterestHint = discoverHintStore.hasPendingFirstInterestHint()

        if useMock {
            repository = MockRepository()
        } else if let url = AppConfig.apiBaseURL {
            repository = LiveTennisRepository(
                baseURL: url,
                allowDebugServerTrustOverride: AppConfig.allowDebugServerTrust
            )
        } else {
            repository = MockRepository()
        }
    }

    var isAuthenticated: Bool {
        currentUser != nil
    }

    var isGuestModeAvailable: Bool {
        !isAuthenticated && guestDraft.hasProfileBasics && guestDraft.onboardingCompleted
    }

    func bootstrap() async {
        await notificationManager.configure()

        guard !isUsingMockData else {
            return
        }

        do {
            currentUser = try await repository.fetchCurrentUser()
            notificationManager.startMonitoring(repository: repository)
        } catch {
            currentUser = nil
        }
    }

    func updateGuestDraft(_ draft: GuestOnboardingDraft) {
        guestDraft = draft
        guestDraftSaveTask?.cancel()
        let store = guestDraftStore
        guestDraftSaveTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else {
                return
            }
            store.save(draft)
        }
    }

    func resetGuestDraft() {
        guestDraftSaveTask?.cancel()
        guestDraft = .default
        guestDraftStore.clear()
    }

    func presentAuth(step: AuthStep) {
        presentedAuthStep = step
    }

    func dismissPresentedAuth() {
        presentedAuthStep = nil
    }

    func requestCode() async {
        guard !authEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Укажи email"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let challenge = try await repository.requestCode(email: authEmail)
            authMessage = challenge.message
            debugCode = challenge.debugCode
            errorMessage = nil
            presentedAuthStep = .code
        } catch {
            present(error: error)
        }
    }

    func verify(code: String) async {
        guard !authEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Сначала укажи email"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let session = try await repository.verifyCode(email: authEmail, code: code)
            var user = try await repository.fetchCurrentUser()

            if !session.onboardingCompleted && guestDraft.hasProfileBasics {
                user = try await repository.updateProfile(makeProfileFromGuestDraft(userId: user.id, email: user.email))
            }

            currentUser = user
            notificationManager.startMonitoring(repository: repository)
            resetGuestDraft()
            authMessage = nil
            debugCode = nil
            errorMessage = nil
            presentedAuthStep = nil
        } catch {
            present(error: error)
        }
    }

    func signInWithApple(identityToken: String, email: String?, givenName: String?, familyName: String?) async {
        isBusy = true
        defer { isBusy = false }

        do {
            if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authEmail = email
            }

            let session = try await repository.signInWithApple(
                identityToken: identityToken,
                email: email,
                givenName: givenName,
                familyName: familyName
            )
            var user = try await repository.fetchCurrentUser()

            if !session.onboardingCompleted && guestDraft.hasProfileBasics {
                user = try await repository.updateProfile(makeProfileFromGuestDraft(userId: user.id, email: user.email))
            }

            currentUser = user
            notificationManager.startMonitoring(repository: repository)
            resetGuestDraft()
            authMessage = nil
            debugCode = nil
            errorMessage = nil
            presentedAuthStep = nil
        } catch {
            present(error: error)
        }
    }

    func saveProfile(_ profile: UserProfile) async {
        isBusy = true
        defer { isBusy = false }

        do {
            currentUser = try await repository.updateProfile(profile)
            errorMessage = nil
        } catch {
            present(error: error)
        }
    }

    func logout() {
        guestDraftSaveTask?.cancel()
        notificationManager.stopMonitoring()
        repository.clearAuthSession()
        currentUser = nil
        debugCode = nil
        authMessage = nil
        errorMessage = nil
        authEmail = ""
        presentedAuthStep = nil
        pendingNavigationTarget = nil
        pendingChatMatchID = nil
        bottomBarDisplayMode = .expanded
        pendingHighlightedDiscoverUserID = nil
        pendingHighlightedSearchID = nil
        pendingHighlightedGameRequestID = nil
        pendingDiscoverSimilarPlayersHint = discoverHintStore.hasPendingSimilarPlayersHint()
        pendingDiscoverFirstInterestHint = discoverHintStore.hasPendingFirstInterestHint()
        hasActiveUpcomingGameRequests = false
        serverRecoveryNotice = nil
    }

    func present(error: Error) {
        if error.isServerIssue {
            let message = error.serverRecoveryMessage
            errorMessage = nil
            serverRecoveryNotice = ServerRecoveryNotice(
                title: "Что-то пошло не так",
                message: message
            )
            return
        }

        errorMessage = error.detailedMessage
    }

    func dismissServerRecoveryNotice() {
        serverRecoveryNotice = nil
    }

    func queueDiscoverSimilarPlayersHint() {
        lastSelectedDiscoverTab = .swipe
        pendingDiscoverSimilarPlayersHint = true
        discoverHintStore.setPendingSimilarPlayersHint(true)
    }

    func shouldPresentDiscoverSimilarPlayersHint() -> Bool {
        pendingDiscoverSimilarPlayersHint
    }

    func consumeDiscoverSimilarPlayersHint() {
        pendingDiscoverSimilarPlayersHint = false
        discoverHintStore.setPendingSimilarPlayersHint(false)
    }

    func completeDiscoverSimilarPlayersHint() {
        consumeDiscoverSimilarPlayersHint()
    }

    func queueDiscoverFirstInterestHintIfNeeded() -> Bool {
        guard !discoverHintStore.hasCompletedFirstInterestHint(for: currentUser?.id) else {
            return false
        }

        pendingDiscoverFirstInterestHint = true
        discoverHintStore.setPendingFirstInterestHint(true)
        return true
    }

    func shouldPresentDiscoverFirstInterestHint() -> Bool {
        pendingDiscoverFirstInterestHint && !discoverHintStore.hasCompletedFirstInterestHint(for: currentUser?.id)
    }

    func consumeDiscoverFirstInterestHint() {
        pendingDiscoverFirstInterestHint = false
        discoverHintStore.setPendingFirstInterestHint(false)
    }

    func completeDiscoverFirstInterestHint() {
        consumeDiscoverFirstInterestHint()
        discoverHintStore.setCompletedFirstInterestHint(true, for: currentUser?.id)
    }

    func navigate(to target: AppNavigationTarget) {
        pendingNavigationTarget = target
    }

    func clearPendingNavigation() {
        pendingNavigationTarget = nil
        pendingHighlightedDiscoverUserID = nil
        pendingHighlightedSearchID = nil
        pendingHighlightedGameRequestID = nil
    }

    private func makeProfileFromGuestDraft(userId: String, email: String?) -> UserProfile {
        UserProfile(
            id: userId,
            email: email,
            name: guestDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            age: guestDraft.age,
            gender: guestDraft.gender,
            city: guestDraft.city,
            district: guestDraft.preferredDistricts.first ?? guestDraft.district,
            preferredDistricts: guestDraft.preferredDistricts,
            bio: nil,
            avatarUrl: nil,
            tennisLevel: guestDraft.sportLevels[guestDraft.preferredSports.first?.rawValue ?? ""] ?? 5,
            preferredSports: guestDraft.preferredSports,
            sportLevels: guestDraft.sportLevels,
            preferredPlayFormat: guestDraft.preferredPlayFormat,
            preferredSurface: guestDraft.preferredSurface,
            availableDays: guestDraft.availableDays,
            availableTimeRanges: guestDraft.availableTimeRanges,
            availabilityByDay: guestDraft.availabilityByDay,
            isLookingForGame: guestDraft.isLookingForGame,
            searchRadiusKm: guestDraft.searchRadiusKm,
            onboardingCompleted: true,
            isVerified: true,
            notificationMatches: true,
            notificationMessages: true,
            notificationGames: true,
            notificationSound: true
        )
    }
}

enum AppNavigationTarget: Equatable {
    case discover(DiscoverTab, highlightedUserID: String? = nil, highlightedSearchID: String? = nil, highlightedGameRequestID: String? = nil)
    case matches
    case searches
    case chat(String)
}

enum AppConfig {
    static var apiBaseURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }

        let scheme: String
        if
            let configuredScheme = Bundle.main.object(forInfoDictionaryKey: "APIScheme") as? String,
            !configuredScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            scheme = configuredScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            scheme = "https"
        }

        return URL(string: "\(scheme)://\(trimmed)")
    }

    static var useMockData: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "UseMockData") as? String else {
            return true
        }

        return value.uppercased() == "YES"
    }

    static var allowDebugServerTrust: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AllowDebugServerTrust") as? String else {
            return false
        }

        return value.uppercased() == "YES"
    }

    static var apnsEnvironment: APNSEnvironment? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String,
            let environment = APNSEnvironment(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }

        return environment
    }

    static func searchInviteURL(searchId: String) -> URL? {
        guard let baseURL = apiBaseURL else {
            return nil
        }

        return baseURL
            .appendingPathComponent("play")
            .appendingPathComponent("searches")
            .appendingPathComponent("invite")
            .appendingPathComponent(searchId)
    }
}

private struct GuestDraftStore {
    private let key = "ios.guest-onboarding-draft.v1"
    private let defaults = UserDefaults.standard

    func load() -> GuestOnboardingDraft {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode(GuestOnboardingDraft.self, from: data)) ?? .default
    }

    func save(_ draft: GuestOnboardingDraft) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(draft) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

private struct DiscoverHintStore {
    private let pendingKey = "ios.discover.similarPlayersHint.pending.v1"
    private let firstInterestPendingKey = "ios.discover.firstInterestHint.pending.v1"
    private let firstInterestCompletedKeyPrefix = "ios.discover.firstInterestHint.completed.v1"
    private let defaults = UserDefaults.standard

    func hasPendingSimilarPlayersHint() -> Bool {
        defaults.bool(forKey: pendingKey)
    }

    func setPendingSimilarPlayersHint(_ isPending: Bool) {
        defaults.set(isPending, forKey: pendingKey)
    }

    func hasPendingFirstInterestHint() -> Bool {
        defaults.bool(forKey: firstInterestPendingKey)
    }

    func setPendingFirstInterestHint(_ isPending: Bool) {
        defaults.set(isPending, forKey: firstInterestPendingKey)
    }

    func hasCompletedFirstInterestHint(for userID: String?) -> Bool {
        defaults.bool(forKey: firstInterestCompletedKey(for: userID))
    }

    func setCompletedFirstInterestHint(_ isCompleted: Bool, for userID: String?) {
        defaults.set(isCompleted, forKey: firstInterestCompletedKey(for: userID))
    }

    private func firstInterestCompletedKey(for userID: String?) -> String {
        let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scope = trimmedUserID.isEmpty ? "guest" : trimmedUserID
        return "\(firstInterestCompletedKeyPrefix).\(scope)"
    }
}

extension Error {
    var isServerIssue: Bool {
        if let apiError = self as? APIError {
            switch apiError {
            case .server, .invalidResponse, .invalidPayload:
                return true
            case .invalidBaseURL:
                return false
            }
        }

        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code != NSURLErrorCancelled
        }

        return false
    }

    var serverRecoveryMessage: String {
        let nsError = self as NSError

        if nsError.domain == NSURLErrorDomain {
            return "Сервис временно недоступен. Уже переподключаемся и скоро всё исправим."
        }

        return "Сервис временно отвечает нестабильно. Попробуй ещё раз через пару секунд."
    }

    var isCancellationLike: Bool {
        if self is CancellationError {
            return true
        }

        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        let description = localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return description == "cancelled" || description == "canceled"
    }

    var detailedMessage: String {
        let nsError = self as NSError
        var parts = [localizedDescription]

        if nsError.domain == NSURLErrorDomain {
            parts.append("URLSession code: \(nsError.code)")
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("Underlying: \(underlying.domain) \(underlying.code)")
            if !underlying.localizedDescription.isEmpty {
                parts.append(underlying.localizedDescription)
            }
        }

        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
            parts.append(reason)
        }

        return parts.joined(separator: "\n")
    }
}
