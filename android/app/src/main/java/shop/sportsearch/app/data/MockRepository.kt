package shop.sportsearch.app.data

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import shop.sportsearch.app.core.*
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID

/** The three schematic map areas from ios/.../MockRepository.swift. */
private val mockCentralMapArea = DiscoverMapArea(
    id = "mock-spb:district:central", cityId = "mock-spb", cityName = "Санкт-Петербург",
    kind = "district", districtId = "central", label = "Центральный",
    latitude = 59.9343, longitude = 30.3351,
)
private val mockMoskovskyMapArea = DiscoverMapArea(
    id = "mock-spb:district:moskovsky", cityId = "mock-spb", cityName = "Санкт-Петербург",
    kind = "district", districtId = "moskovsky", label = "Московский",
    latitude = 59.85, longitude = 30.32,
)
private val mockPetrogradMapArea = DiscoverMapArea(
    id = "mock-spb:district:petrogradsky", cityId = "mock-spb", cityName = "Санкт-Петербург",
    kind = "district", districtId = "petrogradsky", label = "Петроградский",
    latitude = 59.965, longitude = 30.30,
)

/**
 * Stand-in for `final class MockRepository` (ios/.../Services/MockRepository.swift).
 *
 * The iOS mock carries a large hand-written fixture set used for App Store
 * screenshots. This port keeps the same contract and enough seed data to browse
 * every screen offline; it is deliberately smaller and is not the shipping path
 * (`USE_MOCK_DATA` is NO in both release configs).
 *
 * Mock sign-in: any email, code `111111`.
 */
class MockRepository : TennisRepository {

    private var profile = UserProfile(
        id = "mock-user",
        email = "player@sportsearch.shop",
        name = "Алекс",
        age = 29,
        genderRaw = Gender.MALE.wire,
        city = "Санкт-Петербург",
        district = "petrogradsky",
        preferredDistricts = listOf("petrogradsky", "central"),
        bio = "Играю 3 раза в неделю, ищу партнёра примерно своего уровня.",
        tennisLevel = 6,
        preferredSports = listOf(Sport.TENNIS, Sport.PADEL),
        sportLevels = mapOf(Sport.TENNIS.wire to 6, Sport.PADEL.wire to 4),
        preferredPlayFormatRaw = PlayFormat.SINGLES.wire,
        preferredSurfaceRaw = Surface.HARD.wire,
        availableDays = listOf(DayOfWeek.TUESDAY.wire, DayOfWeek.THURSDAY.wire, DayOfWeek.SATURDAY.wire),
        availableTimeRanges = listOf(TimeRange.EVENING.wire),
        isLookingForGame = true,
        showOnMap = true,
        onboardingCompleted = true,
        isVerified = true,
    )

    private val people = listOf(
        mockUser("u1", "Мария", 27, Sport.TENNIS, 6, "Петроградский", "1.2 км", listOf(mockPetrogradMapArea)),
        mockUser("u2", "Дмитрий", 34, Sport.PADEL, 5, "Центральный", "2.8 км", listOf(mockCentralMapArea, mockMoskovskyMapArea)),
        mockUser("u3", "Ольга", 31, Sport.BADMINTON, 7, "Василеостровский", "3.4 км", listOf(mockCentralMapArea)),
        mockUser("u4", "Игорь", 25, Sport.TABLE_TENNIS, 4, "Московский", "5.1 км", listOf(mockMoskovskyMapArea)),
        mockUser("u5", "Настя", 29, Sport.SQUASH, 8, "Приморский", "6.7 км"),
    )

    private val courts = listOf(
        mockCourt("c1", "Теннисный клуб «Крестовский»", "Крестовский остров, 23", 59.9721, 30.2497, "Крестовский остров"),
        mockCourt("c2", "Padel Friends", "Аптекарская наб., 20", 59.9698, 30.3225, "Петроградская"),
        mockCourt("c3", "Арена Спорт", "Московский пр., 189", 59.8511, 30.3211, "Московская"),
    )

