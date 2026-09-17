import Foundation

protocol TennisRepository {
    func requestCode(email: String, userAgreementAccepted: Bool, userAgreementVersion: String) async throws -> AuthChallenge
    func verifyCode(email: String, code: String, userAgreementAccepted: Bool, userAgreementVersion: String, showOnMap: Bool?) async throws -> SessionUser
    func signInWithApple(identityToken: String, email: String?, givenName: String?, familyName: String?, userAgreementAccepted: Bool, userAgreementVersion: String, showOnMap: Bool?) async throws -> SessionUser
    func clearAuthSession()
    func fetchCurrentUser() async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile
    func updateLocaleOverride(_ locale: String?) async throws -> String?
    func fetchLocationCountries(query: String?) async throws -> [GeoCountry]
    func fetchLocationCities(countryCode: String, query: String, limit: Int) async throws -> [GeoPlace]
    func reverseGeocodeLocation(latitude: Double, longitude: Double) async throws -> GeoPlace
    func deleteAccount() async throws
    func uploadAvatar(data: Data, fileName: String, mimeType: String) async throws -> String
    func uploadProfileMedia(data: Data, fileName: String, mimeType: String) async throws -> ProfileMediaUploadResult
    func removeProfileMedia(mediaUrl: String) async throws -> ProfileMediaUploadResult
    func uploadChatMedia(data: Data, fileName: String, mimeType: String) async throws -> ChatMediaAttachment
    func fetchChatMedia(path: String) async throws -> Data
    func fetchDiscoverUsers(view: DiscoverTab, sport: Sport?) async throws -> [DiscoverUser]
    func fetchGuestDiscoverUsers(draft: GuestOnboardingDraft, view: DiscoverTab, sport: Sport?) async throws -> [DiscoverUser]
    func swipe(userId: String, action: SwipeAction) async throws -> String?
    func reportUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext) async throws -> UserSafetyReport
    func blockUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext) async throws -> UserSafetyReport
    func fetchMatches() async throws -> [MatchSummary]
    func ensureMatch(userId: String) async throws -> MatchSummary
    func fetchMyGameRequests() async throws -> [MatchGameRequest]
    func acknowledgeChatMessages(scope: ChatReceiptScope, messageIds: [String], status: String) async throws
    func fetchMessages(matchId: String) async throws -> [ChatMessage]
    func sendMessage(matchId: String, text: String, attachmentIds: [String]) async throws -> ChatMessage
    func createGameRequest(matchId: String, draft: GameProposalDraft) async throws -> MatchGameRequest
    func updateGameRequest(gameRequestId: String, draft: GameProposalDraft) async throws -> MatchGameRequest
    func shareGameRequest(gameRequestId: String, matchIds: [String]) async throws -> [MatchGameRequest]
    func updateGameRequestStatus(gameRequestId: String, status: String) async throws -> MatchGameRequest
    func updateGameRequestOutcome(gameRequestId: String, outcome: String) async throws -> MatchGameRequest
    func uploadGameReportPhoto(gameRequestId: String, data: Data, fileName: String, mimeType: String) async throws -> String
    func createGameReport(gameRequestId: String, photoUrls: [String], comment: String, visibility: String) async throws -> MatchGameRequest
    func updateGameReportConfirmation(gameRequestId: String, status: String) async throws -> MatchGameRequest
    func fetchPersonalActivities() async throws -> [PersonalActivity]
    func createPersonalActivity(_ draft: PersonalActivityDraft) async throws -> PersonalActivity
    func updatePersonalActivity(activityId: String, draft: PersonalActivityUpdateDraft) async throws -> PersonalActivity
    func uploadPersonalActivityPhoto(activityId: String, data: Data, fileName: String, mimeType: String) async throws -> String
    func fetchSearches() async throws -> [GameSearch]
    func createSearch(_ draft: SearchDraft) async throws -> GameSearch
    func updateSearch(searchId: String, draft: SearchDraft) async throws -> GameSearch
    func setSearchActive(searchId: String, isActive: Bool) async throws -> GameSearch
    func fetchSearchLobby(searchId: String) async throws -> SearchLobbySummary
    func sendSearchLobbyMessage(searchId: String, text: String, attachmentIds: [String]) async throws -> SearchLobbyMessage
    func createSearchSlotProposal(searchId: String, options: [SearchSlotProposalDraftOption], comment: String?) async throws -> SearchSlotProposalSummary
    func voteSearchSlotProposal(searchId: String, proposalId: String, optionIds: [String]) async throws -> SearchSlotProposalSummary
    func scheduleSearchGame(searchId: String, courtId: String?, scheduledAt: Date, durationMinutes: Int) async throws -> SearchGameScheduleResult
    func fetchRegularPair(regularPairId: String) async throws -> RegularPairSummary
    func updateRegularPairOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: Date?,
        proposedCourtId: String?
    ) async throws -> RegularPairOccurrence
    func respondToSearch(searchId: String, message: String) async throws -> SearchResponse
    func withdrawSearchResponse(responseId: String) async throws -> SearchResponse
    func updateSearchResponseStatus(responseId: String, status: String) async throws -> SearchResponseUpdateResult
    func simulateRegularSearchActivity(searchId: String) async throws -> SearchSimulationResult
    func fetchCourts(city: String?, locationPlaceId: String?, sport: Sport?) async throws -> [Court]
    func fetchInviteSummary() async throws -> InviteSummary
    func fetchEmptyDeckContent(city: String?, locationPlaceId: String?, sports: [Sport]?) async throws -> EmptyDeckContent
    func fetchCourt(courtId: String) async throws -> Court
    func fetchAddressSuggestions(query: String, city: String?) async throws -> [AddressSuggestion]
    func setCourtMembership(courtId: String, isMember: Bool) async throws -> Court
    func fetchNotifications() async throws -> [AppNotification]
    func fetchActivitySummary() async throws -> ActivitySummary
    func realtimeEvents(lastEventId: String?) -> AsyncThrowingStream<RealtimeEvent, Error>
    func fetchAppStats() async throws -> AppStats
    func markInboxSeen() async throws
    func markNotificationsSeen() async throws
    func setActiveChat(matchId: String?, gameRequestId: String?, isActive: Bool) async throws
    func setActiveSearchLobby(searchId: String, isActive: Bool) async throws
    func registerPushDevice(token: String, environment: APNSEnvironment, bundleId: String, deviceName: String?, locale: String?) async throws
}

