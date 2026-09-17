package shop.sportsearch.app.data

import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import shop.sportsearch.app.core.*
import java.time.Instant

/**
 * 1:1 port of `final class LiveTennisRepository`. Every path, method and body
 * key matches the Swift client so the same backend serves both apps.
 */
class LiveTennisRepository(val client: ApiClient) : TennisRepository {

    /**
     * Swift synthesises `Encodable` with `encodeIfPresent`, so a nil field is
     * left out of the JSON entirely - the server's `.optional()` and `.default()`
     * rules are written for that. kotlinx would serialise the same field as an
     * explicit `null`, which those rules reject (`bio` is `optional().default("")`,
     * not nullable, so `"bio": null` came back as
     * `Invalid input: expected string, received null`).
     *
     * Nulls are therefore dropped here, matching iOS. The one payload that has to
     * send a real null - clearing a game request's court, the single
     * `encodeNil` on the iOS side - opts back in with [keepNull].
     */
    private fun body(build: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit): String {
        val raw = buildJsonObject(build)
        val pruned = buildJsonObject {
            raw.forEach { (key, value) ->
                when {
                    key.endsWith(KEEP_NULL_SUFFIX) -> put(key.removeSuffix(KEEP_NULL_SUFFIX), value)
                    value is JsonNull -> Unit
                    else -> put(key, value)
                }
            }
        }
        return client.encodeToString(pruned)
    }

    /** Marks a key whose explicit `null` must survive [body]'s pruning. */
    private fun keepNull(key: String) = key + KEEP_NULL_SUFFIX

    private companion object {
        const val KEEP_NULL_SUFFIX = "\u0000keepNull"
    }

    private fun userAgreement(accepted: Boolean, version: String): JsonObject = buildJsonObject {
        put("accepted", accepted)
        put("version", version)
    }

    // MARK: - Auth

    override suspend fun requestCode(
        email: String,
        userAgreementAccepted: Boolean,
        userAgreementVersion: String,
    ): AuthChallenge {
        val envelope = client.request(
            path = "auth/request-link",
            method = "POST",
            jsonBody = body {
                put("email", email)
                put("userAgreement", userAgreement(userAgreementAccepted, userAgreementVersion))
            },
            deserializer = AuthRequestEnvelope.serializer(),
        )
        return AuthChallenge(message = envelope.message, debugCode = envelope.debugCode)
    }

    override suspend fun verifyCode(
        email: String,
        code: String,
        userAgreementAccepted: Boolean,
        userAgreementVersion: String,
        showOnMap: Boolean?,
    ): SessionUser {
        val envelope = client.request(
            path = "auth/verify",
            method = "POST",
            jsonBody = body {
                put("email", email)
                put("code", code)
                put("userAgreement", userAgreement(userAgreementAccepted, userAgreementVersion))
                showOnMap?.let { put("showOnMap", it) }
            },
            deserializer = VerifyEnvelope.serializer(),
        )
        client.setSessionToken(envelope.sessionToken)
        return envelope.user
    }

    override fun clearAuthSession() = client.setSessionToken(null)

    // MARK: - Profile

    override suspend fun fetchCurrentUser(): UserProfile =
        client.request(path = "me", deserializer = MeEnvelope.serializer()).user