    private val searches = mutableListOf(
        GameSearch(
            id = "s1",
            createdByUserId = "mock-user",
            status = "open",
            searchTypeRaw = SearchType.HOT.wire,
            hotWindowRaw = HotWindow.TOMORROW.wire,
            hotStartsAt = Instant.now().plus(1, ChronoUnit.DAYS).toServerISOString(),
            durationMinutes = 90,
            hasCourtBooked = true,
            sportRaw = Sport.TENNIS.wire,
            selfLevel = 6,
            desiredLevelMin = 5,
            desiredLevelMax = 8,
            formatRaw = PlayFormat.SINGLES.wire,
            playersNeeded = 1,
            preferredDays = listOf(DayOfWeek.THURSDAY.wire),
            preferredTimeRanges = listOf(TimeRange.EVENING.wire),
            comment = "Корт забронирован, нужен соперник.",
            isActive = true,
            preferredCourt = courts.first(),
            preferredDistricts = listOf("petrogradsky"),
        ),
    )

    private val matches = listOf(
        MatchSummary(
            id = "m1",
            status = "active",
            createdAt = Instant.now().minus(2, ChronoUnit.DAYS).toServerISOString(),
            otherUser = people[0],
            lastMessage = ChatMessage(
                id = "msg1",
                senderUserId = "u1",
                text = "Привет! Сыграем в четверг вечером?",
                createdAt = Instant.now().minus(3, ChronoUnit.HOURS).toServerISOString(),
                senderUser = ChatSender("u1", "Мария", null),
            ),
        ),
        MatchSummary(
            id = "m2",
            status = "active",
            createdAt = Instant.now().minus(6, ChronoUnit.DAYS).toServerISOString(),
            otherUser = people[1],
        ),
    )

    private val messages = mutableMapOf(
        "m1" to mutableListOf(
            ChatMessage("msg0", "mock-user", text = "Привет!", createdAt = Instant.now().minus(4, ChronoUnit.HOURS).toServerISOString(), senderUser = ChatSender("mock-user", "Алекс", null)),
            ChatMessage("msg1", "u1", text = "Привет! Сыграем в четверг вечером?", createdAt = Instant.now().minus(3, ChronoUnit.HOURS).toServerISOString(), senderUser = ChatSender("u1", "Мария", null)),
        ),
    )

    private fun mockUser(
        id: String,
        name: String,
        age: Int,
        sport: Sport,
        level: Int,
        districtLabel: String,
        distance: String,
        mapAreas: List<DiscoverMapArea> = emptyList(),
    ) = DiscoverUser(
        id = id,
        // `makeDiscoverUser` sets `showOnMap` from whether the user has any areas.
        showOnMap = mapAreas.isNotEmpty(),
        mapAreasRaw = mapAreas,
        name = name,
        age = age,
        city = "Санкт-Петербург",
        districtLabel = districtLabel,
        bio = "Играю в ${sport.title.lowercase()}, ищу регулярного партнёра.",
        tennisLevel = level,
        preferredSports = listOf(sport),
        sportLevels = mapOf(sport.wire to level),
        preferredPlayFormatRaw = sport.defaultFormat.wire,
        availableDays = listOf(DayOfWeek.TUESDAY.wire, DayOfWeek.SATURDAY.wire),
        availableTimeRanges = listOf(TimeRange.EVENING.wire),
        distanceLabelRaw = distance,
        explainabilityReasons = listOf("Тот же район", "Близкий уровень"),
    )

    private fun mockCourt(
        id: String,
        name: String,
        address: String,
        lat: Double,
        lng: Double,
        metro: String,
    ) = Court(
        id = id,
        name = name,
        address = address,
        city = "Санкт-Петербург",
        district = "petrogradsky",
        locationLat = lat,
        locationLng = lng,
        distanceLabel = "2.4 км",
        nearestMetroName = metro,
        metroNames = listOf(metro),
        supportedSports = listOf(Sport.TENNIS, Sport.PADEL),
        phone = "+7 812 000-00-00",
        workingHours = "07:00 – 23:00",
        amenities = listOf("Раздевалки", "Душ", "Прокат ракеток"),
        priceRange = "1500–3500 ₽/час",
        rating = 4.7,
        memberCount = 42,
        activeSearchesCount = 3,
        activeSearchPlayersCount = 3,
    )