extension TennisRepository {
    func verifyCode(email: String, code: String, userAgreementAccepted: Bool, userAgreementVersion: String) async throws -> SessionUser {
        try await verifyCode(email: email, code: code, userAgreementAccepted: userAgreementAccepted, userAgreementVersion: userAgreementVersion, showOnMap: nil)
    }
    func signInWithApple(identityToken: String, email: String?, givenName: String?, familyName: String?, userAgreementAccepted: Bool, userAgreementVersion: String) async throws -> SessionUser {
        try await signInWithApple(identityToken: identityToken, email: email, givenName: givenName, familyName: familyName, userAgreementAccepted: userAgreementAccepted, userAgreementVersion: userAgreementVersion, showOnMap: nil)
    }

    func fetchDiscoverUsers(view: DiscoverTab) async throws -> [DiscoverUser] {
        try await fetchDiscoverUsers(view: view, sport: nil)
    }
    func fetchGuestDiscoverUsers(draft: GuestOnboardingDraft, view: DiscoverTab) async throws -> [DiscoverUser] {
        try await fetchGuestDiscoverUsers(draft: draft, view: view, sport: nil)
    }
    func fetchCourts(city: String? = nil) async throws -> [Court] {
        try await fetchCourts(city: city, locationPlaceId: nil, sport: nil)
    }
    func fetchEmptyDeckContent() async throws -> EmptyDeckContent {
        try await fetchEmptyDeckContent(city: nil, locationPlaceId: nil, sports: nil)
    }
}

struct SearchSlotProposalDraftOption {
    let scheduledAt: Date
    let proposedCourtId: String?
    let durationMinutes: Int?
}

struct ProfileMediaUploadResult: Codable {
    let mediaUrl: String
    let mediaType: String
    let avatarUrl: String?
    let profilePhotoUrls: [String]
    let profileVideoUrls: [String]
}

struct SearchSimulationResult: Codable {
    let createdResponses: Int
    let createdVotes: Int
    let finalizedOptions: Int
    let message: String
}
