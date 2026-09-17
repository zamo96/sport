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

    struct LocaleRecommendation: Identifiable, Equatable {
        let locale: AppLocale

        var id: String { locale.rawValue }
    }

    @Published var currentUser: UserProfile?
    @Published var guestDraft: GuestOnboardingDraft
    @Published var isBusy = false
    @Published var authEmail = ""
    @Published var authUserAgreementAccepted = false
    @Published var debugCode: String?
    @Published var authMessage: String?
    @Published var errorMessage: String?
    @Published var presentedAuthStep: AuthStep?
    @Published var pendingNavigationTarget: AppNavigationTarget?
    @Published var pendingChatMatchID: String?
    @Published var pendingSearchLobbyID: String?
    @Published var pendingCreateSearchPrefill: CreateSearchPrefill?
    @Published var pendingCourtID: String?
    @Published var bottomBarDisplayMode: BottomBarDisplayMode = .expanded
    @Published var pendingHighlightedDiscoverUserID: String?
    @Published var pendingHighlightedSearchID: String?
    @Published var pendingHighlightedGameRequestID: String?
    @Published var pendingDiscoverSimilarPlayersHint = false
    @Published var pendingDiscoverFirstInterestHint = false
    @Published var lastSelectedDiscoverTab: DiscoverTab = .swipe
    @Published var hasActiveUpcomingGameRequests = false
    @Published var serverRecoveryNotice: ServerRecoveryNotice?
    @Published var pendingLocaleRecommendation: LocaleRecommendation?
    @Published private(set) var tabContentLoadingKeys: Set<String> = []

    let repository: TennisRepository
    let isUsingMockData: Bool
    let notificationManager = NotificationManager()
    let localeStore: LocaleStore

    private let guestDraftStore = GuestDraftStore()
    private let discoverHintStore = DiscoverHintStore()
    private var guestDraftSaveTask: Task<Void, Never>?
    // Presentation-only, bounded to the last dismissal in this app session.
    private var dismissedDiscoverSummary: (accountID: String?, signature: String)?

    init(localeStore: LocaleStore = LocaleStore()) {
        self.localeStore = localeStore
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
                allowDebugServerTrustOverride: AppConfig.allowDebugServerTrust,
                localeProvider: { [weak localeStore] in
                    localeStore?.effectiveLocale.rawValue ?? AppLocale.en.rawValue
                }
            )
        } else {
            repository = MockRepository()
        }
    }

    func considerLocaleRecommendation(for place: GeoPlace) {
        guard !localeStore.hasManualOverride,
              let rawRecommendation = place.recommendedLocale?.lowercased(),
              let recommendation = AppLocale(rawValue: rawRecommendation),
              recommendation != localeStore.effectiveLocale else {
            return
        }

        pendingLocaleRecommendation = LocaleRecommendation(locale: recommendation)
    }

    func acceptLocaleRecommendation() {
        guard let recommendation = pendingLocaleRecommendation else { return }
        setManualLocale(recommendation.locale)
        pendingLocaleRecommendation = nil
    }

    func dismissLocaleRecommendation() {
        pendingLocaleRecommendation = nil
    }

    func setManualLocale(_ locale: AppLocale) {
        localeStore.setManualOverride(locale)
        if currentUser != nil {
            currentUser?.localeOverride = locale.rawValue
            Task { try? await repository.updateLocaleOverride(locale.rawValue) }
        }
    }

    var isAuthenticated: Bool {
        currentUser != nil
    }

    var isOnboardingComplete: Bool {
        currentUser?.isOnboardingComplete == true
    }

    var isGuestModeAvailable: Bool {
        !isAuthenticated && guestDraft.isOnboardingComplete
    }

    func bootstrap() async {
        await notificationManager.configure()

        guard !isUsingMockData else {
            return
        }

        do {
            let user = await reconcileLocalePreference(try await repository.fetchCurrentUser())
            prepareOnboardingDraft(for: user)
            currentUser = user
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
        authUserAgreementAccepted = false
    }

    @discardableResult
    func requestCode(userAgreementAccepted: Bool, userAgreementVersion: String = LegalDocuments.userAgreementVersion) async -> Bool {
        guard !authEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Укажи email"
            return false
        }
        guard userAgreementAccepted else {
            errorMessage = LegalDocuments.acceptanceError
            return false
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let challenge = try await repository.requestCode(
                email: authEmail,
                userAgreementAccepted: userAgreementAccepted,
                userAgreementVersion: userAgreementVersion
            )
            authMessage = challenge.message
            debugCode = challenge.debugCode
            errorMessage = nil
            return true
        } catch {
            present(error: error)
            return false
        }
    }

    func verify(code: String, userAgreementAccepted: Bool, userAgreementVersion: String = LegalDocuments.userAgreementVersion) async {
        guard !authEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Сначала укажи email"
            return
        }
        guard userAgreementAccepted else {
            errorMessage = LegalDocuments.acceptanceError
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await repository.verifyCode(
                email: authEmail,
                code: code,
                userAgreementAccepted: userAgreementAccepted,
                userAgreementVersion: userAgreementVersion,
                showOnMap: guestDraft.showOnMap
            )
            var user = await reconcileLocalePreference(try await repository.fetchCurrentUser())
            // The session token is already stored, so the account has to be
            // adopted before anything that can throw. Assigning it only after the
            // profile save left `currentUser` nil on failure while the token was
            // live: the app fell back to guest mode and still sent authenticated
            // requests, which is how a draft profile managed to send a like.
            currentUser = user

            if !user.isOnboardingComplete && guestDraft.isOnboardingComplete {
                user = try await repository.updateProfile(makeProfileFromGuestDraft(user))
            }

            prepareOnboardingDraft(for: user)
            currentUser = user
            notificationManager.startMonitoring(repository: repository)
            if user.isOnboardingComplete { resetGuestDraft() }
            authUserAgreementAccepted = false
            authMessage = nil
            debugCode = nil
            errorMessage = nil
            presentedAuthStep = nil
        } catch {
            present(error: error)
        }
    }

    func signInWithApple(
        identityToken: String,
        email: String?,
        givenName: String?,
        familyName: String?,
        userAgreementAccepted: Bool,
        userAgreementVersion: String = LegalDocuments.userAgreementVersion
    ) async {
        guard userAgreementAccepted else {
            errorMessage = LegalDocuments.acceptanceError
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                authEmail = email
            }

            _ = try await repository.signInWithApple(
                identityToken: identityToken,
                email: email,
                givenName: givenName,
                familyName: familyName,
                userAgreementAccepted: userAgreementAccepted,
                userAgreementVersion: userAgreementVersion,
                showOnMap: guestDraft.showOnMap
            )
            var user = await reconcileLocalePreference(try await repository.fetchCurrentUser())
            // The session token is already stored, so the account has to be
            // adopted before anything that can throw. Assigning it only after the
            // profile save left `currentUser` nil on failure while the token was
            // live: the app fell back to guest mode and still sent authenticated
            // requests, which is how a draft profile managed to send a like.
            currentUser = user

            if !user.isOnboardingComplete && guestDraft.isOnboardingComplete {
                user = try await repository.updateProfile(makeProfileFromGuestDraft(user))
            }

            prepareOnboardingDraft(for: user)
            currentUser = user
            notificationManager.startMonitoring(repository: repository)
            if user.isOnboardingComplete { resetGuestDraft() }
            authUserAgreementAccepted = false
            authMessage = nil
            debugCode = nil
            errorMessage = nil
            presentedAuthStep = nil
        } catch {
            present(error: error)
        }
    }

    @discardableResult
    func saveProfile(_ profile: UserProfile) async -> Bool {
        isBusy = true
        defer { isBusy = false }

        do {
            currentUser = try await repository.updateProfile(profile)
            errorMessage = nil
            serverRecoveryNotice = nil
            return true
        } catch {
            present(error: error)
            return false
        }
    }

    func isDiscoverSummaryDismissed(_ signature: String) -> Bool {
        guard let dismissal = dismissedDiscoverSummary else { return false }
        return dismissal.accountID == currentUser?.id && dismissal.signature == signature
    }

    func dismissDiscoverSummary(_ signature: String) {
        dismissedDiscoverSummary = (currentUser?.id, signature)
    }

    func logout() {
        dismissedDiscoverSummary = nil
        guestDraftSaveTask?.cancel()
        notificationManager.stopMonitoring()
        repository.clearAuthSession()
        currentUser = nil
        debugCode = nil
        authMessage = nil
        errorMessage = nil
        authEmail = ""
        authUserAgreementAccepted = false
        presentedAuthStep = nil
        pendingNavigationTarget = nil
        pendingChatMatchID = nil
        pendingSearchLobbyID = nil
        pendingCreateSearchPrefill = nil
        pendingCourtID = nil
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

        serverRecoveryNotice = nil
        errorMessage = error.detailedMessage
    }

    private func reconcileLocalePreference(_ user: UserProfile) async -> UserProfile {
        var resolvedUser = user
        if let accountLocale = user.localeOverride.flatMap(AppLocale.init(rawValue:)) {
            localeStore.setManualOverride(accountLocale)
            return resolvedUser
        }

        if let localLocale = localeStore.manualOverride {
            if (try? await repository.updateLocaleOverride(localLocale.rawValue)) != nil {
                resolvedUser.localeOverride = localLocale.rawValue
            }
        }
        return resolvedUser
    }

    func dismissServerRecoveryNotice() {
        serverRecoveryNotice = nil
    }

    func setTabContentLoading(_ key: String, isLoading: Bool) {
        if isLoading {
            guard !tabContentLoadingKeys.contains(key) else {
                return
            }
            var keys = tabContentLoadingKeys
            keys.insert(key)
            tabContentLoadingKeys = keys
        } else {
            guard tabContentLoadingKeys.contains(key) else {
                return
            }
            var keys = tabContentLoadingKeys
            keys.remove(key)
            tabContentLoadingKeys = keys
        }
    }

    func isTabContentLoading(_ key: String) -> Bool {
        tabContentLoadingKeys.contains(key)
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

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let target = AppNavigationTarget(deepLinkURL: url) else {
            return false
        }

        navigate(to: target)
        return true
    }

    func clearPendingNavigation() {
        pendingNavigationTarget = nil
        pendingHighlightedDiscoverUserID = nil
        pendingHighlightedSearchID = nil
        pendingHighlightedGameRequestID = nil
    }

    @discardableResult
    func completeGuestOnboarding(_ draft: GuestOnboardingDraft) async -> Bool {
        guard draft.hasRequiredOnboardingFields else {
            errorMessage = L10n.string("Enter your name, an age from 18 to 100, a sport, and a city.", "Укажи имя, возраст от 18 до 100, вид спорта и город.")
            return false
        }
        var completedDraft = draft
        completedDraft.onboardingCompleted = true
        updateGuestDraft(completedDraft)
        guard let user = currentUser else { return true }
        guard !user.isOnboardingComplete else { return true }
        let saved = await saveProfile(makeProfileFromGuestDraft(user))
        if saved { resetGuestDraft() }
        return saved
    }

    private func prepareOnboardingDraft(for user: UserProfile) {
        guard !user.isOnboardingComplete else { return }
        var draft = guestDraft
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            draft.name = user.name ?? draft.name
        }
        if !(18 ... 100).contains(draft.age) { draft.age = user.age ?? draft.age }
        if draft.gender == nil { draft.gender = user.gender }
        if draft.preferredSports.isEmpty {
            draft.preferredSports = user.preferredSports
            draft.sportLevels = user.sportLevels
            draft.preferredPlayFormat = user.preferredPlayFormat
            draft.preferredSurface = user.preferredSurface
        }
        if draft.availableDays.isEmpty && draft.availableTimeRanges.isEmpty && draft.availabilityByDay.isEmpty {
            draft.availableDays = user.availableDays
            draft.availableTimeRanges = user.availableTimeRanges
            draft.availabilityByDay = user.availabilityByDay
        }
        if !draft.hasSelectedCity {
            draft.city = user.location?.coverage.legacyCity ?? user.location?.city ?? user.city ?? draft.city
            draft.location = user.location
            draft.locationSource = user.locationSource
            draft.district = user.district
            draft.preferredDistricts = user.preferredDistricts
        }
        draft.showOnMap = OnboardingMapVisibility.resolved(stored: user.showOnMap, draft: draft.showOnMap, completed: user.isOnboardingComplete)
        draft.onboardingCompleted = false
        updateGuestDraft(draft)
    }

    private func makeProfileFromGuestDraft(_ user: UserProfile) -> UserProfile {
        var profile = user
        profile.name = guestDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.age = guestDraft.age
        profile.gender = guestDraft.gender
        profile.city = guestDraft.location?.coverage.legacyCity ?? guestDraft.location?.city ?? guestDraft.city
        profile.location = guestDraft.location
        profile.coverage = guestDraft.location?.coverage ?? .unavailable
        profile.locationSource = guestDraft.locationSource
        profile.district = guestDraft.preferredDistricts.first ?? guestDraft.district
        profile.preferredDistricts = guestDraft.preferredDistricts
        profile.tennisLevel = guestDraft.sportLevels[guestDraft.preferredSports.first?.rawValue ?? ""] ?? 5
        profile.preferredSports = guestDraft.preferredSports
        profile.sportLevels = guestDraft.sportLevels
        profile.preferredPlayFormat = guestDraft.preferredPlayFormat
        profile.preferredSurface = guestDraft.preferredSurface
        profile.availableDays = guestDraft.availableDays
        profile.availableTimeRanges = guestDraft.availableTimeRanges
        profile.availabilityByDay = guestDraft.availabilityByDay
        profile.isLookingForGame = guestDraft.isLookingForGame
        profile.showOnMap = OnboardingMapVisibility.resolved(stored: user.showOnMap, draft: guestDraft.showOnMap, completed: user.isOnboardingComplete)
        profile.searchRadiusKm = guestDraft.searchRadiusKm
        profile.onboardingCompleted = true
        return profile
    }

}