    // MARK: - TennisRepository

    override suspend fun requestCode(email: String, userAgreementAccepted: Boolean, userAgreementVersion: String): AuthChallenge {
        delay(240)
        return AuthChallenge(message = "Код отправлен на $email", debugCode = "111111")
    }

    override suspend fun verifyCode(
        email: String,
        code: String,
        userAgreementAccepted: Boolean,
        userAgreementVersion: String,
        showOnMap: Boolean?,
    ): SessionUser {
        delay(240)
        if (code != "111111") throw ApiException.Server("Неверный код")
        return SessionUser(id = profile.id, email = email, onboardingCompleted = true)
    }

    override suspend fun signInWithGoogle(
        idToken: String,
        userAgreementAccepted: Boolean,
        userAgreementVersion: String,
        showOnMap: Boolean?,
    ): SessionUser {
        delay(240)
        return SessionUser(id = profile.id, email = profile.email ?: "google@example.com", onboardingCompleted = true)
    }

    override fun clearAuthSession() = Unit

    override suspend fun fetchCurrentUser(): UserProfile = profile

    override suspend fun updateProfile(profile: UserProfile): UserProfile {
        this.profile = profile
        return profile
    }

    override suspend fun updateLocaleOverride(locale: String?): String? = locale

    override suspend fun fetchLocationCountries(query: String?) = listOf(GeoCountry("RU", "Russia"))

    override suspend fun fetchLocationCities(countryCode: String, query: String, limit: Int) = listOf(
        GeoPlace("spb", "mock", "RU", "Russia", "Northwest", "Санкт-Петербург", 59.9386, 30.3141),
        GeoPlace("msk", "mock", "RU", "Russia", "Central", "Москва", 55.7558, 37.6173),
    )

    override suspend fun reverseGeocodeLocation(latitude: Double, longitude: Double) =
        GeoPlace("spb", "mock", "RU", "Russia", "Northwest", "Санкт-Петербург", latitude, longitude)

    override suspend fun deleteAccount() = Unit

    override suspend fun uploadAvatar(bytes: ByteArray, fileName: String, mimeType: String) = "/uploads/$fileName"

    override suspend fun uploadProfileMedia(bytes: ByteArray, fileName: String, mimeType: String) =
        ProfileMediaUploadResult(mediaUrl = "/uploads/$fileName", mediaType = mimeType)

    override suspend fun removeProfileMedia(mediaUrl: String) = ProfileMediaUploadResult()

    // Uploaded bytes are kept in memory so the chat can render what was just
    // sent; the real backend serves these from object storage.
    private val chatMedia = mutableMapOf<String, ByteArray>()

    private val chatAttachments = mutableMapOf<String, ChatMediaAttachment>()

    override suspend fun uploadChatMedia(bytes: ByteArray, fileName: String, mimeType: String): ChatMediaAttachment {
        val id = UUID.randomUUID().toString()
        val url = "/uploads/chat-media/$id-$fileName"
        chatMedia[url] = bytes
        val attachment = ChatMediaAttachment(id, "image", url, mimeType, bytes.size, chatAttachments.size)
        chatAttachments[id] = attachment
        return attachment
    }

    override suspend fun fetchChatMedia(path: String): ByteArray = chatMedia[path] ?: ByteArray(0)

    override suspend fun fetchDiscoverUsers(view: DiscoverTab, sport: Sport?): List<DiscoverUser> {
        delay(180)
        return when (view) {
            DiscoverTab.LIKES -> people.take(2)
            DiscoverTab.HOT -> people.filter { it.gameSearches.isNotEmpty() }.ifEmpty { people.take(3) }
            else -> people
        }
    }

    override suspend fun fetchGuestDiscoverUsers(draft: GuestOnboardingDraft, view: DiscoverTab, sport: Sport?) =
        fetchDiscoverUsers(view, sport)

    override suspend fun swipe(userId: String, action: SwipeAction): String? =
        if (action == SwipeAction.LIKE && userId == "u1") "m1" else null