    override suspend fun updateProfile(profile: UserProfile): UserProfile {
        val primarySportLevel = profile.preferredSports.firstOrNull()?.let { profile.sportLevels[it.wire] }
        val payload = body {
            put("name", profile.name)
            put("age", profile.age)
            put("gender", profile.gender?.wire)
            put("city", profile.city)
            put("locationPlaceId", profile.location?.id)
            // `.legacy` is a read-only marker on the server, never sent back.
            put("locationSource", profile.locationSource?.takeIf { it != LocationSource.LEGACY }?.wire)
            put("district", profile.district)
            putJsonArray("preferredDistricts") { profile.preferredDistricts.forEach { add(JsonPrimitive(it)) } }
            put("bio", profile.bio)
            put("avatarUrl", profile.avatarUrl)
            putJsonArray("profilePhotoUrls") { profile.profilePhotoUrls.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("profileVideoUrls") { profile.profileVideoUrls.forEach { add(JsonPrimitive(it)) } }
            put("tennisLevel", (primarySportLevel ?: profile.tennisLevel ?: 5).coerceIn(1, 10))
            putJsonArray("preferredSports") { profile.preferredSports.forEach { add(JsonPrimitive(it.wire)) } }
            putJsonObject("sportLevels") { profile.sportLevels.forEach { (key, value) -> put(key, value) } }
            put("preferredPlayFormat", profile.preferredPlayFormat.wire)
            put("preferredSurface", profile.preferredSurface.wire)
            putJsonArray("availableDays") { profile.availableDays.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("availableTimeRanges") { profile.availableTimeRanges.forEach { add(JsonPrimitive(it)) } }
            putJsonObject("availabilityByDay") {
                profile.availabilityByDay.forEach { (day, slots) ->
                    put(day, JsonArray(slots.map { slot -> JsonPrimitive(slot) }))
                }
            }
            put("searchRadiusKm", profile.searchRadiusKm)
            put("isLookingForGame", profile.isLookingForGame)
            put("showOnMap", profile.showOnMap)
            put("notificationMatches", profile.notificationMatches)
            put("notificationMessages", profile.notificationMessages)
            put("notificationGames", profile.notificationGames)
            put("notificationSound", profile.notificationSound)
        }

        return client.request(
            path = "me",
            method = "PATCH",
            jsonBody = payload,
            deserializer = MeEnvelope.serializer(),
        ).user
    }

    override suspend fun updateLocaleOverride(locale: String?): String? = client.request(
        path = "me/locale",
        method = "PATCH",
        jsonBody = body { put("localeOverride", locale) },
        deserializer = LocaleOverrideEnvelope.serializer(),
    ).localeOverride

    override suspend fun fetchLocationCountries(query: String?): List<GeoCountry> = client.request(
        path = "locations/countries",
        query = buildList {
            add("locale" to client.effectiveLocaleIdentifier)
            query?.trim()?.takeIf { it.isNotEmpty() }?.let { add("q" to it) }
        },
        deserializer = LocationCountriesEnvelope.serializer(),
    ).countries

    override suspend fun fetchLocationCities(countryCode: String, query: String, limit: Int): List<GeoPlace> =
        client.request(
            path = "locations/cities",
            query = listOf(
                "countryCode" to countryCode,
                "q" to query,
                "locale" to client.effectiveLocaleIdentifier,
                "limit" to limit.toString(),
            ),
            deserializer = LocationCitiesEnvelope.serializer(),
        ).places

    override suspend fun reverseGeocodeLocation(latitude: Double, longitude: Double): GeoPlace = client.request(
        path = "locations/reverse",
        method = "POST",
        jsonBody = body {
            put("latitude", latitude)
            put("longitude", longitude)
            put("locale", client.effectiveLocaleIdentifier)
        },
        deserializer = ReverseLocationEnvelope.serializer(),
    ).place

    override suspend fun deleteAccount() {
        client.requestDiscardingResponse(path = "me", method = "DELETE", jsonBody = "{}")
    }

    // MARK: - Uploads

    override suspend fun uploadAvatar(bytes: ByteArray, fileName: String, mimeType: String): String =
        client.uploadMultipart(
            path = "uploads/avatar",
            fieldName = "file",
            fileName = fileName,
            mimeType = mimeType,
            bytes = bytes,
            deserializer = AvatarUploadEnvelope.serializer(),
        ).avatarUrl

    override suspend fun uploadProfileMedia(bytes: ByteArray, fileName: String, mimeType: String): ProfileMediaUploadResult =
        client.uploadMultipart(
            path = "uploads/profile-media",
            fieldName = "file",
            fileName = fileName,
            mimeType = mimeType,
            bytes = bytes,
            deserializer = ProfileMediaUploadResult.serializer(),
        )

    override suspend fun removeProfileMedia(mediaUrl: String): ProfileMediaUploadResult = client.request(
        path = "uploads/profile-media",
        method = "DELETE",
        jsonBody = body { put("mediaUrl", mediaUrl) },
        deserializer = ProfileMediaUploadResult.serializer(),
    )

    override suspend fun uploadChatMedia(bytes: ByteArray, fileName: String, mimeType: String): ChatMediaAttachment =
        client.uploadMultipart(
            path = "uploads/chat-media",
            fieldName = "file",
            fileName = fileName,
            mimeType = mimeType,
            bytes = bytes,
            deserializer = ChatMediaUploadEnvelope.serializer(),
        ).asset

    override suspend fun fetchChatMedia(path: String): ByteArray = client.download(path)

    // MARK: - Discovery

    override suspend fun fetchDiscoverUsers(view: DiscoverTab, sport: Sport?): List<DiscoverUser> =
        when (view) {
            DiscoverTab.LIKES -> client.request(
                path = "users/discover/likes",
                deserializer = DiscoverEnvelope.serializer(),
            )
            else -> client.request(
                path = "users/discover",
                query = buildList {
                    if (view != DiscoverTab.SWIPE) add("view" to view.wire)
                    if (view == DiscoverTab.SWIPE && sport != null) add("sport" to sport.wire)
                },
                deserializer = DiscoverEnvelope.serializer(),
            )
        }.users

    override suspend fun fetchGuestDiscoverUsers(
        draft: GuestOnboardingDraft,
        view: DiscoverTab,
        sport: Sport?,
    ): List<DiscoverUser> = client.request(
        path = "users/discover/guest",
        method = "POST",
        jsonBody = body {
            putJsonObject("draft") {
                put("name", draft.name)
                put("age", draft.age)
                put("gender", draft.gender?.wire)
                put("city", draft.city)
                put("locationPlaceId", draft.location?.id)
                put("locationSource", draft.locationSource?.wire)
                put("district", draft.district)
                putJsonArray("preferredDistricts") { draft.preferredDistricts.forEach { add(JsonPrimitive(it)) } }
                putJsonArray("preferredSports") { draft.preferredSports.forEach { add(JsonPrimitive(it.wire)) } }
                putJsonObject("sportLevels") { draft.sportLevels.forEach { (key, value) -> put(key, value) } }
                put("preferredPlayFormat", draft.preferredPlayFormat.wire)
                put("preferredSurface", draft.preferredSurface.wire)
                put("searchRadiusKm", draft.searchRadiusKm)
                put("isLookingForGame", draft.isLookingForGame)
                putJsonArray("availableDays") { draft.availableDays.forEach { add(JsonPrimitive(it)) } }
                putJsonArray("availableTimeRanges") { draft.availableTimeRanges.forEach { add(JsonPrimitive(it)) } }
                putJsonObject("availabilityByDay") {
                    draft.availabilityByDay.forEach { (day, slots) -> put(day, JsonArray(slots.map { slot -> JsonPrimitive(slot) })) }
                }
            }
            putJsonObject("filters") {
                // The swipe deck is the default view and sends no `view` filter.
                if (view != DiscoverTab.SWIPE) put("view", view.wire)
                if (view == DiscoverTab.SWIPE && sport != null) {
                    put("sport", buildJsonArray { add(JsonPrimitive(sport.wire)) })
                }
            }
        },
        deserializer = DiscoverEnvelope.serializer(),
    ).users

    override suspend fun swipe(userId: String, action: SwipeAction): String? = client.request(
        path = "swipes",
        method = "POST",
        jsonBody = body {
            put("toUserId", userId)
            put("action", action.wire)
        },
        deserializer = SwipeEnvelope.serializer(),
    ).match?.id

    override suspend fun reportUser(
        userId: String,
        reason: UserSafetyReason,
        details: String?,
        context: UserSafetyContext,
    ): UserSafetyReport = safetyCall("users/$userId/report", reason, details, context)

    override suspend fun blockUser(
        userId: String,
        reason: UserSafetyReason,
        details: String?,
        context: UserSafetyContext,
    ): UserSafetyReport = safetyCall("users/$userId/block", reason, details, context)

    private suspend fun safetyCall(
        path: String,
        reason: UserSafetyReason,
        details: String?,
        context: UserSafetyContext,
    ): UserSafetyReport = client.request(
        path = path,
        method = "POST",
        jsonBody = body {
            put("reason", reason.wire)
            put("details", details)
            putJsonObject("context") {
                put("type", context.type)
                put("id", context.id)
            }
        },
        deserializer = UserSafetyReportEnvelope.serializer(),
    ).report

    // MARK: - Matches and chat

    override suspend fun fetchMatches(): List<MatchSummary> =
        client.request(path = "matches", deserializer = MatchesEnvelope.serializer()).matches

    override suspend fun ensureMatch(userId: String): MatchSummary = client.request(
        path = "matches",
        method = "POST",
        jsonBody = body { put("userId", userId) },
        deserializer = MatchEnvelope.serializer(),
    ).match

    override suspend fun fetchMyGameRequests(): List<MatchGameRequest> =
        client.request(path = "game-requests/my", deserializer = GameRequestsEnvelope.serializer()).gameRequests

    override suspend fun acknowledgeChatMessages(matchId: String?, searchId: String?, messageIds: List<String>, status: String) {
        require((matchId != null) != (searchId != null))
        require(status == "delivered" || status == "read")
        for (batch in messageIds.distinct().chunked(200)) {
            client.requestDiscardingResponse(
                path = "activity/chat-receipts",
                jsonBody = body {
                    put("matchId", matchId)
                    put("searchId", searchId)
                    put("status", status)
                    putJsonArray("messageIds") { batch.forEach { add(JsonPrimitive(it)) } }
                },
            )
        }
    }

    override suspend fun fetchMessages(matchId: String): List<ChatMessage> =
        client.request(path = "matches/$matchId/messages", deserializer = MessagesEnvelope.serializer()).messages

    override suspend fun sendMessage(matchId: String, text: String, attachmentIds: List<String>): ChatMessage =
        client.request(
            path = "matches/$matchId/messages",
            method = "POST",
            jsonBody = body {
                put("text", text)
                putJsonArray("attachmentIds") { attachmentIds.forEach { add(JsonPrimitive(it)) } }
            },
            deserializer = SendMessageEnvelope.serializer(),
        ).message

    // MARK: - Game requests

    private fun kotlinx.serialization.json.JsonObjectBuilder.putProposalDraft(draft: GameProposalDraft) {
        // iOS sends an explicit null so the server can clear a previously chosen court.
        // `encodeNil(forKey: .proposedCourtId)` - an explicit null clears the court.
        put(keepNull("proposedCourtId"), draft.proposedCourtId?.let { JsonPrimitive(it) } ?: JsonNull)
        put("proposedDatetime", draft.proposedDatetime.toServerISOString())
        put("durationMinutes", draft.durationMinutes)
        put("levelRangeMin", draft.levelRangeMin)
        put("levelRangeMax", draft.levelRangeMax)
        put("sport", draft.sport.wire)
        put("format", draft.format.wire)
        put("comment", draft.comment)
    }

    override suspend fun createGameRequest(matchId: String, draft: GameProposalDraft): MatchGameRequest =
        client.request(
            path = "game-requests",
            method = "POST",
            jsonBody = body {
                put("matchId", matchId)
                putProposalDraft(draft)
            },
            deserializer = CreateGameRequestEnvelope.serializer(),
        ).gameRequest

    override suspend fun updateGameRequest(gameRequestId: String, draft: GameProposalDraft): MatchGameRequest =
        client.request(
            path = "game-requests/$gameRequestId",
            method = "PATCH",
            jsonBody = body { putProposalDraft(draft) },
            deserializer = GameRequestEnvelope.serializer(),
        ).gameRequest

    override suspend fun shareGameRequest(gameRequestId: String, matchIds: List<String>): List<MatchGameRequest> =
        client.request(
            path = "game-requests/$gameRequestId/share",
            method = "POST",
            jsonBody = body { putJsonArray("matchIds") { matchIds.forEach { add(JsonPrimitive(it)) } } },
            deserializer = GameRequestsEnvelope.serializer(),
        ).gameRequests

    override suspend fun updateGameRequestStatus(gameRequestId: String, status: String): MatchGameRequest =
        client.request(
            path = "game-requests/$gameRequestId",
            method = "PATCH",
            jsonBody = body { put("status", status) },
            deserializer = GameRequestEnvelope.serializer(),
        ).gameRequest

    override suspend fun updateGameRequestOutcome(gameRequestId: String, outcome: String): MatchGameRequest =
        client.request(
            path = "game-requests/$gameRequestId",
            method = "PATCH",
            jsonBody = body { put("outcome", outcome) },
            deserializer = GameRequestEnvelope.serializer(),
        ).gameRequest

    override suspend fun uploadGameReportPhoto(
        gameRequestId: String,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String = client.uploadMultipart(
        path = "uploads/game-reports/$gameRequestId",
        fieldName = "file",
        fileName = fileName,
        mimeType = mimeType,
        bytes = bytes,
        deserializer = PhotoUploadEnvelope.serializer(),
    ).photoUrl

    override suspend fun createGameReport(
        gameRequestId: String,
        photoUrls: List<String>,
        comment: String,
        visibility: String,
    ): MatchGameRequest = client.request(
        path = "game-requests/$gameRequestId/report",
        method = "POST",
        jsonBody = body {
            putJsonArray("photoUrls") { photoUrls.forEach { add(JsonPrimitive(it)) } }
            put("comment", comment)
            put("visibility", visibility)
        },
        deserializer = GameRequestEnvelope.serializer(),
    ).gameRequest

    override suspend fun updateGameReportConfirmation(gameRequestId: String, status: String): MatchGameRequest =
        client.request(
            path = "game-requests/$gameRequestId/report/confirmation",
            method = "PATCH",
            jsonBody = body { put("status", status) },
            deserializer = GameRequestEnvelope.serializer(),
        ).gameRequest

    // MARK: - Personal activities

    override suspend fun fetchPersonalActivities(): List<PersonalActivity> = client.request(
        path = "personal-activities",
        deserializer = PersonalActivitiesEnvelope.serializer(),
    ).personalActivities

    override suspend fun createPersonalActivity(draft: PersonalActivityDraft): PersonalActivity = client.request(
        path = "personal-activities",
        method = "POST",
        jsonBody = body {
            put("courtId", draft.courtId)
            put("sport", draft.sport.wire)
            put("scheduledAt", draft.scheduledAt.toServerISOString())
            put("durationMinutes", draft.durationMinutes)
            put("comment", draft.comment)
        },
        deserializer = PersonalActivityEnvelope.serializer(),
    ).personalActivity

    override suspend fun updatePersonalActivity(
        activityId: String,
        draft: PersonalActivityUpdateDraft,
    ): PersonalActivity = client.request(
        path = "personal-activities/$activityId",
        method = "PATCH",
        jsonBody = body {
            put("scheduledAt", draft.scheduledAt?.toServerISOString())
            put("durationMinutes", draft.durationMinutes)
            put("comment", draft.comment)
            put("status", draft.status)
            put("reportComment", draft.reportComment)
            draft.photoUrls?.let { urls ->
                putJsonArray("photoUrls") { urls.forEach { add(JsonPrimitive(it)) } }
            }
        },
        deserializer = PersonalActivityEnvelope.serializer(),
    ).personalActivity

    override suspend fun uploadPersonalActivityPhoto(
        activityId: String,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String = client.uploadMultipart(
        path = "uploads/personal-activities/$activityId",
        fieldName = "file",
        fileName = fileName,
        mimeType = mimeType,
        bytes = bytes,
        deserializer = PhotoUploadEnvelope.serializer(),
    ).photoUrl

    // MARK: - Searches

    override suspend fun fetchSearches(): List<GameSearch> =
        client.request(path = "game-searches/my", deserializer = SearchesEnvelope.serializer()).gameSearches

    private fun searchDraftBody(draft: SearchDraft): String = body {
        put("inviteSlug", draft.inviteSlug)
        put("preferredCourtId", draft.preferredCourtId)
        put("customVenueTitle", draft.customVenueTitle)
        put("customVenueAddress", draft.customVenueAddress)
        put("runningRoute", draft.runningRoute)
        draft.runningRoutePoints?.let { points ->
            putJsonArray("runningRoutePoints") {
                points.forEach { point ->
                    add(
                        buildJsonObject {
                            put("lat", point.lat)
                            put("lng", point.lng)
                        },
                    )
                }
            }
        }
        putJsonArray("preferredDistricts") { draft.preferredDistricts.forEach { add(JsonPrimitive(it)) } }
        putJsonArray("preferredDays") { draft.preferredDays.forEach { add(JsonPrimitive(it)) } }
        putJsonArray("preferredTimeRanges") { draft.preferredTimeRanges.forEach { add(JsonPrimitive(it)) } }
        put("searchType", draft.searchType.wire)
        put("hotWindow", draft.hotWindow?.wire)
        put("hotStartTime", draft.hotStartTime)
        put("hotStartsAt", draft.hotStartsAt)
        put("durationMinutes", draft.durationMinutes)
        put("hasCourtBooked", draft.hasCourtBooked)
        put("sport", draft.sport.wire)
        put("selfLevel", draft.selfLevel)
        put("selfLevelUnknown", draft.selfLevelUnknown)
        put("desiredLevelMin", draft.desiredLevelMin)
        put("desiredLevelMax", draft.desiredLevelMax)
        put("format", draft.format.wire)
        put("playersNeeded", draft.playersNeeded)
        put("comment", draft.comment)
    }

    override suspend fun createSearch(draft: SearchDraft): GameSearch = client.request(
        path = "game-searches",
        method = "POST",
        jsonBody = searchDraftBody(draft),
        deserializer = CreateSearchEnvelope.serializer(),
    ).gameSearch

    override suspend fun updateSearch(searchId: String, draft: SearchDraft): GameSearch = client.request(
        path = "game-searches/$searchId",
        method = "PATCH",
        jsonBody = searchDraftBody(draft),
        deserializer = CreateSearchEnvelope.serializer(),
    ).gameSearch

    override suspend fun setSearchActive(searchId: String, isActive: Boolean): GameSearch = client.request(
        path = "game-searches/$searchId",
        method = "PATCH",
        jsonBody = body { put("isActive", isActive) },
        deserializer = CreateSearchEnvelope.serializer(),
    ).gameSearch

    override suspend fun fetchSearchLobby(searchId: String): SearchLobbySummary =
        client.request(path = "game-searches/$searchId", deserializer = SearchLobbySummary.serializer())

    override suspend fun sendSearchLobbyMessage(
        searchId: String,
        text: String,
        attachmentIds: List<String>,
    ): SearchLobbyMessage = client.request(
        path = "game-searches/$searchId/messages",
        method = "POST",
        jsonBody = body {
            put("text", text)
            putJsonArray("attachmentIds") { attachmentIds.forEach { add(JsonPrimitive(it)) } }
        },
        deserializer = SearchLobbyMessageEnvelope.serializer(),
    ).message

    override suspend fun createSearchSlotProposal(
        searchId: String,
        options: List<SearchSlotProposalDraftOption>,
        comment: String?,
    ): SearchSlotProposalSummary = client.request(
        path = "game-searches/$searchId/slot-proposals",
        method = "POST",
        jsonBody = body {
            put("comment", comment ?: "")
            putJsonArray("options") {
                options.forEach { option ->
                    add(
                        buildJsonObject {
                            put("scheduledAt", option.scheduledAt.toServerISOString())
                            put("proposedCourtId", option.proposedCourtId)
                            put("durationMinutes", option.durationMinutes)
                        },
                    )
                }
            }
        },
        deserializer = SearchSlotProposalEnvelope.serializer(),
    ).proposal

    override suspend fun voteSearchSlotProposal(
        searchId: String,
        proposalId: String,
        optionIds: List<String>,
    ): SearchSlotProposalSummary = client.request(
        path = "game-searches/$searchId/slot-proposals/$proposalId/votes",
        method = "PUT",
        jsonBody = body { putJsonArray("optionIds") { optionIds.forEach { add(JsonPrimitive(it)) } } },
        deserializer = SearchSlotProposalEnvelope.serializer(),
    ).proposal

    override suspend fun scheduleSearchGame(
        searchId: String,
        courtId: String?,
        scheduledAt: Instant,
        durationMinutes: Int,
    ): SearchGameScheduleResult = client.request(
        path = "game-searches/$searchId",
        method = "PATCH",
        jsonBody = body {
            put("scheduledCourtId", courtId)
            put("scheduledAt", scheduledAt.toServerISOString())
            put("scheduledDurationMinutes", durationMinutes)
        },
        deserializer = SearchGameScheduleResult.serializer(),
    )

    override suspend fun fetchRegularPair(regularPairId: String): RegularPairSummary = client.request(
        path = "regular-pairs/$regularPairId",
        deserializer = RegularPairEnvelope.serializer(),
    ).regularPair

    override suspend fun updateRegularPairOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: Instant?,
        proposedCourtId: String?,
    ): RegularPairOccurrence = client.request(
        path = "regular-pairs/$regularPairId/occurrences/$occurrenceId",
        method = "PATCH",
        jsonBody = body {
            put("status", status)
            put("scheduledAt", scheduledAt?.toServerISOString())
            put("proposedCourtId", proposedCourtId)
        },
        deserializer = RegularPairOccurrenceEnvelope.serializer(),
    ).occurrence

    override suspend fun respondToSearch(searchId: String, message: String): SearchResponse = client.request(
        path = "game-searches/$searchId/respond",
        method = "POST",
        jsonBody = body { put("message", message) },
        deserializer = SearchResponseEnvelope.serializer(),
    ).response

    override suspend fun withdrawSearchResponse(responseId: String): SearchResponse = client.request(
        path = "game-search-responses/$responseId",
        method = "PATCH",
        jsonBody = body { put("status", "withdrawn") },
        deserializer = SearchResponseEnvelope.serializer(),
    ).response

    override suspend fun updateSearchResponseStatus(
        responseId: String,
        status: String,
    ): SearchResponseUpdateResult {
        val envelope = client.request(
            path = "game-search-responses/$responseId",
            method = "PATCH",
            jsonBody = body { put("status", status) },
            deserializer = SearchResponseEnvelope.serializer(),
        )
        return SearchResponseUpdateResult(
            response = envelope.response,
            matchId = envelope.matchId,
            gameRequestId = envelope.gameRequestId,
            regularPairId = envelope.regularPairId,
            gameSearch = envelope.gameSearch,
        )
    }

    override suspend fun simulateRegularSearchActivity(searchId: String): SearchSimulationResult = client.request(
        path = "game-searches/$searchId/simulate",
        method = "POST",
        jsonBody = "{}",
        deserializer = SearchSimulationResult.serializer(),
    )

    // MARK: - Courts

    override suspend fun fetchCourts(city: String?, locationPlaceId: String?, sport: Sport?): List<Court> =
        client.request(
            path = "courts",
            query = buildList {
                city?.trim()?.takeIf { it.isNotEmpty() }?.let { add("city" to it) }
                locationPlaceId?.let { add("locationPlaceId" to it) }
                sport?.let { add("sport" to it.wire) }
            },
            deserializer = CourtsEnvelope.serializer(),
        ).courts

    override suspend fun fetchCourt(courtId: String): Court =
        client.request(path = "courts/$courtId", deserializer = CourtEnvelope.serializer()).court

    override suspend fun fetchAddressSuggestions(query: String, city: String?): List<AddressSuggestion> =
        client.request(
            path = "addresses/suggest",
            query = buildList {
                add("q" to query)
                city?.trim()?.takeIf { it.isNotEmpty() }?.let { add("city" to it) }
            },
            deserializer = AddressSuggestionsEnvelope.serializer(),
        ).suggestions

    override suspend fun setCourtMembership(courtId: String, isMember: Boolean): Court = client.request(
        path = "courts/$courtId/membership",
        method = "POST",
        jsonBody = body { put("isMember", isMember) },
        deserializer = CourtEnvelope.serializer(),
    ).court

    // MARK: - Activity

    override suspend fun fetchNotifications(): List<AppNotification> = client.request(
        path = "activity/notifications",
        deserializer = NotificationsEnvelope.serializer(),
    ).notifications

    override suspend fun fetchActivitySummary(): ActivitySummary =
        client.request(path = "activity/summary", deserializer = ActivitySummary.serializer())

    override fun realtimeEvents(lastEventId: String?): Flow<RealtimeEvent> = client.realtimeEvents(lastEventId)

    override suspend fun fetchAppStats(): AppStats =
        client.request(path = "app/stats", deserializer = AppStats.serializer())

    override suspend fun markInboxSeen() {
        client.requestDiscardingResponse(path = "activity/inbox-seen", jsonBody = "{}")
    }

    override suspend fun markNotificationsSeen() {
        client.requestDiscardingResponse(path = "activity/notifications-seen", jsonBody = "{}")
    }

    override suspend fun setActiveChat(matchId: String?, gameRequestId: String?, isActive: Boolean) {
        client.requestDiscardingResponse(
            path = "activity/active-chat",
            jsonBody = body {
                put("matchId", matchId)
                put("gameRequestId", gameRequestId)
                put("searchId", null as String?)
                put("isActive", isActive)
            },
        )
    }

    override suspend fun setActiveSearchLobby(searchId: String, isActive: Boolean) {
        client.requestDiscardingResponse(
            path = "activity/active-chat",
            jsonBody = body {
                put("matchId", null as String?)
                put("gameRequestId", null as String?)
                put("searchId", searchId)
                put("isActive", isActive)
            },
        )
    }

    override suspend fun fetchEmptyDeckContent(
        city: String?,
        locationPlaceId: String?,
        sports: List<Sport>?,
    ): EmptyDeckContent = client.request(
        path = "discover/empty-state",
        query = buildList {
            city?.let { add("city" to it) }
            locationPlaceId?.let { add("locationPlaceId" to it) }
            sports?.takeIf { it.isNotEmpty() }?.let { list ->
                add("sport" to list.joinToString(",") { it.wire })
            }
        },
        deserializer = EmptyDeckContent.serializer(),
    )

    override suspend fun fetchInviteSummary(): InviteSummary =
        client.request(path = "me/invite", deserializer = InviteEnvelope.serializer()).invite

    /**
     * The backend currently exposes only `devices/apns` (see src/app/devices).
     * A matching `devices/fcm` route has to land before Android push works;
     * until then nothing in the app calls this.
     */
    override suspend fun registerPushDevice(
        token: String,
        environment: String,
        bundleId: String,
        deviceName: String?,
        locale: String?,
    ) {
        client.requestDiscardingResponse(
            path = "devices/fcm",
            jsonBody = body {
                put("token", token)
                put("platform", "android")
                // FCM has no sandbox/production split the way APNs does, but the
                // column is shared with iOS rows, so the build type stands in.
                put("environment", environment)
                put("bundleId", bundleId)
                put("deviceName", deviceName)
                put("locale", locale)
            },
        )
    }
}

// MARK: - Response envelopes (private structs in APIClient.swift)

@kotlinx.serialization.Serializable
internal data class AuthRequestEnvelope(val ok: Boolean = false, val message: String = "", val debugCode: String? = null)

@kotlinx.serialization.Serializable
internal data class VerifyEnvelope(val ok: Boolean = false, val user: SessionUser, val sessionToken: String? = null)

@kotlinx.serialization.Serializable
internal data class MeEnvelope(val user: UserProfile)

@kotlinx.serialization.Serializable
internal data class LocaleOverrideEnvelope(val localeOverride: String? = null, val effectiveLocale: String = "en")

@kotlinx.serialization.Serializable
internal data class LocationCountriesEnvelope(val countries: List<GeoCountry> = emptyList())

@kotlinx.serialization.Serializable
internal data class LocationCitiesEnvelope(val places: List<GeoPlace> = emptyList())

@kotlinx.serialization.Serializable
internal data class ReverseLocationEnvelope(val place: GeoPlace)

@kotlinx.serialization.Serializable
internal data class AvatarUploadEnvelope(val avatarUrl: String)

@kotlinx.serialization.Serializable
internal data class ChatMediaUploadEnvelope(val asset: ChatMediaAttachment)

@kotlinx.serialization.Serializable
internal data class DiscoverEnvelope(val users: List<DiscoverUser> = emptyList())

@kotlinx.serialization.Serializable
internal data class MatchesEnvelope(val matches: List<MatchSummary> = emptyList())

@kotlinx.serialization.Serializable
internal data class MatchEnvelope(val match: MatchSummary)

@kotlinx.serialization.Serializable
internal data class MatchReference(val id: String)

@kotlinx.serialization.Serializable
internal data class SwipeEnvelope(val match: MatchReference? = null)

@kotlinx.serialization.Serializable
internal data class UserSafetyReportEnvelope(val report: UserSafetyReport)

@kotlinx.serialization.Serializable
internal data class GameRequestsEnvelope(val gameRequests: List<MatchGameRequest> = emptyList())

@kotlinx.serialization.Serializable
internal data class GameRequestEnvelope(val gameRequest: MatchGameRequest)

@kotlinx.serialization.Serializable
internal data class CreateGameRequestEnvelope(val gameRequest: MatchGameRequest)

@kotlinx.serialization.Serializable
internal data class MessagesEnvelope(val messages: List<ChatMessage> = emptyList())

@kotlinx.serialization.Serializable
internal data class SendMessageEnvelope(val message: ChatMessage)

@kotlinx.serialization.Serializable
internal data class PhotoUploadEnvelope(val photoUrl: String)

@kotlinx.serialization.Serializable
internal data class PersonalActivitiesEnvelope(val personalActivities: List<PersonalActivity> = emptyList())

@kotlinx.serialization.Serializable
internal data class PersonalActivityEnvelope(val personalActivity: PersonalActivity)

@kotlinx.serialization.Serializable
internal data class SearchesEnvelope(val gameSearches: List<GameSearch> = emptyList())

@kotlinx.serialization.Serializable
internal data class CreateSearchEnvelope(val gameSearch: GameSearch)

@kotlinx.serialization.Serializable
internal data class SearchResponseEnvelope(
    val response: SearchResponse,
    val matchId: String? = null,
    val gameRequestId: String? = null,
    val regularPairId: String? = null,
    val gameSearch: SearchStatusUpdate? = null,
)

@kotlinx.serialization.Serializable
internal data class SearchLobbyMessageEnvelope(val message: SearchLobbyMessage)

@kotlinx.serialization.Serializable
internal data class SearchSlotProposalEnvelope(val proposal: SearchSlotProposalSummary)

@kotlinx.serialization.Serializable
internal data class RegularPairEnvelope(val regularPair: RegularPairSummary)

@kotlinx.serialization.Serializable
internal data class RegularPairOccurrenceEnvelope(val occurrence: RegularPairOccurrence)

@kotlinx.serialization.Serializable
internal data class CourtsEnvelope(val courts: List<Court> = emptyList())

@kotlinx.serialization.Serializable
internal data class CourtEnvelope(val court: Court)

@kotlinx.serialization.Serializable
internal data class AddressSuggestionsEnvelope(val suggestions: List<AddressSuggestion> = emptyList())

@kotlinx.serialization.Serializable
internal data class NotificationsEnvelope(val notifications: List<AppNotification> = emptyList())

@kotlinx.serialization.Serializable
internal data class InviteEnvelope(val invite: InviteSummary)