/// Предзаполнение формы создания поиска из пуша «сходить на тренировку».
/// День недели превращается в окно «сегодня/завтра», потому что в приложении
/// композер умеет только срочные поиски (`SearchType.userVisibleCases == [.hot]`).
struct CreateSearchPrefill: Equatable {
    let sport: Sport?
    let hotWindow: HotWindow?
    let hotStartTime: String?

    init(sport: Sport?, day: String?, timeRange: String?) {
        self.sport = sport
        self.hotWindow = Self.window(for: day)
        self.hotStartTime = timeRange.flatMap(TimeRange.init(rawValue:)).map(Self.startTime(for:))
    }

    private static func window(for day: String?) -> HotWindow? {
        guard let day, let target = DayOfWeek(rawValue: day) else {
            return nil
        }

        let calendar = Calendar.current
        let windows: [HotWindow] = [.today, .tomorrow, .dayAfterTomorrow]

        for (offset, window) in windows.enumerated() {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: Date()),
                  weekday(from: calendar.component(.weekday, from: candidate)) == target else {
                continue
            }
            return window
        }

        return nil
    }

    /// `Calendar.weekday` считает с воскресенья (1), `DayOfWeek` — с понедельника.
    private static func weekday(from calendarWeekday: Int) -> DayOfWeek? {
        let order: [DayOfWeek] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard order.indices.contains(calendarWeekday - 1) else {
            return nil
        }
        return order[calendarWeekday - 1]
    }

    private static func startTime(for range: TimeRange) -> String {
        switch range {
        case .morning: return "09:00"
        case .day: return "14:00"
        case .evening: return "19:00"
        }
    }
}

