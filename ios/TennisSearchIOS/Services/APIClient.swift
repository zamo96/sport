import Foundation

enum APIError: LocalizedError {
    private static let genericServerMessage = "Сервис временно отвечает нестабильно. Попробуй ещё раз через пару секунд."

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
            return Self.sanitizedServerMessage(message)
        case .invalidPayload(let message):
            return message
        }
    }

    var isInternalServerMessage: Bool {
        guard case .server(let message) = self else {
            return false
        }
        return Self.isInternalServerMessage(message)
    }

    private static func sanitizedServerMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return genericServerMessage
        }
        return isInternalServerMessage(trimmed) ? genericServerMessage : trimmed
    }

    private static func isInternalServerMessage(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return true
        }

        let internalMarkers = [
            "<!doctype",
            "<html",
            "text/html",
            "body:",
            "http 500",
            "http 502",
            "http 503",
            "http 504",
            "prisma.",
            "prismaclient",
            "invalid `prisma",
            "unique constraint failed",
            "foreign key constraint",
            "constraint failed",
            "next-hide-fouc",
            "stack trace"
        ]

        return internalMarkers.contains { normalized.contains($0) }
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

    private lazy var streamSession: URLSession = {
        let streamConfiguration = URLSessionConfiguration.default
        streamConfiguration.httpCookieAcceptPolicy = .always
        streamConfiguration.httpShouldSetCookies = true
        streamConfiguration.httpCookieStorage = .shared
        streamConfiguration.timeoutIntervalForRequest = 45
        streamConfiguration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return URLSession(configuration: streamConfiguration, delegate: self, delegateQueue: nil)
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

    func download(path: String) async throws -> Data {
        let request: URLRequest
        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            request = URLRequest(url: absoluteURL)
        } else {
            let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            request = makeRequest(path: relativePath, method: "GET", queryItems: [])
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.server("HTTP \(httpResponse.statusCode)")
        }
        return data
    }

    func realtimeEvents(lastEventId: String?) -> AsyncThrowingStream<RealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = makeRequest(path: "realtime", method: "GET", queryItems: [])
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 45
                    if let lastEventId, !lastEventId.isEmpty {
                        request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
                    }

                    let (bytes, response) = try await streamSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }
                    guard (200 ... 299).contains(httpResponse.statusCode) else {
                        throw APIError.server("Realtime HTTP \(httpResponse.statusCode)")
                    }

                    var eventId: String?
                    var eventName: String?
                    var dataLines: [String] = []

                    func flushEvent() {
                        guard !dataLines.isEmpty else {
                            eventId = nil
                            eventName = nil
                            return
                        }

                        let dataText = dataLines.joined(separator: "\n")
                        if var decoded = try? decoder.decode(RealtimeEvent.self, from: Data(dataText.utf8)) {
                            decoded.id = decoded.id ?? eventId
                            continuation.yield(decoded)
                        } else if let eventName {
                            let fallback = RealtimeEvent(
                                id: eventId,
                                type: eventName,
                                createdAt: nil,
                                title: nil,
                                body: nil,
                                href: nil,
                                matchId: nil,
                                searchId: nil,
                                messageId: nil,
                                gameRequestId: nil,
                                status: nil
                            )
                            continuation.yield(fallback)
                        }

                        eventId = nil
                        eventName = nil
                        dataLines = []
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }

                        if line.isEmpty {
                            flushEvent()
                            continue
                        }

                        if line.hasPrefix(":") {
                            continue
                        }

                        if line.hasPrefix("id:") {
                            eventId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }

                    flushEvent()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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

    func requestCode(email: String, userAgreementAccepted: Bool, userAgreementVersion: String) async throws -> AuthChallenge {
        let response: AuthRequestEnvelope = try await client.request(
            path: "auth/request-link",
            method: "POST",
            body: AuthRequest(
                email: email,
                userAgreement: UserAgreementAcceptanceRequest(
                    accepted: userAgreementAccepted,
                    version: userAgreementVersion
                )
            )
        )
        return AuthChallenge(message: response.message, debugCode: response.debugCode)
    }

    func verifyCode(email: String, code: String, userAgreementAccepted: Bool, userAgreementVersion: String) async throws -> SessionUser {
        let response: VerifyEnvelope = try await client.request(
            path: "auth/verify",
            method: "POST",
            body: VerifyRequest(
                email: email,
                code: code,
                userAgreement: UserAgreementAcceptanceRequest(
                    accepted: userAgreementAccepted,
                    version: userAgreementVersion
                )
            )
        )
        client.setSessionToken(response.sessionToken)
        return response.user
    }

    func signInWithApple(identityToken: String, email: String?, givenName: String?, familyName: String?, userAgreementAccepted: Bool, userAgreementVersion: String) async throws -> SessionUser {
        let response: VerifyEnvelope = try await client.request(
            path: "auth/apple",
            method: "POST",
            body: AppleAuthRequest(
                identityToken: identityToken,
                email: email,
                givenName: givenName,
                familyName: familyName,
                userAgreement: UserAgreementAcceptanceRequest(
                    accepted: userAgreementAccepted,
                    version: userAgreementVersion
                )
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

    func uploadProfileMedia(data: Data, fileName: String, mimeType: String) async throws -> ProfileMediaUploadResult {
        try await client.uploadMultipart(
            path: "uploads/profile-media",
            fieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
    }

    func removeProfileMedia(mediaUrl: String) async throws -> ProfileMediaUploadResult {
        try await client.request(
            path: "uploads/profile-media",
            method: "DELETE",
            body: RemoveProfileMediaRequest(mediaUrl: mediaUrl)
        )
    }

    func uploadChatMedia(data: Data, fileName: String, mimeType: String) async throws -> ChatMediaAttachment {
        let response: ChatMediaUploadEnvelope = try await client.uploadMultipart(
            path: "uploads/chat-media",
            fieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        return response.asset
    }

    func fetchChatMedia(path: String) async throws -> Data {
        try await client.download(path: path)
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

    func reportUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext) async throws -> UserSafetyReport {
        let response: UserSafetyReportEnvelope = try await client.request(
            path: "users/\(userId)/report",
            method: "POST",
            body: UserSafetyRequest(reason: reason.rawValue, details: details, context: context)
        )
        return response.report
    }

    func blockUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext) async throws -> UserSafetyReport {
        let response: UserSafetyReportEnvelope = try await client.request(
            path: "users/\(userId)/block",
            method: "POST",
            body: UserSafetyRequest(reason: reason.rawValue, details: details, context: context)
        )
        return response.report
    }

    func fetchMatches() async throws -> [MatchSummary] {
        let response: MatchesEnvelope = try await client.request(path: "matches")
        return response.matches
    }

    func ensureMatch(userId: String) async throws -> MatchSummary {
        let response: MatchEnvelope = try await client.request(
            path: "matches",
            method: "POST",
            body: CreateMatchRequest(userId: userId)
        )
        return response.match
    }

    func fetchMyGameRequests() async throws -> [MatchGameRequest] {
        let response: GameRequestsEnvelope = try await client.request(path: "game-requests/my")
        return response.gameRequests
    }

    func fetchMessages(matchId: String) async throws -> [ChatMessage] {
        let response: MessagesEnvelope = try await client.request(path: "matches/\(matchId)/messages")
        return response.messages
    }

    func sendMessage(matchId: String, text: String, attachmentIds: [String]) async throws -> ChatMessage {
        let response: SendMessageEnvelope = try await client.request(
            path: "matches/\(matchId)/messages",
            method: "POST",
            body: SendMessageRequest(text: text, attachmentIds: attachmentIds)
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

    func uploadGameReportPhoto(gameRequestId: String, data: Data, fileName: String, mimeType: String) async throws -> String {
        let response: GameReportPhotoUploadEnvelope = try await client.uploadMultipart(
            path: "uploads/game-reports/\(gameRequestId)",
            fieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        return response.photoUrl
    }

    func createGameReport(gameRequestId: String, photoUrls: [String], comment: String, visibility: String) async throws -> MatchGameRequest {
        let response: GameRequestEnvelope = try await client.request(
            path: "game-requests/\(gameRequestId)/report",
            method: "POST",
            body: CreateGameReportRequest(photoUrls: photoUrls, comment: comment, visibility: visibility)
        )
        return response.gameRequest
    }

    func updateGameReportConfirmation(gameRequestId: String, status: String) async throws -> MatchGameRequest {
        let response: GameRequestEnvelope = try await client.request(
            path: "game-requests/\(gameRequestId)/report/confirmation",
            method: "PATCH",
            body: UpdateGameReportConfirmationRequest(status: status)
        )
        return response.gameRequest
    }

    func fetchPersonalActivities() async throws -> [PersonalActivity] {
        let response: PersonalActivitiesEnvelope = try await client.request(path: "personal-activities")
        return response.personalActivities
    }

    func createPersonalActivity(_ draft: PersonalActivityDraft) async throws -> PersonalActivity {
        let response: PersonalActivityEnvelope = try await client.request(
            path: "personal-activities",
            method: "POST",
            body: CreatePersonalActivityRequest(draft: draft)
        )
        return response.personalActivity
    }

    func updatePersonalActivity(activityId: String, draft: PersonalActivityUpdateDraft) async throws -> PersonalActivity {
        let response: PersonalActivityEnvelope = try await client.request(
            path: "personal-activities/\(activityId)",
            method: "PATCH",
            body: UpdatePersonalActivityRequest(draft: draft)
        )
        return response.personalActivity
    }

    func uploadPersonalActivityPhoto(activityId: String, data: Data, fileName: String, mimeType: String) async throws -> String {
        let response: PersonalActivityPhotoUploadEnvelope = try await client.uploadMultipart(
            path: "uploads/personal-activities/\(activityId)",
            fieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        return response.photoUrl
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

    func sendSearchLobbyMessage(searchId: String, text: String, attachmentIds: [String]) async throws -> SearchLobbyMessage {
        let response: SearchLobbyMessageEnvelope = try await client.request(
            path: "game-searches/\(searchId)/messages",
            method: "POST",
            body: SendMessageRequest(text: text, attachmentIds: attachmentIds)
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

    func scheduleSearchGame(searchId: String, courtId: String?, scheduledAt: Date, durationMinutes: Int) async throws -> SearchGameScheduleResult {
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

    func simulateRegularSearchActivity(searchId: String) async throws -> SearchSimulationResult {
        try await client.request(path: "game-searches/\(searchId)/simulate", method: "POST", body: EmptyRequest())
    }

    func fetchCourts(city: String?) async throws -> [Court] {
        let normalizedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryItems = normalizedCity?.isEmpty == false
            ? [URLQueryItem(name: "city", value: normalizedCity)]
            : []
        let response: CourtsEnvelope = try await client.request(
            path: "courts",
            queryItems: queryItems
        )
        return response.courts
    }

    func fetchCourt(courtId: String) async throws -> Court {
        let response: CourtEnvelope = try await client.request(path: "courts/\(courtId)")
        return response.court
    }

    func fetchAddressSuggestions(query: String, city: String?) async throws -> [AddressSuggestion] {
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let city, !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "city", value: city))
        }

        let response: AddressSuggestionsEnvelope = try await client.request(
            path: "addresses/suggest",
            queryItems: queryItems
        )
        return response.suggestions
    }

    func setCourtMembership(courtId: String, isMember: Bool) async throws -> Court {
        let response: CourtEnvelope = try await client.request(
            path: "courts/\(courtId)/membership",
            method: "POST",
            body: CourtMembershipRequest(isMember: isMember)
        )
        return response.court
    }

    func fetchNotifications() async throws -> [AppNotification] {
        let response: NotificationsEnvelope = try await client.request(path: "activity/notifications")
        return response.notifications
    }

    func fetchActivitySummary() async throws -> ActivitySummary {
        let response: ActivitySummary = try await client.request(path: "activity/summary")
        return response
    }

    func realtimeEvents(lastEventId: String?) -> AsyncThrowingStream<RealtimeEvent, Error> {
        client.realtimeEvents(lastEventId: lastEventId)
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

    func setActiveChat(matchId: String?, gameRequestId: String?, isActive: Bool) async throws {
        let _: SuccessEnvelope = try await client.request(
            path: "activity/active-chat",
            method: "POST",
            body: ActiveChatRequest(matchId: matchId, gameRequestId: gameRequestId, searchId: nil, isActive: isActive)
        )
    }

    func setActiveSearchLobby(searchId: String, isActive: Bool) async throws {
        let _: SuccessEnvelope = try await client.request(
            path: "activity/active-chat",
            method: "POST",
            body: ActiveChatRequest(matchId: nil, gameRequestId: nil, searchId: searchId, isActive: isActive)
        )
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
    let userAgreement: UserAgreementAcceptanceRequest
}

private struct VerifyRequest: Encodable {
    let email: String
    let code: String
    let userAgreement: UserAgreementAcceptanceRequest
}

private struct AppleAuthRequest: Encodable {
    let identityToken: String
    let email: String?
    let givenName: String?
    let familyName: String?
    let userAgreement: UserAgreementAcceptanceRequest
}

private struct UserAgreementAcceptanceRequest: Encodable {
    let accepted: Bool
    let version: String
}

private struct SwipeRequest: Encodable {
    let toUserId: String
    let action: String
}

private struct SendMessageRequest: Encodable {
    let text: String
    let attachmentIds: [String]
}

private struct CreateGameRequestRequest: Encodable {
    let matchId: String
    let proposedCourtId: String?
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
    let scheduledCourtId: String?
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
    private let includesDraftFields: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case outcome
        case proposedCourtId
        case proposedDatetime
        case durationMinutes
        case levelRangeMin
        case levelRangeMax
        case sport
        case format
        case comment
    }

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
        includesDraftFields = false
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
        includesDraftFields = false
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
        includesDraftFields = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        if includesDraftFields {
            if let proposedCourtId {
                try container.encode(proposedCourtId, forKey: .proposedCourtId)
            } else {
                try container.encodeNil(forKey: .proposedCourtId)
            }
            try container.encodeIfPresent(proposedDatetime, forKey: .proposedDatetime)
            try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
            try container.encodeIfPresent(levelRangeMin, forKey: .levelRangeMin)
            try container.encodeIfPresent(levelRangeMax, forKey: .levelRangeMax)
            try container.encodeIfPresent(sport, forKey: .sport)
            try container.encodeIfPresent(format, forKey: .format)
            try container.encodeIfPresent(comment, forKey: .comment)
        }
    }
}

private struct CreateGameReportRequest: Encodable {
    let photoUrls: [String]
    let comment: String
    let visibility: String
}

private struct UpdateGameReportConfirmationRequest: Encodable {
    let status: String
}

private struct CreatePersonalActivityRequest: Encodable {
    let courtId: String
    let sport: String
    let scheduledAt: String
    let durationMinutes: Int?
    let comment: String

    init(draft: PersonalActivityDraft) {
        courtId = draft.courtId
        sport = draft.sport.rawValue
        scheduledAt = draft.scheduledAt.serverISOString()
        durationMinutes = draft.durationMinutes
        comment = draft.comment
    }
}

private struct UpdatePersonalActivityRequest: Encodable {
    let scheduledAt: String?
    let durationMinutes: Int?
    let comment: String?
    let status: String?
    let reportComment: String?
    let photoUrls: [String]?

    init(draft: PersonalActivityUpdateDraft) {
        scheduledAt = draft.scheduledAt?.serverISOString()
        durationMinutes = draft.durationMinutes
        comment = draft.comment
        status = draft.status
        reportComment = draft.reportComment
        photoUrls = draft.photoUrls
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
    let profilePhotoUrls: [String]
    let profileVideoUrls: [String]
    let tennisLevel: Int
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
        profilePhotoUrls = profile.profilePhotoUrls
        profileVideoUrls = profile.profileVideoUrls
        let primarySportLevel = profile.preferredSports.first
            .flatMap { profile.sportLevels[$0.rawValue] }
        tennisLevel = Self.normalizedLevel(primarySportLevel ?? profile.tennisLevel ?? 5)
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

    private static func normalizedLevel(_ value: Int) -> Int {
        min(max(value, 1), 10)
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

private struct MatchEnvelope: Decodable {
    let match: MatchSummary
}

private struct CreateMatchRequest: Encodable {
    let userId: String
}

private struct GameRequestsEnvelope: Decodable {
    let gameRequests: [MatchGameRequest]
}

private struct MessagesEnvelope: Decodable {
    let messages: [ChatMessage]
}

private struct ChatMediaUploadEnvelope: Decodable {
    let asset: ChatMediaAttachment
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

private struct GameReportPhotoUploadEnvelope: Decodable {
    let photoUrl: String
}

private struct PersonalActivitiesEnvelope: Decodable {
    let personalActivities: [PersonalActivity]
}

private struct PersonalActivityEnvelope: Decodable {
    let personalActivity: PersonalActivity
}

private struct PersonalActivityPhotoUploadEnvelope: Decodable {
    let photoUrl: String
}

private struct SwipeEnvelope: Decodable {
    let match: MatchReference?
}

private struct UserSafetyRequest: Encodable {
    let reason: String
    let details: String?
    let context: UserSafetyContext
}

private struct UserSafetyReportEnvelope: Decodable {
    let report: UserSafetyReport
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

private struct CourtEnvelope: Decodable {
    let court: Court
}

private struct AddressSuggestionsEnvelope: Decodable {
    let suggestions: [AddressSuggestion]
}

private struct CourtMembershipRequest: Encodable {
    let isMember: Bool
}

private struct NotificationsEnvelope: Decodable {
    let notifications: [AppNotification]
}

private struct SuccessEnvelope: Decodable {
    let success: Bool?
}

private struct EmptyRequest: Encodable {}

private struct RemoveProfileMediaRequest: Encodable {
    let mediaUrl: String
}

private struct ActiveChatRequest: Encodable {
    let matchId: String?
    let gameRequestId: String?
    let searchId: String?
    let isActive: Bool
}

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
