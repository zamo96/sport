package shop.sportsearch.app.data

import kotlinx.coroutines.flow.Flow
import shop.sportsearch.app.core.*

/**
 * 1:1 port of `protocol TennisRepository` in
 * ios/TennisSearchIOS/Services/TennisRepository.swift.
 */
interface TennisRepository {
    suspend fun requestCode(email: String, userAgreementAccepted: Boolean, userAgreementVersion: String): AuthChallenge

    suspend fun verifyCode(
        email: String,
        code: String,
        userAgreementAccepted: Boolean,
        userAgreementVersion: String,
        showOnMap: Boolean? = null,
    ): SessionUser

    /**
     * The iOS build signs in with Apple. Google Sign-In is the Android
     * equivalent and needs its own backend route, so it is not wired up here;
     * email + OTP is the shared path both clients already support.
     */
    fun clearAuthSession()

    suspend fun fetchCurrentUser(): UserProfile
    suspend fun updateProfile(profile: UserProfile): UserProfile
    suspend fun updateLocaleOverride(locale: String?): String?
    suspend fun fetchLocationCountries(query: String?): List<GeoCountry>
    suspend fun fetchLocationCities(countryCode: String, query: String, limit: Int = 20): List<GeoPlace>
    suspend fun reverseGeocodeLocation(latitude: Double, longitude: Double): GeoPlace
    suspend fun deleteAccount()

    suspend fun uploadAvatar(bytes: ByteArray, fileName: String, mimeType: String): String
    suspend fun uploadProfileMedia(bytes: ByteArray, fileName: String, mimeType: String): ProfileMediaUploadResult
    suspend fun removeProfileMedia(mediaUrl: String): ProfileMediaUploadResult
    suspend fun uploadChatMedia(bytes: ByteArray, fileName: String, mimeType: String): ChatMediaAttachment
    suspend fun fetchChatMedia(path: String): ByteArray

    suspend fun fetchDiscoverUsers(view: DiscoverTab, sport: Sport? = null): List<DiscoverUser>
    suspend fun fetchGuestDiscoverUsers(draft: GuestOnboardingDraft, view: DiscoverTab, sport: Sport? = null): List<DiscoverUser>
    suspend fun swipe(userId: String, action: SwipeAction): String?
    suspend fun reportUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext): UserSafetyReport
    suspend fun blockUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext): UserSafetyReport

    suspend fun fetchMatches(): List<MatchSummary>
    suspend fun ensureMatch(userId: String): MatchSummary
    suspend fun fetchMyGameRequests(): List<MatchGameRequest>
    suspend fun acknowledgeChatMessages(matchId: String?, searchId: String?, messageIds: List<String>, status: String)
    suspend fun fetchMessages(matchId: String): List<ChatMessage>
    suspend fun sendMessage(matchId: String, text: String, attachmentIds: List<String> = emptyList()): ChatMessage

    suspend fun createGameRequest(matchId: String, draft: GameProposalDraft): MatchGameRequest
    suspend fun updateGameRequest(gameRequestId: String, draft: GameProposalDraft): MatchGameRequest
    suspend fun shareGameRequest(gameRequestId: String, matchIds: List<String>): List<MatchGameRequest>
    suspend fun updateGameRequestStatus(gameRequestId: String, status: String): MatchGameRequest
    suspend fun updateGameRequestOutcome(gameRequestId: String, outcome: String): MatchGameRequest
    suspend fun uploadGameReportPhoto(gameRequestId: String, bytes: ByteArray, fileName: String, mimeType: String): String
    suspend fun createGameReport(gameRequestId: String, photoUrls: List<String>, comment: String, visibility: String): MatchGameRequest
    suspend fun updateGameReportConfirmation(gameRequestId: String, status: String): MatchGameRequest

    suspend fun fetchPersonalActivities(): List<PersonalActivity>
    suspend fun createPersonalActivity(draft: PersonalActivityDraft): PersonalActivity
    suspend fun updatePersonalActivity(activityId: String, draft: PersonalActivityUpdateDraft): PersonalActivity
    suspend fun uploadPersonalActivityPhoto(activityId: String, bytes: ByteArray, fileName: String, mimeType: String): String

    suspend fun fetchSearches(): List<GameSearch>
    suspend fun createSearch(draft: SearchDraft): GameSearch
    suspend fun updateSearch(searchId: String, draft: SearchDraft): GameSearch
    suspend fun setSearchActive(searchId: String, isActive: Boolean): GameSearch
    suspend fun fetchSearchLobby(searchId: String): SearchLobbySummary
    suspend fun sendSearchLobbyMessage(searchId: String, text: String, attachmentIds: List<String> = emptyList()): SearchLobbyMessage
    suspend fun createSearchSlotProposal(searchId: String, options: List<SearchSlotProposalDraftOption>, comment: String?): SearchSlotProposalSummary
    suspend fun voteSearchSlotProposal(searchId: String, proposalId: String, optionIds: List<String>): SearchSlotProposalSummary
    suspend fun scheduleSearchGame(searchId: String, courtId: String?, scheduledAt: java.time.Instant, durationMinutes: Int): SearchGameScheduleResult

    suspend fun fetchRegularPair(regularPairId: String): RegularPairSummary
    suspend fun updateRegularPairOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: java.time.Instant?,
        proposedCourtId: String?,
    ): RegularPairOccurrence

    suspend fun respondToSearch(searchId: String, message: String): SearchResponse
    suspend fun withdrawSearchResponse(responseId: String): SearchResponse
    suspend fun updateSearchResponseStatus(responseId: String, status: String): SearchResponseUpdateResult
    suspend fun simulateRegularSearchActivity(searchId: String): SearchSimulationResult

    suspend fun fetchCourts(city: String? = null, locationPlaceId: String? = null, sport: Sport? = null): List<Court>
    suspend fun fetchCourt(courtId: String): Court
    suspend fun fetchAddressSuggestions(query: String, city: String?): List<AddressSuggestion>
    suspend fun setCourtMembership(courtId: String, isMember: Boolean): Court

    suspend fun fetchNotifications(): List<AppNotification>
    suspend fun fetchActivitySummary(): ActivitySummary
    fun realtimeEvents(lastEventId: String?): Flow<RealtimeEvent>
    suspend fun fetchAppStats(): AppStats
    suspend fun markInboxSeen()
    suspend fun markNotificationsSeen()
    suspend fun setActiveChat(matchId: String?, gameRequestId: String?, isActive: Boolean)
    suspend fun setActiveSearchLobby(searchId: String, isActive: Boolean)

    suspend fun fetchEmptyDeckContent(city: String? = null, locationPlaceId: String? = null, sports: List<Sport>? = null): EmptyDeckContent
    suspend fun fetchInviteSummary(): InviteSummary

    /** `registerPushDevice` on iOS talks to APNs; Android registers an FCM token. */
    suspend fun registerPushDevice(
        token: String,
        environment: String,
        bundleId: String,
        deviceName: String?,
        locale: String?,
    )
}