enum AppNavigationTarget: Equatable {
    case discover(DiscoverTab, highlightedUserID: String? = nil, highlightedSearchID: String? = nil, highlightedGameRequestID: String? = nil)
    case matches
    case searches
    case searchLobby(String)
    case createSearch(CreateSearchPrefill)
    case courts(sport: Sport?)
    case chat(String)
    case profile
}

extension AppNavigationTarget {
    init?(deepLinkURL url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.port == nil else {
            return nil
        }

        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()

        switch scheme {
        case "https":
            guard host == "sportsearch.shop",
                  let pathSegments = Self.validDeepLinkPathSegments(components.percentEncodedPath) else {
                return nil
            }

            if pathSegments.count == 2, pathSegments[0] == "users" {
                self = .discover(.swipe, highlightedUserID: pathSegments[1])
            } else if pathSegments.count == 4,
                      pathSegments[0] == "play",
                      pathSegments[1] == "searches",
                      pathSegments[2] == "invite" {
                self = .discover(.hot, highlightedSearchID: pathSegments[3])
            } else {
                return nil
            }

        case "sportsearch":
            guard let host else {
                return nil
            }

            let pathSegments: [String]
            if components.percentEncodedPath.isEmpty {
                pathSegments = []
            } else if let parsedSegments = Self.validDeepLinkPathSegments(components.percentEncodedPath) {
                pathSegments = parsedSegments
            } else {
                return nil
            }

            switch host {
            case "upcoming" where pathSegments.isEmpty:
                self = .discover(.upcoming)
            case "matches" where pathSegments.isEmpty:
                self = .matches
            case "profile" where pathSegments.count == 1:
                self = .discover(.swipe, highlightedUserID: pathSegments[0])
            case "invite" where pathSegments.count == 1:
                self = .discover(.hot, highlightedSearchID: pathSegments[0])
            default:
                return nil
            }

        default:
            return nil
        }
    }

