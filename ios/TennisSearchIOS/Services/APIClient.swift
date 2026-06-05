import Foundation

enum APIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Не указан API base URL"
        case .invalidResponse:
            return "Некорректный ответ сервера"
        case .server(let message):
            return message
        case .invalidPayload(let message):
            return message
        }
    }
}

final class APIClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private static let sessionTokenKey = "SportSearch.sessionToken"
    private static let appGroupIdentifier = "group.shop.sportsearch.app"

    private let baseURL: URL
    private let configuration: URLSessionConfiguration
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let allowDebugServerTrustOverride: Bool
    private let trustedHost: String?
    private var sessionToken: String?

    private lazy var session: URLSession = {
        URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(baseURL: URL, allowDebugServerTrustOverride: Bool = false) {
        self.baseURL = baseURL
        self.allowDebugServerTrustOverride = allowDebugServerTrustOverride
        trustedHost = baseURL.host
        configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = .shared
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 30
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        sessionToken = UserDefaults.standard.string(forKey: Self.sessionTokenKey)
            ?? UserDefaults(suiteName: Self.appGroupIdentifier)?.string(forKey: Self.sessionTokenKey)
    }

    func setSessionToken(_ token: String?) {
        let normalizedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionToken = normalizedToken?.isEmpty == false ? normalizedToken : nil

        if let sessionToken {
            UserDefaults.standard.set(sessionToken, forKey: Self.sessionTokenKey)
            UserDefaults(suiteName: Self.appGroupIdentifier)?.set(sessionToken, forKey: Self.sessionTokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionTokenKey)
            UserDefaults(suiteName: Self.appGroupIdentifier)?.removeObject(forKey: Self.sessionTokenKey)
        }
    }

    func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Body? = nil
    ) async throws -> Response {
        var request = makeRequest(path: path, method: method, queryItems: queryItems)
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        return try await perform(request)
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await perform(makeRequest(path: path, method: method, queryItems: queryItems))
    }

    func uploadMultipart<Response: Decodable>(
        path: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = makeRequest(path: path, method: "POST", queryItems: [])
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            fieldName: fieldName,
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        return try await perform(request)
    }

    private func makeRequest(path: String, method: String, queryItems: [URLQueryItem]) -> URLRequest {
        let pathURL = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        let url = components?.url ?? pathURL
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        if let sessionToken, !sessionToken.isEmpty {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func multipartBody(
        boundary: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        body.append(Data("--\(boundary)\(lineBreak)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\(lineBreak)".utf8))
        body.append(Data("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)".utf8))
        body.append(data)
        body.append(Data(lineBreak.utf8))
        body.append(Data("--\(boundary)--\(lineBreak)".utf8))

        return body
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if !(200 ... 299).contains(httpResponse.statusCode) {
            let serverError =
                (try? decoder.decode(ErrorEnvelope.self, from: data))?.error ??
                "HTTP \(httpResponse.statusCode). \(debugPayloadSummary(data: data, response: httpResponse))"
            throw APIError.server(serverError)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch let decodingError as DecodingError {
            throw APIError.invalidPayload(
                "Не удалось прочитать JSON ответа. " +
                describe(decodingError: decodingError) +
                ". " +
                debugPayloadSummary(data: data, response: httpResponse)
            )
        } catch {
            throw APIError.invalidPayload(
                "Не удалось обработать ответ сервера. " +
                debugPayloadSummary(data: data, response: httpResponse)
            )
        }
    }

    private func debugPayloadSummary(data: Data, response: HTTPURLResponse) -> String {
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "unknown content type"
        let snippet: String
        if let text = String(data: data.prefix(220), encoding: .utf8) {
            snippet = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            snippet = "<non-UTF8 body>"
        }

        return "HTTP \(response.statusCode), \(contentType). Body: \(snippet)"
    }

    private func describe(decodingError: DecodingError) -> String {
        switch decodingError {
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Corrupted data at \(codingPath(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error"
        }
    }

    private func codingPath(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else {
            return "<root>"
        }

        return path.map(\.stringValue).joined(separator: ".")
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    private func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if
            allowDebugServerTrustOverride,
            trustedHost == nil || challenge.protectionSpace.host == trustedHost,
            let serverTrust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }
}

final class LiveTennisRepository: TennisRepository {
    private let client: APIClient

    init(baseURL: URL, allowDebugServerTrustOverride: Bool = false) {
        client = APIClient(
            baseURL: baseURL,
            allowDebugServerTrustOverride: allowDebugServerTrustOverride
        )
    }

    func requestCode(email: String) async throws -> AuthChallenge {
        let response: AuthRequestEnvelope = try await client.request(
            path: "auth/request-link",
            method: "POST",
            body: AuthRequest(email: email)
        )
        return AuthChallenge(message: response.message, debugCode: response.debugCode)
    }

    func verifyCode(email: String, code: String) async throws -> SessionUser {
        let response: VerifyEnvelope = try await client.request(
            path: "auth/verify",
            method: "POST",
            body: VerifyRequest(email: email, code: code)
        )
        client.setSessionToken(response.sessionToken)
        return response.user
    }

    func signInWithApple(identityToken: String, email: String?, givenName: String?, familyName: String?) async throws -> SessionUser {
        let response: VerifyEnvelope = try await client.request(
            path: "auth/apple",
            method: "POST",
            body: AppleAuthRequest(
                identityToken: identityToken,
                email: email,
                givenName: givenName,
                familyName: familyName
            )
        )
        client.setSessionToken(response.sessionToken)
        return response.user
    }

    func clearAuthSession() {
        client.setSessionToken(nil)
    }

    func fetchCurrentUser() async throws -> UserProfile {
        let response: MeEnvelope = try await client.request(path: "me")
        return response.user
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        let body = UpdateProfileRequest(profile: profile)
        let response: MeEnvelope = try await client.request(path: "me", method: "PATCH", body: body)
        return response.user
    }

    func deleteAccount() async throws {
        let _: SuccessEnvelope = try await client.request(path: "me", method: "DELETE", body: EmptyRequest())
    }

    func uploadAvatar(data: Data, fileName: String, mimeType: String) async throws -> String {
        let response: AvatarUploadEnvelope = try await client.uploadMultipart(
            path: "uploads/avatar",
            fieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        return response.avatarUrl
    }

    func fetchDiscoverUsers(view: DiscoverTab) async throws -> [DiscoverUser] {
        let response: DiscoverEnvelope
        switch view {
        case .likes:
            response = try await client.request(path: "users/discover/likes")
        default:
            let queryItems = view == .swipe ? [] : [URLQueryItem(name: "view", value: view.rawValue)]
            response = try await client.request(path: "users/discover", queryItems: queryItems)
        }
        return response.users
    }

    func fetchGuestDiscoverUsers(draft: GuestOnboardingDraft, view: DiscoverTab) async throws -> [DiscoverUser] {
        let queryView: String
        switch view {
        case .upcoming:
            queryView = "upcoming"
        case .swipe:
            queryView = "swipe"
        case .likes:
            queryView = "likes"
        case .seeking:
            queryView = "seeking"
        case .hot:
            queryView = "hot"
        }

        let response: DiscoverEnvelope = try await client.request(
            path: "users/discover/guest",
            method: "POST",
            body: GuestDiscoverRequest(
                draft: draft,
                filters: GuestDiscoverFilters(view: queryView == "swipe" ? nil : queryView)
            )
        )
        return response.users
    }

    func swipe(userId: String, action: SwipeAction) async throws -> String? {
        let response: SwipeEnvelope = try await client.request(
            path: "swipes",
            method: "POST",
            body: SwipeRequest(toUserId: userId, action: action.rawValue)
        )
        return response.match?.id
    }

    func fetchMatches() async throws -> [MatchSummary] {
        let response: MatchesEnvelope = try await client.request(path: "matches")
        return response.matches
    }

    func fetchMyGameRequests() async throws -> [MatchGameRequest] {
        let response: GameRequestsEnvelope = try await client.request(path: "game-requests/my")
        return response.gameRequests
    }

    func fetchMessages(matchId: String) async throws -> [ChatMessage] {
        let response: MessagesEnvelope = try await client.request(path: "matches/\(matchId)/messages")
        return response.messages
    }

    func sendMessage(matchId: String, text: String) async throws -> ChatMessage {
        let response: SendMessageEnvelope = try await client.request(
            path: "matches/\(matchId)/messages",
            method: "POST",
            body: SendMessageRequest(text: text)
        )
        return response.message
    }

    func createGameRequest(matchId: String, draft: GameProposalDraft) async throws -> MatchGameRequest {
        let response: CreateGameRequestEnvelope = try await client.request(
            path: "game-requests",
            method: "POST",
            body: CreateGameRequestRequest(matchId: matchId, draft: draft)
        )
        return response.gameRequest
    }

    func updateGameRequest(gameRequestId: String, draft: GameProposalDraft) async throws -> MatchGameRequest {
        let response: GameRequestEnvelope = try await client.request(
            path: "game-requests/\(gameRequestId)",
            method: "PATCH",
            body: UpdateGameRequestRequest(draft: draft)
        )
        return response.gameRequest
    }

    func shareGameRequest(gameRequestId: String, matchIds: [String]) async throws -> [MatchGameRequest] {
        let response: GameRequestsEnvelope = try await client.request(
            path: "game-requests/\(gameRequestId)/share",
            method: "POST",
            body: ShareGameRequestRequest(matchIds: matchIds)
        )
        return response.gameRequests
    }

    func updateGameRequestStatus(gameRequestId: String, status: String) async throws -> MatchGameRequest {
        let response: GameRequestEnvelope = try await client.request(
            path: "game-requests/\(gameRequestId)",
            method: "PATCH",
            body: UpdateGameRequestRequest(status: status)
        )
        return response.gameRequest
    }

    func updateGameRequestOutcome(gameRequestId: String, outcome: String) async throws -> MatchGameRequest {
        let response: GameRequestEnvelope = try await client.request(
            path: "game-requests/\(gameRequestId)",
            method: "PATCH",
            body: UpdateGameRequestRequest(outcome: outcome)
        )
        return response.gameRequest
    }

    func fetchSearches() async throws -> [GameSearch] {
        let response: SearchesEnvelope = try await client.request(path: "game-searches/my")
        return response.gameSearches
    }

    func createSearch(_ draft: SearchDraft) async throws -> GameSearch {
        let response: CreateSearchEnvelope = try await client.request(
            path: "game-searches",
            method: "POST",
            body: draft
        )
        return response.gameSearch
    }

    func updateSearch(searchId: String, draft: SearchDraft) async throws -> GameSearch {
        let response: CreateSearchEnvelope = try await client.request(
            path: "game-searches/\(searchId)",
            method: "PATCH",
            body: draft
        )
        return response.gameSearch
    }

    func setSearchActive(searchId: String, isActive: Bool) async throws -> GameSearch {
        let response: CreateSearchEnvelope = try await client.request(
            path: "game-searches/\(searchId)",
            method: "PATCH",
            body: UpdateSearchActiveRequest(isActive: isActive)
        )
        return response.gameSearch
    }

    func fetchSearchLobby(searchId: String) async throws -> SearchLobbySummary {
        try await client.request(path: "game-searches/\(searchId)")
    }

    func sendSearchLobbyMessage(searchId: String, text: String) async throws -> SearchLobbyMessage {
        let response: SearchLobbyMessageEnvelope = try await client.request(
            path: "game-searches/\(searchId)/messages",
            method: "POST",
            body: SendMessageRequest(text: text)
        )
        return response.message
    }

    func createSearchSlotProposal(
        searchId: String,
        options: [SearchSlotProposalDraftOption],
        comment: String?
    ) async throws -> SearchSlotProposalSummary {
        let response: SearchSlotProposalEnvelope = try await client.request(
            path: "game-searches/\(searchId)/slot-proposals",
            method: "POST",
            body: CreateSearchSlotProposalRequest(options: options, comment: comment)
        )
        return response.proposal
    }

    func voteSearchSlotProposal(
        searchId: String,
        proposalId: String,
        optionIds: [String]
    ) async throws -> SearchSlotProposalSummary {
        let response: SearchSlotProposalEnvelope = try await client.request(
            path: "game-searches/\(searchId)/slot-proposals/\(proposalId)/votes",
            method: "PUT",
            body: VoteSearchSlotProposalRequest(optionIds: optionIds)
        )
        return response.proposal
    }

    func scheduleSearchGame(searchId: String, courtId: String, scheduledAt: Date, durationMinutes: Int) async throws -> SearchGameScheduleResult {
        try await client.request(
            path: "game-searches/\(searchId)",
            method: "PATCH",
            body: ScheduleSearchGameRequest(
                scheduledCourtId: courtId,
                scheduledAt: scheduledAt.serverISOString(),
                scheduledDurationMinutes: durationMinutes
            )
        )
    }

    func fetchRegularPair(regularPairId: String) async throws -> RegularPairSummary {
        let response: RegularPairEnvelope = try await client.request(path: "regular-pairs/\(regularPairId)")
        return response.regularPair
    }

    func updateRegularPairOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: Date?,
        proposedCourtId: String?
    ) async throws -> RegularPairOccurrence {
        let response: RegularPairOccurrenceEnvelope = try await client.request(
            path: "regular-pairs/\(regularPairId)/occurrences/\(occurrenceId)",
            method: "PATCH",
            body: UpdateRegularPairOccurrenceRequest(
                status: status,
                scheduledAt: scheduledAt?.serverISOString(),
                proposedCourtId: proposedCourtId
            )
        )
        return response.occurrence
    }

    func respondToSearch(searchId: String, message: String) async throws -> SearchResponse {
        let response: SearchResponseEnvelope = try await client.request(
            path: "game-searches/\(searchId)/respond",
            method: "POST",
            body: SearchResponseRequest(message: message)
        )
        return response.response
    }

    func withdrawSearchResponse(responseId: String) async throws -> SearchResponse {
        let response: SearchResponseEnvelope = try await client.request(
            path: "game-search-responses/\(responseId)",
            method: "PATCH",
            body: UpdateSearchResponseRequest(status: "withdrawn")
        )
        return response.response
    }

    func updateSearchResponseStatus(responseId: String, status: String) async throws -> SearchResponseUpdateResult {
        let response: SearchResponseEnvelope = try await client.request(
            path: "game-search-responses/\(responseId)",
            method: "PATCH",
            body: UpdateSearchResponseRequest(status: status)
        )
        return SearchResponseUpdateResult(
            response: response.response,
            matchId: response.matchId,
            gameRequestId: response.gameRequestId,
            regularPairId: response.regularPairId,
            gameSearch: response.gameSearch
        )
    }

    func fetchCourts() async throws -> [Court] {
        let response: CourtsEnvelope = try await client.request(path: "courts")
        return response.courts
    }

    func fetchNotifications() async throws -> [AppNotification] {
        let response: NotificationsEnvelope = try await client.request(path: "activity/notifications")
        return response.notifications
    }

    func fetchActivitySummary() async throws -> ActivitySummary {
        let response: ActivitySummary = try await client.request(path: "activity/summary")
        return response
    }

    func fetchAppStats() async throws -> AppStats {
        try await client.request(path: "app/stats")
    }

    func markInboxSeen() async throws {
        let _: SuccessEnvelope = try await client.request(path: "activity/inbox-seen", method: "POST", body: EmptyRequest())
    }

    func markNotificationsSeen() async throws {
        let _: SuccessEnvelope = try await client.request(path: "activity/notifications-seen", method: "POST", body: EmptyRequest())
    }

    func registerPushDevice(token: String, environment: APNSEnvironment, bundleId: String, deviceName: String?) async throws {
        let _: RegisterPushDeviceEnvelope = try await client.request(
            path: "devices/apns",
            method: "POST",
            body: RegisterPushDeviceRequest(
                token: token,
                platform: "ios",
                environment: environment.rawValue,
                bundleId: bundleId,
                deviceName: deviceName
            )
        )
    }
}

private struct ErrorEnvelope: Decodable {
    let error: String
}

private struct AuthRequest: Encodable {
    let email: String
}

private struct VerifyRequest: Encodable {
    let email: String
    let code: String
}

private struct AppleAuthRequest: Encodable {
    let identityToken: String
    let email: String?
    let givenName: String?
    let familyName: String?
}

private struct SwipeRequest: Encodable {
    let toUserId: String
    let action: String
}

private struct SendMessageRequest: Encodable {
    let text: String
}

private struct CreateGameRequestRequest: Encodable {
    let matchId: String
    let proposedCourtId: String
    let proposedDatetime: String
    let durationMinutes: Int?
    let levelRangeMin: Int?
    let levelRangeMax: Int?
    let sport: String
    let format: String
    let comment: String

    init(matchId: String, draft: GameProposalDraft) {
        self.matchId = matchId
        proposedCourtId = draft.proposedCourtId
        proposedDatetime = draft.proposedDatetime.serverISOString()
        durationMinutes = draft.durationMinutes
        levelRangeMin = draft.levelRangeMin
        levelRangeMax = draft.levelRangeMax
        sport = draft.sport.rawValue
        format = draft.format.rawValue
        comment = draft.comment
    }
}

private struct ShareGameRequestRequest: Encodable {
    let matchIds: [String]
}

private struct SearchResponseRequest: Encodable {
    let message: String
}

private struct UpdateSearchActiveRequest: Encodable {
    let isActive: Bool
}

private struct ScheduleSearchGameRequest: Encodable {
    let scheduledCourtId: String
    let scheduledAt: String
    let scheduledDurationMinutes: Int
}

private struct CreateSearchSlotProposalRequest: Encodable {
    let comment: String
    let options: [Option]

    struct Option: Encodable {
        let scheduledAt: String
        let proposedCourtId: String?
        let durationMinutes: Int?
    }

    init(options: [SearchSlotProposalDraftOption], comment: String?) {
        self.comment = comment ?? ""
        self.options = options.map {
            Option(
                scheduledAt: $0.scheduledAt.serverISOString(),
                proposedCourtId: $0.proposedCourtId,
                durationMinutes: $0.durationMinutes
            )
        }
    }
}

private struct VoteSearchSlotProposalRequest: Encodable {
    let optionIds: [String]
}

private struct UpdateSearchResponseRequest: Encodable {
    let status: String
}

private struct UpdateRegularPairOccurrenceRequest: Encodable {
    let status: String?
    let scheduledAt: String?
    let proposedCourtId: String?
}

private struct UpdateGameRequestRequest: Encodable {
    let status: String?
    let outcome: String?
    let proposedCourtId: String?
    let proposedDatetime: String?
    let durationMinutes: Int?
    let levelRangeMin: Int?
    let levelRangeMax: Int?
    let sport: String?
    let format: String?
    let comment: String?

    init(status: String) {
        self.status = status
        outcome = nil
        proposedCourtId = nil
        proposedDatetime = nil
        durationMinutes = nil
        levelRangeMin = nil
        levelRangeMax = nil
        sport = nil
        format = nil
        comment = nil
    }

    init(outcome: String) {
        status = nil
        self.outcome = outcome
        proposedCourtId = nil
        proposedDatetime = nil
        durationMinutes = nil
        levelRangeMin = nil
        levelRangeMax = nil
        sport = nil
        format = nil
        comment = nil
    }

    init(draft: GameProposalDraft) {
        status = nil
        outcome = nil
        proposedCourtId = draft.proposedCourtId
        proposedDatetime = draft.proposedDatetime.serverISOString()
        durationMinutes = draft.durationMinutes
        levelRangeMin = draft.levelRangeMin
        levelRangeMax = draft.levelRangeMax
        sport = draft.sport.rawValue
        format = draft.format.rawValue
        comment = draft.comment
    }
}

private struct UpdateProfileRequest: Encodable {
    let name: String?
    let age: Int?
    let gender: String?
    let city: String?
    let district: String?
    let preferredDistricts: [String]
    let bio: String?
    let avatarUrl: String?
    let tennisLevel: Int?
    let preferredSports: [String]
    let sportLevels: [String: Int]
    let preferredPlayFormat: String
    let preferredSurface: String
    let availableDays: [String]
    let availableTimeRanges: [String]
    let availabilityByDay: [String: [String]]
    let searchRadiusKm: Int
    let isLookingForGame: Bool
    let notificationMatches: Bool
    let notificationMessages: Bool
    let notificationGames: Bool
    let notificationSound: Bool

    init(profile: UserProfile) {
        name = profile.name
        age = profile.age
        gender = profile.gender?.rawValue
        city = profile.city
        district = profile.district
        preferredDistricts = profile.preferredDistricts
        bio = profile.bio
        avatarUrl = profile.avatarUrl
        tennisLevel = profile.tennisLevel
        preferredSports = profile.preferredSports.map(\.rawValue)
        sportLevels = profile.sportLevels
        preferredPlayFormat = profile.preferredPlayFormat.rawValue
        preferredSurface = profile.preferredSurface.rawValue
        availableDays = profile.availableDays
        availableTimeRanges = profile.availableTimeRanges
        availabilityByDay = profile.availabilityByDay
        searchRadiusKm = profile.searchRadiusKm
        isLookingForGame = profile.isLookingForGame
        notificationMatches = profile.notificationMatches
        notificationMessages = profile.notificationMessages
        notificationGames = profile.notificationGames
        notificationSound = profile.notificationSound
    }
}

private struct GuestDiscoverRequest: Encodable {
    let draft: GuestDraftPayload
    let filters: GuestDiscoverFilters

    init(draft: GuestOnboardingDraft, filters: GuestDiscoverFilters) {
        self.draft = GuestDraftPayload(draft: draft)
        self.filters = filters
    }
}

private struct GuestDraftPayload: Encodable {
    let name: String
    let age: Int
    let gender: String?
    let city: String
    let district: String?
    let preferredDistricts: [String]
    let preferredSports: [String]
    let sportLevels: [String: Int]
    let preferredPlayFormat: String
    let preferredSurface: String
    let searchRadiusKm: Int
    let isLookingForGame: Bool
    let availableDays: [String]
    let availableTimeRanges: [String]
    let availabilityByDay: [String: [String]]

    init(draft: GuestOnboardingDraft) {
        name = draft.name
        age = draft.age
        gender = draft.gender?.rawValue
        city = draft.city
        district = draft.district
        preferredDistricts = draft.preferredDistricts
        preferredSports = draft.preferredSports.map(\.rawValue)
        sportLevels = draft.sportLevels
        preferredPlayFormat = draft.preferredPlayFormat.rawValue
        preferredSurface = draft.preferredSurface.rawValue
        searchRadiusKm = draft.searchRadiusKm
        isLookingForGame = draft.isLookingForGame
        availableDays = draft.availableDays
        availableTimeRanges = draft.availableTimeRanges
        availabilityByDay = draft.availabilityByDay
    }
}

private struct GuestDiscoverFilters: Encodable {
    let view: String?
}

private struct AuthRequestEnvelope: Decodable {
    let ok: Bool
    let message: String
    let debugCode: String?
}

private struct VerifyEnvelope: Decodable {
    let ok: Bool
    let user: SessionUser
    let sessionToken: String?
}

private struct MeEnvelope: Decodable {
    let user: UserProfile
}

private struct AvatarUploadEnvelope: Decodable {
    let avatarUrl: String
}

private struct DiscoverEnvelope: Decodable {
    let users: [DiscoverUser]
}

private struct MatchesEnvelope: Decodable {
    let matches: [MatchSummary]
}

private struct GameRequestsEnvelope: Decodable {
    let gameRequests: [MatchGameRequest]
}

private struct MessagesEnvelope: Decodable {
    let messages: [ChatMessage]
}

private struct SendMessageEnvelope: Decodable {
    let message: ChatMessage
}

private struct CreateGameRequestEnvelope: Decodable {
    let gameRequest: MatchGameRequest
}

private struct GameRequestEnvelope: Decodable {
    let gameRequest: MatchGameRequest
}

private struct SwipeEnvelope: Decodable {
    let match: MatchReference?
}

private struct MatchReference: Decodable {
    let id: String
}

private struct SearchesEnvelope: Decodable {
    let gameSearches: [GameSearch]
}

private struct CreateSearchEnvelope: Decodable {
    let gameSearch: GameSearch
}

private struct SearchResponseEnvelope: Decodable {
    let response: SearchResponse
    let matchId: String?
    let gameRequestId: String?
    let regularPairId: String?
    let gameSearch: SearchStatusUpdate?
}

private struct SearchLobbyMessageEnvelope: Decodable {
    let message: SearchLobbyMessage
}

private struct SearchSlotProposalEnvelope: Decodable {
    let proposal: SearchSlotProposalSummary
}

private struct RegularPairEnvelope: Decodable {
    let regularPair: RegularPairSummary
}

private struct RegularPairOccurrenceEnvelope: Decodable {
    let occurrence: RegularPairOccurrence
}

private struct CourtsEnvelope: Decodable {
    let courts: [Court]
}

private struct NotificationsEnvelope: Decodable {
    let notifications: [AppNotification]
}

private struct SuccessEnvelope: Decodable {
    let success: Bool?
}

private struct EmptyRequest: Encodable {}

private struct RegisterPushDeviceRequest: Encodable {
    let token: String
    let platform: String
    let environment: String
    let bundleId: String
    let deviceName: String?
}

private struct RegisterPushDeviceEnvelope: Decodable {
    let device: RegisteredPushDevice
}

private struct RegisteredPushDevice: Decodable {
    let id: String
    let token: String
    let environment: String
    let bundleId: String
    let isActive: Bool
}

private extension Date {
    func serverISOString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: self)
    }
}