    override suspend fun reportUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext) =
        UserSafetyReport(id = UUID.randomUUID().toString(), status = "pending")

    override suspend fun blockUser(userId: String, reason: UserSafetyReason, details: String?, context: UserSafetyContext) =
        UserSafetyReport(id = UUID.randomUUID().toString(), status = "resolved")

    override suspend fun fetchMatches(): List<MatchSummary> {
        delay(160)
        return matches
    }

    override suspend fun ensureMatch(userId: String) = matches.first()

    override suspend fun fetchMyGameRequests(): List<MatchGameRequest> = emptyList()

    // Every read returns a copy. Handing out the internal MutableList would let a
    // screen alias mock state: a later add() would mutate the list the UI already
    // holds, and an optimistic append on top of it would show the item twice.
    override suspend fun acknowledgeChatMessages(matchId: String?, searchId: String?, messageIds: List<String>, status: String) = Unit

    override suspend fun fetchMessages(matchId: String): List<ChatMessage> =
        messages[matchId].orEmpty().toList()

    override suspend fun sendMessage(matchId: String, text: String, attachmentIds: List<String>): ChatMessage {
        val message = ChatMessage(
            id = UUID.randomUUID().toString(),
            senderUserId = profile.id,
            text = text,
            createdAt = Instant.now().toServerISOString(),
            senderUser = ChatSender(profile.id, profile.name, profile.avatarUrl),
            attachments = attachmentIds.mapIndexedNotNull { index, id ->
                chatAttachments[id]?.copy(position = index)
            },
        )
        messages.getOrPut(matchId) { mutableListOf() }.add(message)
        return message
    }

    override suspend fun createGameRequest(matchId: String, draft: GameProposalDraft) = mockGameRequest(matchId, draft)

    override suspend fun updateGameRequest(gameRequestId: String, draft: GameProposalDraft) = mockGameRequest("m1", draft)

    override suspend fun shareGameRequest(gameRequestId: String, matchIds: List<String>) = emptyList<MatchGameRequest>()

    override suspend fun updateGameRequestStatus(gameRequestId: String, status: String) =
        MatchGameRequest(id = gameRequestId, status = status, proposedDatetime = Instant.now().toServerISOString())

    override suspend fun updateGameRequestOutcome(gameRequestId: String, outcome: String) =
        MatchGameRequest(id = gameRequestId, status = "completed", outcome = outcome, proposedDatetime = Instant.now().toServerISOString())

    override suspend fun uploadGameReportPhoto(gameRequestId: String, bytes: ByteArray, fileName: String, mimeType: String) =
        "/uploads/$fileName"

    override suspend fun createGameReport(gameRequestId: String, photoUrls: List<String>, comment: String, visibility: String) =
        MatchGameRequest(id = gameRequestId, status = "completed", proposedDatetime = Instant.now().toServerISOString())

    override suspend fun updateGameReportConfirmation(gameRequestId: String, status: String) =
        MatchGameRequest(id = gameRequestId, status = "completed", proposedDatetime = Instant.now().toServerISOString())

    private fun mockGameRequest(matchId: String, draft: GameProposalDraft) = MatchGameRequest(
        id = UUID.randomUUID().toString(),
        matchId = matchId,
        status = "pending",
        proposedDatetime = draft.proposedDatetime.toServerISOString(),
        createdByUserId = profile.id,
        durationMinutes = draft.durationMinutes,
        comment = draft.comment,
        sportRaw = draft.sport.wire,
        formatRaw = draft.format.wire,
    )

    override suspend fun fetchPersonalActivities(): List<PersonalActivity> = emptyList()

    override suspend fun createPersonalActivity(draft: PersonalActivityDraft) = PersonalActivity(
        id = UUID.randomUUID().toString(),
        userId = profile.id,
        courtId = draft.courtId,
        sportRaw = draft.sport.wire,
        scheduledAt = draft.scheduledAt.toServerISOString(),
        durationMinutes = draft.durationMinutes,
        comment = draft.comment,
        status = "planned",
    )

    override suspend fun updatePersonalActivity(activityId: String, draft: PersonalActivityUpdateDraft) =
        PersonalActivity(id = activityId, userId = profile.id, status = draft.status ?: "planned")

    override suspend fun uploadPersonalActivityPhoto(activityId: String, bytes: ByteArray, fileName: String, mimeType: String) =
        "/uploads/$fileName"

    override suspend fun fetchSearches(): List<GameSearch> {
        delay(150)
        return searches.toList()
    }

    override suspend fun createSearch(draft: SearchDraft): GameSearch {
        val search = GameSearch(
            id = UUID.randomUUID().toString(),
            createdByUserId = profile.id,
            status = "open",
            searchTypeRaw = draft.searchType.wire,
            hotWindowRaw = draft.hotWindow?.wire,
            hotStartsAt = draft.hotStartsAt,
            durationMinutes = draft.durationMinutes,
            hasCourtBooked = draft.hasCourtBooked,
            sportRaw = draft.sport.wire,
            selfLevel = draft.selfLevel,
            desiredLevelMin = draft.desiredLevelMin,
            desiredLevelMax = draft.desiredLevelMax,
            formatRaw = draft.format.wire,
            playersNeeded = draft.playersNeeded,
            preferredDays = draft.preferredDays,
            preferredTimeRanges = draft.preferredTimeRanges,
            comment = draft.comment,
            isActive = true,
            preferredCourt = courts.firstOrNull { it.id == draft.preferredCourtId },
            preferredDistricts = draft.preferredDistricts,
        )
        searches.add(0, search)
        return search
    }

    override suspend fun updateSearch(searchId: String, draft: SearchDraft) = createSearch(draft)

    override suspend fun setSearchActive(searchId: String, isActive: Boolean): GameSearch {
        val index = searches.indexOfFirst { it.id == searchId }
        if (index < 0) return searches.first()
        val updated = searches[index].copy(isActive = isActive)
        searches[index] = updated
        return updated
    }

    // Lobby state is kept per search so the chat and roster survive the lobby's
    // 2.5s polling refresh, the way the real backend does.
    private val lobbyMessages = mutableMapOf<String, MutableList<SearchLobbyMessage>>()

    override suspend fun fetchSearchLobby(searchId: String): SearchLobbySummary {
        delay(120)
        return SearchLobbySummary(
            SearchLobbyGameSearch(
                id = searchId,
                createdByUserId = profile.id,
                createdByUser = mockUser("mock-user", profile.name.orEmpty(), 29, Sport.TENNIS, 6, "Петроградский", "0 км"),
                searchTypeRaw = SearchType.REGULAR.wire,
                status = "open",
                isActive = true,
                sportRaw = Sport.TENNIS.wire,
                formatRaw = PlayFormat.SINGLES.wire,
                preferredDistricts = listOf("petrogradsky"),
                preferredDays = listOf(DayOfWeek.TUESDAY.wire, DayOfWeek.THURSDAY.wire, DayOfWeek.SATURDAY.wire),
                preferredTimeRanges = listOf(TimeRange.EVENING.wire),
                durationMinutes = 90,
                playersNeeded = 1,
                desiredLevelMin = 5,
                desiredLevelMax = 7,
                comment = "Играем в среднем темпе, без счёта.",
                preferredCourt = courts.first(),
                responses = listOf(
                    SearchResponse("r1", "approved", people[0]),
                    SearchResponse("r2", "pending", people[1]),
                ),
                messages = lobbyMessages[searchId].orEmpty().toList(),
            ),
        )
    }

    override suspend fun sendSearchLobbyMessage(searchId: String, text: String, attachmentIds: List<String>): SearchLobbyMessage {
        val message = SearchLobbyMessage(
            id = UUID.randomUUID().toString(),
            senderUserId = profile.id,
            text = text,
            createdAt = Instant.now().toServerISOString(),
            senderUser = ChatSender(profile.id, profile.name, profile.avatarUrl),
            attachments = attachmentIds.mapIndexedNotNull { index, id ->
                chatAttachments[id]?.copy(position = index)
            },
        )
        lobbyMessages.getOrPut(searchId) { mutableListOf() }.add(message)
        return message
    }

    override suspend fun createSearchSlotProposal(searchId: String, options: List<SearchSlotProposalDraftOption>, comment: String?) =
        SearchSlotProposalSummary(id = UUID.randomUUID().toString(), comment = comment, status = "open")

    override suspend fun voteSearchSlotProposal(searchId: String, proposalId: String, optionIds: List<String>) =
        SearchSlotProposalSummary(id = proposalId, status = "open")

    override suspend fun scheduleSearchGame(searchId: String, courtId: String?, scheduledAt: Instant, durationMinutes: Int) =
        SearchGameScheduleResult(gameSearch = searches.first())

    override suspend fun fetchRegularPair(regularPairId: String) =
        RegularPairSummary(id = regularPairId, matchId = "m1", partnerUser = people[0])

    override suspend fun updateRegularPairOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: Instant?,
        proposedCourtId: String?,
    ) = RegularPairOccurrence(
        id = occurrenceId,
        scheduledAt = (scheduledAt ?: Instant.now()).toServerISOString(),
        status = status ?: "pending",
    )

    override suspend fun respondToSearch(searchId: String, message: String) =
        SearchResponse(id = UUID.randomUUID().toString(), status = "pending", responderUser = people[0])

    override suspend fun withdrawSearchResponse(responseId: String) =
        SearchResponse(id = responseId, status = "withdrawn", responderUser = people[0])

    override suspend fun updateSearchResponseStatus(responseId: String, status: String) = SearchResponseUpdateResult(
        response = SearchResponse(id = responseId, status = status, responderUser = people[0]),
    )

    override suspend fun simulateRegularSearchActivity(searchId: String) = SearchSimulationResult(message = "ok")

    override suspend fun fetchCourts(city: String?, locationPlaceId: String?, sport: Sport?): List<Court> {
        delay(160)
        return sport?.let { wanted -> courts.filter { it.supportedSports.contains(wanted) } } ?: courts
    }

    override suspend fun fetchCourt(courtId: String) = courts.first { it.id == courtId }

    override suspend fun fetchAddressSuggestions(query: String, city: String?) = listOf(
        AddressSuggestion("a1", query, "Санкт-Петербург, $query", null, 59.94, 30.31),
    )

    override suspend fun setCourtMembership(courtId: String, isMember: Boolean) =
        courts.first { it.id == courtId }.copy(isMember = isMember)

    override suspend fun fetchNotifications(): List<AppNotification> = emptyList()

    override suspend fun fetchActivitySummary() = ActivitySummary(
        inboxBadgeCount = 1,
        incomingLikesCount = 2,
        discoverBadgeCount = 2,
        activeSearchesCount = searches.count { it.isActive == true },
    )

    override fun realtimeEvents(lastEventId: String?): Flow<RealtimeEvent> = emptyFlow()

    override suspend fun fetchAppStats() = AppStats(registeredPlayersCount = 1284, seekingPlayersCount = 96)

    override suspend fun markInboxSeen() = Unit
    override suspend fun markNotificationsSeen() = Unit
    override suspend fun setActiveChat(matchId: String?, gameRequestId: String?, isActive: Boolean) = Unit
    override suspend fun setActiveSearchLobby(searchId: String, isActive: Boolean) = Unit

    override suspend fun fetchEmptyDeckContent(city: String?, locationPlaceId: String?, sports: List<Sport>?) =
        EmptyDeckContent(
            sections = listOf(
                EmptyDeckSection(
                    sportRaw = Sport.TENNIS.wire,
                    total = 3,
                    courts = courts.map {
                        EmptyDeckCourt(
                            id = it.id,
                            name = it.name,
                            city = it.city,
                            distanceLabel = it.distanceLabel,
                            activeSearchesCount = it.activeSearchesCount,
                            memberCount = it.memberCount,
                            searchers = people.take(3).map { user -> EmptyDeckSearcher(user.id, user.name, user.avatarUrl) },
                        )
                    },
                ),
            ),
            invite = InviteSummary(code = "MOCK", url = "https://sportsearch.shop/i/MOCK", visits = 12, joined = 3),
        )

    override suspend fun fetchInviteSummary() =
        InviteSummary(code = "MOCK", url = "https://sportsearch.shop/i/MOCK", visits = 12, joined = 3)

    override suspend fun registerPushDevice(
        token: String,
        environment: String,
        bundleId: String,
        deviceName: String?,
        locale: String?,
    ) = Unit
}