    init?(notificationHref href: String) {
        guard let components = URLComponents(string: href) else {
            return nil
        }

        let path = components.path
        let queryItems = components.queryItems ?? []

        if path.hasPrefix("/inbox/") {
            self = .chat(String(path.dropFirst("/inbox/".count)))
            return
        }

        if path == "/play/searches/new" || path == "/play/searches/new/" {
            self = .createSearch(
                CreateSearchPrefill(
                    sport: queryItems.first(where: { $0.name == "sport" })?.value.flatMap(Sport.init(rawValue:)),
                    day: queryItems.first(where: { $0.name == "day" })?.value,
                    timeRange: queryItems.first(where: { $0.name == "time" })?.value
                )
            )
            return
        }

        if path.hasPrefix("/play/searches/") {
            self = .searchLobby(String(path.dropFirst("/play/searches/".count)))
            return
        }

        if path == "/play/searches" || path.hasPrefix("/searches") {
            self = .searches
            return
        }

        if path.hasPrefix("/play/games/") {
            self = .discover(.upcoming, highlightedGameRequestID: String(path.dropFirst("/play/games/".count)))
            return
        }

        if path.hasPrefix("/discover") {
            let view = queryItems.first(where: { $0.name == "view" })?.value ?? "swipe"
            let highlight = queryItems.first(where: { $0.name == "highlight" })?.value
            switch view {
            case "likes":
                self = .discover(.likes, highlightedUserID: highlight)
            case "hot":
                self = .discover(.hot, highlightedSearchID: highlight)
            case "upcoming":
                self = .discover(.upcoming, highlightedGameRequestID: highlight)
            case "seeking", "regular":
                self = .discover(.seeking, highlightedSearchID: highlight)
            default:
                self = .discover(.swipe, highlightedUserID: highlight)
            }
            return
        }

        if path.hasPrefix("/matches") || path.hasPrefix("/inbox") {
            self = .matches
            return
        }

        if path.hasPrefix("/onboarding") || path.hasPrefix("/profile") || path.hasPrefix("/settings") {
            self = .profile
            return
        }

        return nil
    }

    private static func validDeepLinkPathSegments(_ percentEncodedPath: String) -> [String]? {
        guard percentEncodedPath.first == "/", percentEncodedPath.count > 1 else {
            return nil
        }

        let encodedSegments = percentEncodedPath
            .dropFirst()
            .split(separator: "/", omittingEmptySubsequences: false)

        var segments: [String] = []
        segments.reserveCapacity(encodedSegments.count)

        for encodedSegment in encodedSegments {
            guard !encodedSegment.isEmpty,
                  let segment = String(encodedSegment).removingPercentEncoding,
                  Self.isValidDeepLinkSegment(segment) else {
                return nil
            }
            segments.append(segment)
        }

        return segments
    }

    private static func isValidDeepLinkSegment(_ segment: String) -> Bool {
        guard !segment.isEmpty, segment.utf8.count <= 200 else {
            return false
        }

        return segment.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || byte == 45
                || byte == 95
        }
    }
}

enum AppConfig {
    static let publicWebBaseURL = URL(string: "https://sportsearch.shop")!

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
        publicWebBaseURL
            .appendingPathComponent("play")
            .appendingPathComponent("searches")
            .appendingPathComponent("invite")
            .appendingPathComponent(searchId)
    }

    static func profileURL(userID: String) -> URL {
        publicWebBaseURL
            .appendingPathComponent("users")
            .appendingPathComponent(userID)
    }
}

func resolveAppRemoteURL(_ path: String?) -> URL? {
    guard let path else {
        return nil
    }

    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else {
        return nil
    }

    if trimmedPath.contains("://") {
        return URL(string: trimmedPath)
    }

    guard let baseURL = AppConfig.apiBaseURL else {
        return nil
    }

    let relativePath = trimmedPath.hasPrefix("/") ? String(trimmedPath.dropFirst()) : trimmedPath
    return baseURL.appendingPathComponent(relativePath)
}

private struct GuestDraftStore {
    private let key = "ios.guest-onboarding-draft.v1"
    private let defaults = UserDefaults.standard

    func load() -> GuestOnboardingDraft {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }

        let decoder = JSONDecoder()
        var draft = (try? decoder.decode(GuestOnboardingDraft.self, from: data)) ?? .default
        if !draft.onboardingCompleted && draft.age == 28 {
            draft.age = 0
        }
        return draft
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
            case .invalidResponse, .invalidPayload:
                return true
            case .server:
                return apiError.isInternalServerMessage
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
