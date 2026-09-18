package shop.sportsearch.app.ui.discover

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.core.AuthStep
import shop.sportsearch.app.core.UpcomingGamesWidgetStore
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.DarkCard
import shop.sportsearch.app.ui.components.DarkEmptyState
import shop.sportsearch.app.ui.components.DarkSectionHeader
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.ReportPhotoGalleryItem
import shop.sportsearch.app.ui.components.ReportPhotoGallerySheet
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.maps.RunningRouteDetailSheet
import shop.sportsearch.app.ui.matches.ChatScreen
import shop.sportsearch.app.ui.matches.GameProposalSheet
import shop.sportsearch.app.ui.matches.ProposalSheetContext
import shop.sportsearch.app.ui.notifications.NotificationsScreen
import shop.sportsearch.app.ui.searches.RegularPairDetailSheet
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import shop.sportsearch.app.ui.theme.statusTintColor
import shop.sportsearch.app.widget.UpcomingGamesWidget

/** Android icons for `DiscoverTab.systemImage`. */
private val DiscoverTab.icon: ImageVector
    get() = when (this) {
        DiscoverTab.UPCOMING -> Icons.Filled.CalendarMonth   // calendar.badge.clock
        DiscoverTab.SWIPE -> Icons.Filled.Group              // person.2.fill
        DiscoverTab.LIKES -> Icons.Filled.Favorite           // heart.text.square
        DiscoverTab.SEEKING -> Icons.Filled.CalendarMonth    // calendar
        DiscoverTab.HOT -> Icons.Filled.Search               // magnifyingglass
    }

/**
 * Port of `struct DiscoverView`: a black screen with a pinned pill tab bar over
 * the four user-visible tabs (upcoming, searches, similar players, likes).
 */
/** `@AppStorage("ios.discover.upcomingWidgetPrompt.dismissed.v1")`. */
private const val WIDGET_PROMPT_DISMISSED_KEY = "discover.upcomingWidgetPrompt.dismissed"

@Composable
fun DiscoverScreen(
    appModel: AppViewModel,
    initialTab: DiscoverTab,
    highlightedUserID: String?,
    highlightedSearchID: String?,
    highlightedGameRequestID: String?,
    onTabChanged: (DiscoverTab) -> Unit,
) {
    var selectedTab by remember { mutableStateOf(initialTab) }
    var users by remember { mutableStateOf<List<DiscoverUser>>(emptyList()) }
    var upcomingRequests by remember { mutableStateOf<List<MatchGameRequest>>(emptyList()) }
    var upcomingMatches by remember { mutableStateOf<List<MatchSummary>>(emptyList()) }
    var personalActivities by remember { mutableStateOf<List<PersonalActivity>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var isSubmittingSwipe by remember { mutableStateOf(false) }
    var isUpcomingHistoryExpanded by remember { mutableStateOf(false) }
    var updatingRequestIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var updatingActivityIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var photoReportRequest by remember { mutableStateOf<MatchGameRequest?>(null) }
    var activityReport by remember { mutableStateOf<PersonalActivity?>(null) }
    var selectedParticipant by remember { mutableStateOf<DiscoverUser?>(null) }
    var gallery by remember { mutableStateOf<ReportPhotoGalleryItem?>(null) }
    var chatMatch by remember { mutableStateOf<MatchSummary?>(null) }
    var proposalMatch by remember { mutableStateOf<MatchSummary?>(null) }
    var shareRequest by remember { mutableStateOf<MatchGameRequest?>(null) }
    var detailsRequest by remember { mutableStateOf<MatchGameRequest?>(null) }
    var upcomingCourt by remember { mutableStateOf<Court?>(null) }
    var regularPairId by remember { mutableStateOf<String?>(null) }
    var isWidgetHelpPresented by remember { mutableStateOf(false) }
    val androidContext = LocalContext.current
    val widgetPrefs = remember(androidContext) {
        androidContext.getSharedPreferences("sportsearch.hints", android.content.Context.MODE_PRIVATE)
    }
    // `@AppStorage("ios.discover.upcomingWidgetPrompt.dismissed.v1")`
    var isWidgetPromptDismissed by remember {
        mutableStateOf(widgetPrefs.getBoolean(WIDGET_PROMPT_DISMISSED_KEY, false))
    }
    var editGameRequest by remember { mutableStateOf<MatchGameRequest?>(null) }
    var hotSearchSportFilter by remember { mutableStateOf<Sport?>(null) }
    var hotSearchFilter by remember { mutableStateOf(ActiveHotSearchFilter.ALL) }
    var similarMode by remember { mutableStateOf(SimilarPlayersDisplayMode.CARDS) }
    var similarSportFilter by remember { mutableStateOf<Sport?>(null) }
    var selectedSimilarPlayerId by remember { mutableStateOf<String?>(null) }
    var emptyDeckSections by remember { mutableStateOf<List<EmptyDeckSection>>(emptyList()) }
    var inviteSummary by remember { mutableStateOf<InviteSummary?>(null) }
    var isLoadingEmptyDeck by remember { mutableStateOf(false) }
    var hasLoadedEmptyDeck by remember { mutableStateOf(false) }
    var emptyDeckFailed by remember { mutableStateOf(false) }
    var mySearches by remember { mutableStateOf<List<GameSearch>>(emptyList()) }
    var hotSearchCalendarDate by remember { mutableStateOf(java.time.LocalDate.now()) }
    var hotSearchDisplayMode by remember { mutableStateOf(ActiveHotSearchDisplayMode.LIST) }
    var selectedHotSearchMapItemId by remember { mutableStateOf<String?>(null) }
    var hotSearchMapClusterItemIds by remember { mutableStateOf<List<String>>(emptyList()) }
    var isNotificationsPresented by remember { mutableStateOf(false) }
    var routeSport by remember { mutableStateOf<Pair<Sport, List<RunningRoutePoint>>?>(null) }
    var routeTitle by remember { mutableStateOf("") }
    var localResponseStatuses by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var localResponseIds by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()

    // First-run tutorial overlays - ported from `DiscoverView`'s hint state.
    var isSimilarPlayersHintPresented by remember { mutableStateOf(false) }
    var isSimilarPlayersHintScheduled by remember { mutableStateOf(false) }
    var isSimilarPlayersHintDismissing by remember { mutableStateOf(false) }
    var isFirstInterestHintPresented by remember { mutableStateOf(false) }
    var isFirstInterestHintScheduled by remember { mutableStateOf(false) }
    var firstInterestHintPlayerName by remember { mutableStateOf<String?>(null) }
    var similarPlayersHintDemoPhase by remember { mutableIntStateOf(0) }
    var viewedPlayers by remember { mutableStateOf(ViewedPlayerQueue()) }

    // `responseMessage` / `matchMessage` and their auto-dismiss tasks.
    var responseMessage by remember { mutableStateOf<String?>(null) }
    var matchMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(responseMessage) {
        if (responseMessage != null) {
            delay(2200)
            responseMessage = null
        }
    }
    LaunchedEffect(matchMessage) {
        if (matchMessage != null) {
            delay(2800)
            matchMessage = null
        }
    }

    // `visibleSimilarUsers` - de-duplicated, then filtered by sport. Hoisted out
    // of the swipe tab because the hint gate reads it too.
    val visibleUsers = if (similarMode == SimilarPlayersDisplayMode.CARDS) {
        SimilarPlayersMapData.filteredUsers(users, similarSportFilter)
    } else {
        SimilarPlayersMapData.mapUsers(users, similarSportFilter)
    }

    // `orderedSimilarUsers` / `activeUser` / `topStack`.
    val orderedUsers = run {
        val lookup = visibleUsers.associateBy { it.id }
        viewedPlayers.orderedIDs(visibleUsers.map { it.id }).mapNotNull(lookup::get)
    }
    val activeUser = selectedSimilarPlayerId?.let { id -> visibleUsers.firstOrNull { it.id == id } }
        ?: orderedUsers.firstOrNull()
    val deckUsers = activeUser
        ?.let { listOf(it) + orderedUsers.filterNot { other -> other.id == it.id } }
        ?: orderedUsers

    // `viewedSimilarUsers` - most recently seen first.
    val viewedUsers = run {
        val lookup = visibleUsers.associateBy { it.id }
        viewedPlayers.newestViewedIDs(visibleUsers.map { it.id }).mapNotNull(lookup::get)
    }

    // `canManageUpcomingRequest` / `canEditUpcomingRequest`.
    fun canManageUpcomingRequest(request: MatchGameRequest): Boolean {
        if (request.isRegularOccurrence) return false
        if (request.status.lowercase() !in setOf("pending", "accepted", "approved", "proposed")) return false
        return request.canCancel(appModel.currentUser?.id)
    }

    fun canEditUpcomingRequest(request: MatchGameRequest): Boolean {
        if (!canManageUpcomingRequest(request)) return false
        return request.status.lowercase() !in setOf("canceled", "cancelled", "declined", "rejected")
    }

    fun scheduleSimilarPlayersHintIfNeeded() {
        if (!appModel.shouldPresentDiscoverSimilarPlayersHint() ||
            selectedTab != DiscoverTab.SWIPE ||
            similarMode != SimilarPlayersDisplayMode.CARDS ||
            isSubmittingSwipe ||
            visibleUsers.isEmpty() ||
            isSimilarPlayersHintPresented ||
            isFirstInterestHintPresented ||
            isSimilarPlayersHintScheduled
        ) {
            return
        }

        isSimilarPlayersHintScheduled = true
        scope.launch {
            try {
                delay(420)
                if (appModel.shouldPresentDiscoverSimilarPlayersHint() &&
                    selectedTab == DiscoverTab.SWIPE &&
                    similarMode == SimilarPlayersDisplayMode.CARDS &&
                    !isSubmittingSwipe &&
                    visibleUsers.isNotEmpty() &&
                    !isFirstInterestHintPresented &&
                    !isSimilarPlayersHintPresented
                ) {
                    appModel.consumeDiscoverSimilarPlayersHint()
                    isSimilarPlayersHintPresented = true
                }
            } finally {
                isSimilarPlayersHintScheduled = false
            }
        }
    }

    fun dismissSimilarPlayersHint() {
        if (isSimilarPlayersHintDismissing) return
        isSimilarPlayersHintDismissing = true
        haptics.selection()
        appModel.completeDiscoverSimilarPlayersHint()
        similarPlayersHintDemoPhase = 0
        isSimilarPlayersHintPresented = false
    }

    fun scheduleFirstInterestHintIfNeeded(playerName: String? = null) {
        if (!appModel.shouldPresentDiscoverFirstInterestHint() ||
            (selectedTab == DiscoverTab.SWIPE && similarMode != SimilarPlayersDisplayMode.CARDS) ||
            isSimilarPlayersHintPresented ||
            isFirstInterestHintPresented ||
            isFirstInterestHintScheduled
        ) {
            return
        }

        if (playerName != null) firstInterestHintPlayerName = playerName

        isFirstInterestHintScheduled = true
        scope.launch {
            try {
                delay(360)
                if (appModel.shouldPresentDiscoverFirstInterestHint() &&
                    (selectedTab != DiscoverTab.SWIPE || similarMode == SimilarPlayersDisplayMode.CARDS) &&
                    !isSimilarPlayersHintPresented &&
                    !isFirstInterestHintPresented
                ) {
                    appModel.consumeDiscoverFirstInterestHint()
                    isFirstInterestHintPresented = true
                }
            } finally {
                isFirstInterestHintScheduled = false
            }
        }
    }

    // `.task(id: isSimilarPlayersHintPresented) { await runSimilarPlayersHintDemoLoop() }`
    LaunchedEffect(isSimilarPlayersHintPresented) {
        if (!isSimilarPlayersHintPresented) return@LaunchedEffect
        while (true) {
            delay(360)
            similarPlayersHintDemoPhase = -1
            delay(780)
            similarPlayersHintDemoPhase = 0
            delay(390)
            similarPlayersHintDemoPhase = 1
            delay(780)
            similarPlayersHintDemoPhase = 0
            delay(780)
        }
    }

    // The overlays cover the tab bar, exactly as the iOS `.onChange` below does.
    LaunchedEffect(isSimilarPlayersHintPresented, isFirstInterestHintPresented) {
        appModel.bottomBarDisplayMode = if (isSimilarPlayersHintPresented || isFirstInterestHintPresented) {
            BottomBarDisplayMode.HIDDEN
        } else {
            BottomBarDisplayMode.EXPANDED
        }
    }

    suspend fun loadDiscover() {
        isLoading = true
        appModel.setTabContentLoading("discover", true)
        users = runCatching {
            if (appModel.isAuthenticated) {
                appModel.repository.fetchDiscoverUsers(selectedTab)
            } else {
                appModel.repository.fetchGuestDiscoverUsers(appModel.guestDraft, selectedTab)
            }
        }.getOrElse {
            appModel.present(it)
            emptyList()
        }

        if (selectedTab == DiscoverTab.UPCOMING && appModel.isAuthenticated) {
            upcomingRequests = runCatching { appModel.repository.fetchMyGameRequests() }.getOrDefault(emptyList())
            upcomingMatches = runCatching { appModel.repository.fetchMatches() }.getOrDefault(emptyList())
            personalActivities = runCatching { appModel.repository.fetchPersonalActivities() }.getOrDefault(emptyList())
            appModel.hasActiveUpcomingGameRequests = upcomingRequests.isNotEmpty()
            UpcomingGamesWidgetStore.save(
                context = androidContext,
                gameRequests = upcomingRequests.filterNot { it.isArchivedForTimeline },
                personalActivities = personalActivities.filterNot { it.isArchivedForTimeline },
                currentUserId = appModel.currentUser?.id,
            )
            UpcomingGamesWidget().updateAll(androidContext)
        } else if (!appModel.isAuthenticated) {
            UpcomingGamesWidgetStore.clear(androidContext)
            UpcomingGamesWidget().updateAll(androidContext)
        }

        appModel.setTabContentLoading("discover", false)
        isLoading = false
    }

    LaunchedEffect(selectedTab, appModel.currentUser?.id) {
        loadDiscover()
        scheduleSimilarPlayersHintIfNeeded()
        scheduleFirstInterestHintIfNeeded()
    }

    // `.onChange(of: similarPlayersDisplayMode)` - the hints only make sense on cards.
    LaunchedEffect(similarMode, isSubmittingSwipe, visibleUsers.isEmpty()) {
        if (selectedTab == DiscoverTab.SWIPE && similarMode == SimilarPlayersDisplayMode.CARDS) {
            scheduleSimilarPlayersHintIfNeeded()
            scheduleFirstInterestHintIfNeeded()
        }
    }

    // `loadEmptyDeckContent()` - clubs and the invite link behind the empty deck.
    suspend fun loadEmptyDeckContent() {
        isLoadingEmptyDeck = true
        emptyDeckFailed = false
        val sports = appModel.currentUser?.preferredSports ?: appModel.guestDraft.preferredSports
        runCatching {
            appModel.repository.fetchEmptyDeckContent(
                city = appModel.currentUser?.city ?: appModel.guestDraft.city,
                locationPlaceId = appModel.currentUser?.location?.id ?: appModel.guestDraft.location?.id,
                sports = sports.takeIf { it.isNotEmpty() },
            )
        }.onSuccess { content ->
            emptyDeckSections = content.sections
            hasLoadedEmptyDeck = true
        }.onFailure { emptyDeckFailed = true }

        if (appModel.isAuthenticated) {
            inviteSummary = runCatching { appModel.repository.fetchInviteSummary() }.getOrNull()
            mySearches = runCatching { appModel.repository.fetchSearches() }.getOrDefault(emptyList())
        }
        isLoadingEmptyDeck = false
    }

    LaunchedEffect(appModel.currentUser?.id, appModel.guestDraft.city) { loadEmptyDeckContent() }

    routeSport?.let { (sport, points) ->
        HideBottomBarWhileVisible(appModel)
        RunningRouteDetailSheet(
            title = routeTitle,
            sport = sport,
            points = points,
            onDismiss = { routeSport = null },
        )
        return
    }

    if (isNotificationsPresented) {
        NotificationsScreen(appModel = appModel, onBack = { isNotificationsPresented = false })
        return
    }

    // Full-screen destinations reached from the upcoming cards.
    photoReportRequest?.let { request ->
        GameReportComposerSheet(
            appModel = appModel,
            request = request,
            onDismiss = { photoReportRequest = null },
            onSubmitted = {
                responseMessage = L10n.string("Photo report saved.", "Фотоотчёт сохранён.")
                loadDiscover()
            },
        )
        return
    }

    activityReport?.let { activity ->
        PersonalActivityReportComposerSheet(
            appModel = appModel,
            activity = activity,
            onDismiss = { activityReport = null },
            onSubmitted = { loadDiscover() },
        )
        return
    }

    gallery?.let { item ->
        HideBottomBarWhileVisible(appModel)
        ReportPhotoGallerySheet(item = item, onDismiss = { gallery = null })
        return
    }

    selectedParticipant?.let { participant ->
        HideBottomBarWhileVisible(appModel)
        DiscoverParticipantSheet(
            appModel = appModel,
            user = participant,
            onDismiss = { selectedParticipant = null },
        )
        return
    }

    chatMatch?.let { match ->
        ChatScreen(appModel = appModel, match = match, onBack = { chatMatch = null })
        return
    }

    // `presentHotSearchMapCluster` - a tap on a cluster whose members share a
    // coordinate opens the picker; anything else the map zooms into itself.
    if (hotSearchMapClusterItemIds.isNotEmpty()) {
        val viewerCenter = SupportedCity.resolve(appModel.currentUser?.city ?: appModel.guestDraft.city)
            ?: SupportedCity.SAINT_PETERSBURG
        val clusterItems = users
            .flatMap { user -> user.gameSearches.map { ActiveHotSearchItem(user, it, viewerCenter.mapCenter) } }
            .filter { hotSearchMapClusterItemIds.contains(it.id) }
            .distinctBy { it.search.id }

        if (clusterItems.size < 2) {
            hotSearchMapClusterItemIds = emptyList()
            clusterItems.firstOrNull()?.let { selectedHotSearchMapItemId = it.id }
        } else {
            HideBottomBarWhileVisible(appModel)
            ActiveHotSearchClusterPickerSheet(
                items = clusterItems,
                onDismiss = { hotSearchMapClusterItemIds = emptyList() },
                onSelect = { itemId ->
                    selectedHotSearchMapItemId = itemId
                    hotSearchMapClusterItemIds = emptyList()
                },
            )
            return
        }
    }

    if (isWidgetHelpPresented) {
        HideBottomBarWhileVisible(appModel)
        UpcomingWidgetHelpSheet(
            onConfirm = {
                isWidgetPromptDismissed = true
                widgetPrefs.edit().putBoolean(WIDGET_PROMPT_DISMISSED_KEY, true).apply()
            },
            onDismiss = { isWidgetHelpPresented = false },
        )
        return
    }

    regularPairId?.let { pairId ->
        RegularPairDetailSheet(
            appModel = appModel,
            regularPairId = pairId,
            onDismiss = { regularPairId = null },
        )
        return
    }

    upcomingCourt?.let { court ->
        HideBottomBarWhileVisible(appModel)
        UpcomingCourtDetailSheet(court = court, onDismiss = { upcomingCourt = null })
        return
    }

    detailsRequest?.let { request ->
        HideBottomBarWhileVisible(appModel)
        val match = upcomingMatches.firstOrNull { it.id == request.matchId }
        UpcomingGameDetailsSheet(
            appModel = appModel,
            request = request,
            displayName = request.upcomingDisplayName(appModel.currentUser?.id),
            avatarUrl = request.upcomingAvatarUrl(appModel.currentUser?.id),
            isUpdating = updatingRequestIds.contains(request.id),
            canEdit = canEditUpcomingRequest(request) && match != null,
            canCancel = canManageUpcomingRequest(request),
            cancelTitle = if (request.createdByUserId == appModel.currentUser?.id) {
                L10n.string("Cancel game", "Отменить игру")
            } else {
                L10n.string("I can't make it", "Не смогу")
            },
            onDismiss = { detailsRequest = null },
            onEdit = {
                detailsRequest = null
                editGameRequest = request
            },
            onCancel = {
                updatingRequestIds = updatingRequestIds + request.id
                runCatching { appModel.repository.updateGameRequestStatus(request.id, "canceled") }
                    .onSuccess {
                        haptics.warning()
                        responseMessage = if (request.createdByUserId == appModel.currentUser?.id) {
                            L10n.string("Game canceled.", "Игра отменена.")
                        } else {
                            L10n.string("We let them know you cannot play.", "Отправили, что не сможешь сыграть.")
                        }
                        loadDiscover()
                    }
                    .onFailure(appModel::present)
                updatingRequestIds = updatingRequestIds - request.id
                detailsRequest = null
            },
            onOpenCourt = { court ->
                detailsRequest = null
                upcomingCourt = court
            },
            onParticipantsChanged = { loadDiscover() },
        )
        return
    }

    // `selectedEditGameRequest` - the composer reopened on an existing game.
    editGameRequest?.let { request ->
        val match = upcomingMatches.firstOrNull { it.id == request.matchId }
        if (match == null) {
            editGameRequest = null
        } else {
            GameProposalSheet(
                appModel = appModel,
                match = match,
                context = ProposalSheetContext.EDIT,
                seedRequest = request,
                onDismiss = { editGameRequest = null },
                onCreated = {
                    editGameRequest = null
                    loadDiscover()
                },
            )
            return
        }
    }

    shareRequest?.let { request ->
        HideBottomBarWhileVisible(appModel)
        ShareExistingGameSheet(
            request = request,
            matches = shareableMatches(request, upcomingMatches),
            onDismiss = { shareRequest = null },
            onShare = { matchIds ->
                if (matchIds.isNotEmpty()) {
                    updatingRequestIds = updatingRequestIds + request.id
                    runCatching {
                        appModel.repository.shareGameRequest(request.rootRequestId ?: request.id, matchIds)
                    }.onSuccess { created ->
                        haptics.success()
                        shareRequest = null
                        responseMessage = if (created.size == 1) {
                            L10n.string("Invitation sent", "Приглашение отправлено")
                        } else {
                            L10n.string("Invitations sent", "Приглашения отправлены")
                        }
                        loadDiscover()
                        appModel.refreshActivitySummary()
                    }.onFailure(appModel::present)
                    updatingRequestIds = updatingRequestIds - request.id
                }
            },
        )
        return
    }

    proposalMatch?.let { match ->
        GameProposalSheet(
            appModel = appModel,
            match = match,
            onDismiss = { proposalMatch = null },
            onCreated = {
                proposalMatch = null
                loadDiscover()
            },
        )
        return
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            stickyHeaderRow {
                DiscoverHeaderRow(
                    appModel = appModel,
                    onOpenNotifications = { isNotificationsPresented = true },
                ) {
                DiscoverTabBar(
                    trailing = {
                        // iOS keeps this control inside the same scrolling row as the pills.
                        if (selectedTab == DiscoverTab.SWIPE && users.isNotEmpty()) {
                            SimilarPlayersModeControl(mode = similarMode, isEnabled = true) {
                                similarMode = it
                                haptics.selection()
                            }
                        } else if (selectedTab == DiscoverTab.HOT || selectedTab == DiscoverTab.SEEKING) {
                            ActiveHotSearchDisplayControl(hotSearchDisplayMode) {
                                hotSearchDisplayMode = it
                                haptics.selection()
                            }
                        }
                    },
                    selected = selectedTab,
                    badgeFor = { tab ->
                        if (!appModel.isAuthenticated) {
                            null
                        } else when (tab) {
                            // Only the games waiting on this player. Counting every scheduled
                            // game gives a badge that never reaches zero, and one of those is
                            // ignored. Mirrors `tabBadgeCount` in DiscoverView.swift.
                            DiscoverTab.UPCOMING -> upcomingRequests
                                .count { !it.isArchivedForTimeline && it.isPendingForRecipient(appModel.currentUser?.id) }
                                .takeIf { it > 0 }
                            DiscoverTab.LIKES -> appModel.activitySummary.incomingLikesCount.takeIf { it > 0 }
                            // Server-side count of hot events newer than lastNotificationsSeenAt.
                            DiscoverTab.HOT -> appModel.activitySummary.hotBadgeCount.takeIf { it > 0 }
                            // The similar-players feed has no honest "new since last visit"
                            // number: it is fetched only while its own tab is open.
                            else -> null
                        }
                    },
                    onSelect = { tab ->
                        haptics.selection()
                        selectedTab = tab
                        onTabChanged(tab)
                    },
                )
                }
            }

            matchMessage?.let { item { MatchSuccessToast(it) } }
            responseMessage?.let { item { InlineToast(it) } }

            when (selectedTab) {
                DiscoverTab.UPCOMING -> upcomingContent(
                    appModel = appModel,
                    requests = upcomingRequests,
                    matches = upcomingMatches,
                    personalActivities = personalActivities,
                    isLoading = isLoading,
                    isHistoryExpanded = isUpcomingHistoryExpanded,
                    isWidgetPromptDismissed = isWidgetPromptDismissed,
                    onOpenWidgetHelp = { isWidgetHelpPresented = true },
                    updatingRequestIds = updatingRequestIds,
                    updatingActivityIds = updatingActivityIds,
                    onToggleHistory = { isUpcomingHistoryExpanded = !isUpcomingHistoryExpanded },
                    onSelectParticipant = { selectedParticipant = it },
                    onOpenChat = { request ->
                        request.searchLobbyId?.let { appModel.navigate(AppNavigationTarget.SearchLobby(it)) }
                            ?: upcomingMatches.firstOrNull { it.id == request.matchId }
                                ?.let { chatMatch = it }
                    },
                    onOpenDetails = { detailsRequest = it },
                    onOpenCourt = { upcomingCourt = it },
                    onShare = { shareRequest = it },
                    onAccept = { request ->
                        scope.launch {
                            updatingRequestIds = updatingRequestIds + request.id
                            runCatching { appModel.repository.updateGameRequestStatus(request.id, "accepted") }
                                .onSuccess {
                                    haptics.success()
                                    responseMessage = L10n.string("Game confirmed.", "Игра подтверждена.")
                                    loadDiscover()
                                }
                                .onFailure(appModel::present)
                            updatingRequestIds = updatingRequestIds - request.id
                        }
                    },
                    onCancel = { request ->
                        scope.launch {
                            updatingRequestIds = updatingRequestIds + request.id
                            runCatching { appModel.repository.updateGameRequestStatus(request.id, "canceled") }
                                .onSuccess {
                                    haptics.warning()
                                    responseMessage = if (request.createdByUserId == appModel.currentUser?.id) {
                                        L10n.string("Game canceled.", "Игра отменена.")
                                    } else {
                                        L10n.string("We let them know you cannot play.", "Отправили, что не сможешь сыграть.")
                                    }
                                    loadDiscover()
                                }
                                .onFailure(appModel::present)
                            updatingRequestIds = updatingRequestIds - request.id
                        }
                    },
                    onMarkOutcome = { request, outcome ->
                        scope.launch {
                            updatingRequestIds = updatingRequestIds + request.id
                            runCatching { appModel.repository.updateGameRequestOutcome(request.id, outcome) }
                                .onSuccess {
                                    responseMessage = if (outcome == "played") {
                                        L10n.string("Marked as played.", "Отметили, что игра прошла.")
                                    } else {
                                        L10n.string("Marked as not played.", "Отметили, что сыграть не удалось.")
                                    }
                                    loadDiscover()
                                }
                                .onFailure(appModel::present)
                            updatingRequestIds = updatingRequestIds - request.id
                        }
                    },
                    onAddPhotoReport = { photoReportRequest = it },
                    onProposeNext = { request ->
                        upcomingMatches.firstOrNull { it.id == request.matchId }?.let { proposalMatch = it }
                    },
                    onActivityReport = { activityReport = it },
                    onActivityComplete = { activity ->
                        scope.launch {
                            updatingActivityIds = updatingActivityIds + activity.id
                            runCatching {
                                appModel.repository.updatePersonalActivity(
                                    activity.id,
                                    PersonalActivityUpdateDraft(status = "completed"),
                                )
                            }.onSuccess {
                                responseMessage = L10n.string("Visit completed.", "Визит завершён.")
                                loadDiscover()
                            }.onFailure(appModel::present)
                            updatingActivityIds = updatingActivityIds - activity.id
                        }
                    },
                    onActivityCancel = { activity ->
                        scope.launch {
                            updatingActivityIds = updatingActivityIds + activity.id
                            runCatching {
                                appModel.repository.updatePersonalActivity(
                                    activity.id,
                                    PersonalActivityUpdateDraft(status = "canceled"),
                                )
                            }.onSuccess {
                                responseMessage = L10n.string("Visit canceled.", "Визит отменён.")
                                loadDiscover()
                            }.onFailure(appModel::present)
                            updatingActivityIds = updatingActivityIds - activity.id
                        }
                    },
                    onOpenGallery = { gallery = it },
                    onCreateSearch = {
                        // `presentHotSearchComposer()`
                        if (appModel.isAuthenticated) {
                            appModel.navigate(AppNavigationTarget.Searches)
                        } else {
                            appModel.presentAuth(AuthStep.EMAIL)
                        }
                    },
                )
                DiscoverTab.SWIPE -> {
                    if (deckUsers.isNotEmpty() && similarMode == SimilarPlayersDisplayMode.CARDS) {
                        item {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                SwipeHintBar(
                                    leftTitle = if (viewedUsers.isEmpty()) {
                                        L10n.string("Left — skip", "Влево — пропустить")
                                    } else {
                                        L10n.string("Skip", "Пропустить")
                                    },
                                    rightTitle = if (viewedUsers.isEmpty()) {
                                        L10n.string("Right — ready to play", "Вправо — можно сыграть")
                                    } else {
                                        L10n.string("Play", "Играть")
                                    },
                                    isHighlighted = isSimilarPlayersHintPresented,
                                    modifier = Modifier.weight(1f),
                                )
                                if (viewedUsers.isNotEmpty()) {
                                    ShowViewedPlayersButton(viewedUsers.size, !isSubmittingSwipe) {
                                        haptics.selection()
                                    }
                                }
                            }
                        }
                    }

                    when {
                        users.isEmpty() && !isLoading -> item {
                            EmptyDeckView(
                                city = appModel.currentUser?.city ?: appModel.guestDraft.city,
                                preferredSports = appModel.currentUser?.preferredSports
                                    ?: appModel.guestDraft.preferredSports,
                                sections = emptyDeckSections,
                                invite = inviteSummary,
                                hasActiveSearch = mySearches.any {
                                    (it.isActive ?: true) && it.status.lowercase() in setOf("active", "in_review")
                                },
                                isLoading = isLoadingEmptyDeck,
                                hasLoaded = hasLoadedEmptyDeck,
                                loadFailed = emptyDeckFailed,
                                onCreateSearch = {
                                    appModel.navigate(
                                        AppNavigationTarget.CreateSearch(
                                            CreateSearchPrefill.from(null, null, null),
                                        ),
                                    )
                                },
                                onManageSearches = { appModel.navigate(AppNavigationTarget.Searches) },
                                onOpenCourt = { court, sport ->
                                    haptics.selection()
                                    appModel.pendingCourtID = court.id
                                    appModel.navigate(AppNavigationTarget.Courts(sport))
                                },
                                onOpenClubs = { sport ->
                                    haptics.selection()
                                    appModel.navigate(AppNavigationTarget.Courts(sport))
                                },
                                onRetry = { scope.launch { loadEmptyDeckContent() } },
                            )
                        }

                        // The grid stands on the raw deck, not the map-filtered list, so
                        // its own empty state is what shows when nobody opted into the map.
                        similarMode == SimilarPlayersDisplayMode.GRID && users.isNotEmpty() -> {
                            item {
                                SimilarPlayersMapGrid(
                                    users = visibleUsers,
                                    layoutUsers = users,
                                    availableSports = appModel.currentUser?.preferredSports
                                        ?: appModel.guestDraft.preferredSports,
                                    selectedSport = similarSportFilter,
                                    selectedPlayerId = selectedSimilarPlayerId,
                                    isEnabled = true,
                                    onSelectSport = { similarSportFilter = it; haptics.selection() },
                                    onSelectMapPlayer = { selectedSimilarPlayerId = it; haptics.selection() },
                                    onShowCards = { similarMode = SimilarPlayersDisplayMode.CARDS },
                                    onOpenPlayer = { selectedParticipant = it },
                                )
                            }

                            // `tiles` - the two-column grid under the map.
                            items(((visibleUsers.size + 1) / 2)) { row ->
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    visibleUsers.drop(row * 2).take(2).forEach { user ->
                                        SimilarPlayerGridTile(
                                            user = user,
                                            selectedSport = similarSportFilter,
                                            isSelected = selectedSimilarPlayerId == user.id,
                                            modifier = Modifier.weight(1f),
                                        ) { selectedParticipant = user }
                                    }
                                    if (visibleUsers.drop(row * 2).take(2).size == 1) {
                                        Spacer(Modifier.weight(1f))
                                    }
                                }
                            }
                        }

                        visibleUsers.isEmpty() && !isLoading -> item {
                            SimilarPlayersFilteredEmptyState { similarSportFilter = null }
                        }

                        else -> item {
                            SwipeDeck(
                                users = deckUsers,
                                isLoading = isLoading,
                                isSubmitting = isSubmittingSwipe,
                                hintDemoPhase = if (isSimilarPlayersHintPresented) similarPlayersHintDemoPhase else null,
                                onPlaybackComplete = { user ->
                                    if (deckUsers.any { it.id != user.id }) {
                                        viewedPlayers = viewedPlayers.deferPlayer(user.id)
                                        selectedSimilarPlayerId = null
                                    }
                                },
                                onSwipe = { user, action ->
                                    // `submitSwipe(_:userID:)` - a guest cannot send
                                    // interest; the like turns into a sign-in prompt.
                                    if (!appModel.isAuthenticated &&
                                        (action == SwipeAction.LIKE || action == SwipeAction.SUPERLIKE)
                                    ) {
                                        appModel.consumeDiscoverFirstInterestHint()
                                        appModel.presentAuth(AuthStep.EMAIL)
                                        return@SwipeDeck
                                    }

                                    // A guest's swipe never leaves the device: the card is
                                    // dropped locally and nothing is sent, so a decline works
                                    // without an account.
                                    if (!appModel.isAuthenticated) {
                                        users = users.filterNot { it.id == user.id }
                                        viewedPlayers = viewedPlayers.remove(user.id)
                                        if (selectedSimilarPlayerId == user.id) selectedSimilarPlayerId = null
                                        return@SwipeDeck
                                    }

                                    // A decline is optimistic and fire-and-forget: the card goes
                                    // at once and the request is not awaited, so a failure never
                                    // interrupts swiping (`try?` on the iOS side).
                                    if (action == SwipeAction.DISLIKE) {
                                        users = users.filterNot { it.id == user.id }
                                        viewedPlayers = viewedPlayers.remove(user.id)
                                        if (selectedSimilarPlayerId == user.id) selectedSimilarPlayerId = null
                                        scope.launch {
                                            runCatching { appModel.repository.swipe(user.id, action) }
                                        }
                                        return@SwipeDeck
                                    }

                                    isSubmittingSwipe = true
                                    scope.launch {
                                        runCatching { appModel.repository.swipe(user.id, action) }
                                            .onSuccess { createdMatchId ->
                                                if (createdMatchId != null && action == SwipeAction.LIKE) {
                                                    matchMessage = L10n.string(
                                                        "You matched with ${user.displayName}.",
                                                        "С ${user.displayName} случился новый мэтч.",
                                                    )
                                                }
                                            }
                                            .onFailure { appModel.present(it) }
                                        users = users.filterNot { it.id == user.id }
                                        viewedPlayers = viewedPlayers.remove(user.id)
                                        if (selectedSimilarPlayerId == user.id) selectedSimilarPlayerId = null
                                        isSubmittingSwipe = false
                                        appModel.refreshActivitySummary()
                                        if (action == SwipeAction.LIKE || action == SwipeAction.SUPERLIKE) {
                                            firstInterestHintPlayerName = user.displayName
                                            if (appModel.queueDiscoverFirstInterestHintIfNeeded()) {
                                                scheduleFirstInterestHintIfNeeded(user.displayName)
                                            }
                                        }
                                    }
                                },
                            )
                        }
                    }

                    if (similarMode == SimilarPlayersDisplayMode.CARDS && viewedUsers.isNotEmpty()) {
                        item {
                            ViewedPlayersTray(
                                users = viewedUsers,
                                currentUserId = activeUser?.id,
                                isEnabled = !isSubmittingSwipe,
                            ) { userId ->
                                haptics.selection()
                                selectedSimilarPlayerId = userId
                            }
                        }
                    }
                }
                DiscoverTab.LIKES -> likesContent(appModel, users, isLoading)
                DiscoverTab.SEEKING, DiscoverTab.HOT -> searchContent(
                    appModel = appModel,
                    users = users,
                    isLoading = isLoading,
                    sportFilter = hotSearchSportFilter,
                    hotFilter = hotSearchFilter,
                    calendarDate = hotSearchCalendarDate,
                    displayMode = hotSearchDisplayMode,
                    selectedMapItemId = selectedHotSearchMapItemId,
                    onSelectMapItem = { selectedHotSearchMapItemId = it; haptics.selection() },
                    onSelectMapCluster = { ids -> hotSearchMapClusterItemIds = ids },
                    localResponseStatuses = localResponseStatuses,
                    localResponseIds = localResponseIds,
                    onSelectSport = { hotSearchSportFilter = it; haptics.selection() },
                    onSelectHotFilter = { hotSearchFilter = it; haptics.selection() },
                    onSelectCalendarDate = { hotSearchCalendarDate = it },
                    onOpenUser = { selectedParticipant = it },
                    onOpenCourt = { court ->
                        appModel.pendingCourtID = court.id
                        appModel.navigate(AppNavigationTarget.Courts(null))
                    },
                    onOpenApprovedChat = { search ->
                        // `openApprovedRegularPair(for:)` - парный поиск ведёт в
                        // лист регулярной пары, а не в лобби на несколько человек.
                        val pairId = search.regularPair?.id
                        if (search.playersNeeded > 1 || pairId == null) {
                            appModel.navigate(AppNavigationTarget.SearchLobby(search.id))
                        } else {
                            haptics.selection()
                            regularPairId = pairId
                        }
                    },
                    onRespond = { search ->
                        // `respond(to:)` - a guest is sent to sign-in instead.
                        if (!appModel.isAuthenticated) {
                            appModel.presentAuth(AuthStep.EMAIL)
                            return@searchContent
                        }
                        scope.launch {
                            val status = localResponseStatuses[search.id]
                                ?: search.responses.firstOrNull { it.responderUser.id == appModel.currentUser?.id }?.status
                            if (status == "pending") {
                                val responseId = localResponseIds[search.id]
                                    ?: search.responses.firstOrNull {
                                        it.responderUser.id == appModel.currentUser?.id
                                    }?.id
                                if (responseId != null) {
                                    runCatching { appModel.repository.withdrawSearchResponse(responseId) }
                                        .onSuccess {
                                            localResponseStatuses = localResponseStatuses - search.id
                                            localResponseIds = localResponseIds - search.id
                                            haptics.warning()
                                            responseMessage = L10n.string("Response withdrawn.", "Отклик отменён.")
                                        }
                                        .onFailure(appModel::present)
                                }
                            } else {
                                runCatching { appModel.repository.respondToSearch(search.id, "") }
                                    .onSuccess { response ->
                                        localResponseStatuses = localResponseStatuses + (search.id to response.status)
                                        localResponseIds = localResponseIds + (search.id to response.id)
                                        haptics.success()
                                        responseMessage = L10n.string(
                                            "Response sent. The organizer will now see you in their search.",
                                            "Отклик отправлен. Дальше организатор увидит тебя в своих поисках.",
                                        )
                                    }
                                    .onFailure(appModel::present)
                            }
                        }
                    },
                    onCreateSearch = {
                        // `presentHotSearchComposer()`
                        if (appModel.isAuthenticated) {
                            appModel.navigate(AppNavigationTarget.Searches)
                        } else {
                            appModel.presentAuth(AuthStep.EMAIL)
                        }
                    },
                    onOpenRoute = { search ->
                        routeTitle = search.runningRoute ?: search.sport.routeDefaultTitle
                        routeSport = search.sport to search.runningRoutePoints
                    },
                )
            }
        }

        // `.overlay { … }` - the tutorials sit above the whole Discover tab.
        if (isSimilarPlayersHintPresented) {
            DiscoverSimilarPlayersHintOverlay(onDismiss = ::dismissSimilarPlayersHint)
        } else if (isFirstInterestHintPresented) {
            DiscoverFirstInterestHintOverlay(
                playerName = firstInterestHintPlayerName,
                onDismiss = {
                    haptics.selection()
                    appModel.completeDiscoverFirstInterestHint()
                    isFirstInterestHintPresented = false
                },
            )
        }
    }
}

/**
 * The SwiftUI header is a pinned `Section` header. LazyColumn's stickyHeader is
 * still experimental, so the row scrolls with the content for now.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.stickyHeaderRow(
    content: @Composable () -> Unit,
) = item { content() }

/** Port of `tabBar` in DiscoverView.swift: pills that expand to show a label when selected. */
@Composable
private fun DiscoverTabBar(
    selected: DiscoverTab,
    badgeFor: (DiscoverTab) -> Int?,
    onSelect: (DiscoverTab) -> Unit,
    trailing: @Composable () -> Unit = {},
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Black)
            .padding(vertical = 6.dp)
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        DiscoverTab.userVisibleCases.forEach { tab ->
            val isSelected = tab == selected
            val shape = continuousShape(22.dp)

            Box {
                Row(
                    modifier = Modifier
                        .heightIn(min = 44.dp)
                        .clip(shape)
                        .background(if (isSelected) Color.White else Color.White.copy(alpha = 0.08f))
                        .border(
                            width = if (isSelected) 1.2.dp else 1.dp,
                            color = if (isSelected) AppTheme.line else Color.White.copy(alpha = 0.8f).copy(alpha = 0.12f),
                            shape = shape,
                        )
                        .clickable { onSelect(tab) }
                        .padding(horizontal = if (isSelected) 14.dp else 12.dp, vertical = 11.dp),
                    horizontalArrangement = Arrangement.spacedBy(if (isSelected) 7.dp else 0.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        tab.icon,
                        contentDescription = tab.title,
                        tint = if (isSelected) AppTheme.ink else Color.White.copy(alpha = 0.86f),
                        modifier = Modifier.size(20.dp),
                    )
                    if (isSelected) {
                        Text(
                            tab.title,
                            style = AppText.subheadlineSemibold,
                            color = AppTheme.ink,
                            maxLines = 2,
                        )
                    }
                }

                // A badge exists to pull the player to a tab they are not on; on the
                // open tab it is noise. Same rule as `discoverPrimaryTabLabel`.
                badgeFor(tab).takeIf { !isSelected }?.let { count ->
                    Text(
                        minOf(count, 99).toString(),
                        style = AppText.caption2Semibold.copy(fontWeight = FontWeight.Bold),
                        color = Color.White,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(top = 0.dp)
                            .background(AppTheme.clay, RoundedCornerShape(percent = 50))
                            .padding(horizontal = 6.dp, vertical = 3.dp),
                    )
                }
            }
        }

        trailing()
    }
}

/** Port of `swipeContent` + the drag gesture that drives the deck. */
@Composable
private fun SwipeDeck(
    users: List<DiscoverUser>,
    isLoading: Boolean,
    isSubmitting: Boolean,
    hintDemoPhase: Int?,
    onPlaybackComplete: (DiscoverUser) -> Unit,
    onSwipe: (DiscoverUser, SwipeAction) -> Unit,
) {
    if (users.isEmpty()) {
        if (!isLoading) {
            DarkEmptyState(
                title = L10n.string("No players nearby yet", "Пока нет игроков рядом"),
                subtitle = L10n.string(
                    "Create an urgent search or widen your area — new players appear every day.",
                    "Создай срочный поиск или расширь район — новые игроки появляются каждый день.",
                ),
            )
        }
        return
    }

    val haptics = rememberAppHaptics()
    val density = LocalDensity.current
    var dragOffsetX by remember { mutableFloatStateOf(0f) }
    var decision by remember { mutableStateOf<SwipeAction?>(null) }
    var storyIndex by remember { mutableIntStateOf(0) }
    var storyProgress by remember { mutableFloatStateOf(0f) }

    val topStack = users.take(3)
    val topUser = topStack.first()

    // `PlayerMediaPlaybackClock`: 10s per story item, advancing through up to six.
    LaunchedEffect(topUser.id, hintDemoPhase != null) {
        storyIndex = 0
        storyProgress = 0f
        if (hintDemoPhase != null) return@LaunchedEffect
        val count = topUser.playerCardMediaItems.size.coerceIn(1, 6)
        while (true) {
            delay(100)
            storyProgress += 0.01f
            if (storyProgress >= 1f) {
                storyProgress = 0f
                if (storyIndex == count - 1) {
                    // `completePlayerMedia(userID:)` - the card played through.
                    onPlaybackComplete(topUser)
                    return@LaunchedEffect
                }
                storyIndex += 1
            }
        }
    }

    // `similarPlayersHintDemoOffset` / `similarPlayersHintDemoDecision` - while the
    // tutorial is up the demo phase drives the top card, not the finger.
    val demoOffset = with(density) { ((hintDemoPhase ?: 0) * 56).dp.toPx() }
    val demoDecision = when (hintDemoPhase) {
        -1 -> SwipeAction.DISLIKE
        1 -> SwipeAction.LIKE
        else -> null
    }

    val animatedOffset by animateFloatAsState(
        targetValue = if (hintDemoPhase != null) demoOffset else dragOffsetX,
        label = "cardOffset",
    )

    // `swipeDeckMinHeight`: min(max(screenHeight * 0.54, 440), 500)
    val deckHeight = (LocalConfiguration.current.screenHeightDp * 0.54f).coerceIn(440f, 500f).dp

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(deckHeight)
            .pointerInput(topUser.id, isSubmitting, hintDemoPhase != null) {
                if (isSubmitting || hintDemoPhase != null) return@pointerInput
                val threshold = with(density) { 110.dp.toPx() }
                detectHorizontalDragGestures(
                    onDragEnd = {
                        when {
                            dragOffsetX > threshold -> {
                                haptics.impactMedium()
                                onSwipe(topUser, SwipeAction.LIKE)
                            }
                            dragOffsetX < -threshold -> {
                                haptics.impactLight()
                                onSwipe(topUser, SwipeAction.DISLIKE)
                            }
                        }
                        dragOffsetX = 0f
                        decision = null
                    },
                    onDragCancel = {
                        dragOffsetX = 0f
                        decision = null
                    },
                ) { change, dragAmount ->
                    change.consume()
                    dragOffsetX += dragAmount
                    decision = when {
                        dragOffsetX > 40f -> SwipeAction.LIKE
                        dragOffsetX < -40f -> SwipeAction.DISLIKE
                        else -> null
                    }
                }
            },
    ) {
        if (hintDemoPhase != null) {
            TutorialSwipeDecisionZones()
        }

        // Back cards first so the top card paints last.
        topStack.drop(1).reversed().forEachIndexed { reversedIndex, user ->
            val index = topStack.size - 1 - reversedIndex
            SwipeCard(
                user = user,
                index = index,
                dragOffsetX = 0f,
                decision = null,
                storyIndex = 0,
                storyProgress = 0f,
                modifier = Modifier.graphicsLayer {
                    scaleX = 0.965f - index * 0.02f
                    scaleY = 0.965f - index * 0.02f
                    translationY = index * 14f * this.density
                },
            )
        }

        SwipeCard(
            user = topUser,
            index = 0,
            dragOffsetX = animatedOffset,
            decision = if (hintDemoPhase != null) demoDecision else decision,
            storyIndex = storyIndex,
            storyProgress = storyProgress,
            onDislike = { onSwipe(topUser, SwipeAction.DISLIKE) },
            onLike = { onSwipe(topUser, SwipeAction.LIKE) },
        )
    }
}

/** Port of `upcomingContent`. */
private fun androidx.compose.foundation.lazy.LazyListScope.upcomingContent(
    appModel: AppViewModel,
    requests: List<MatchGameRequest>,
    matches: List<MatchSummary>,
    personalActivities: List<PersonalActivity>,
    isLoading: Boolean,
    isHistoryExpanded: Boolean,
    isWidgetPromptDismissed: Boolean,
    onOpenWidgetHelp: () -> Unit,
    updatingRequestIds: Set<String>,
    updatingActivityIds: Set<String>,
    onToggleHistory: () -> Unit,
    onSelectParticipant: (DiscoverUser) -> Unit,
    onOpenChat: (MatchGameRequest) -> Unit,
    onOpenDetails: (MatchGameRequest) -> Unit,
    onOpenCourt: (Court) -> Unit,
    onShare: (MatchGameRequest) -> Unit,
    onAccept: (MatchGameRequest) -> Unit,
    onCancel: (MatchGameRequest) -> Unit,
    onMarkOutcome: (MatchGameRequest, String) -> Unit,
    onAddPhotoReport: (MatchGameRequest) -> Unit,
    onProposeNext: (MatchGameRequest) -> Unit,
    onActivityReport: (PersonalActivity) -> Unit,
    onActivityComplete: (PersonalActivity) -> Unit,
    onActivityCancel: (PersonalActivity) -> Unit,
    onOpenGallery: (ReportPhotoGalleryItem) -> Unit,
    onCreateSearch: () -> Unit,
) {
    if (!appModel.isAuthenticated) {
        item {
            SectionCard(
                title = L10n.string("Upcoming games", "Ближайшие игры"),
                subtitle = L10n.string(
                    "This section is available after signing in with email.",
                    "Этот раздел доступен после входа по email.",
                ),
            ) {
                AuthInlinePrompt(
                    title = L10n.string(
                        "Save your account to see upcoming games",
                        "Сохрани аккаунт, чтобы видеть ближайшие игры",
                    ),
                    subtitle = L10n.string(
                        "Confirmed arrangements and upcoming matches will appear here after email verification.",
                        "После подтверждения email здесь появятся подтверждённые договорённости и предстоящие матчи.",
                    ),
                ) { appModel.presentAuth(AuthStep.EMAIL) }
            }
        }
        return
    }

    val currentUserId = appModel.currentUser?.id
    val activeRequests = requests.filterNot { it.isArchivedForTimeline }
    val archivedRequests = requests.filter { it.isArchivedForTimeline }
    val activeActivities = personalActivities.filterNot { it.isArchivedForTimeline }

    if (activeRequests.isEmpty() && activeActivities.isEmpty() && !isLoading) {
        item { UpcomingEmptyState(onCreateSearch = onCreateSearch) }
    }

    if (!isWidgetPromptDismissed) {
        item {
            UpcomingWidgetPromptCard(
                hasUpcomingGames = activeRequests.isNotEmpty() || activeActivities.isNotEmpty(),
                onOpenHelp = onOpenWidgetHelp,
            )
        }
    }

    if (activeRequests.isNotEmpty()) {
        item { DarkSectionHeader(L10n.string("Games with players", "Игры с игроками"), activeRequests.size) }

        items(activeRequests.size) { index ->
            val request = activeRequests[index]
            val match = matches.firstOrNull { it.id == request.matchId }
            val rawStatus = request.status.lowercase()
            val canManage = rawStatus == "pending" || rawStatus == "accepted" || rawStatus == "approved"

            UpcomingGameCard(
                request = request,
                displayName = request.upcomingDisplayName(currentUserId),
                avatarUrl = request.upcomingAvatarUrl(currentUserId) ?: match?.otherUser?.avatarUrl,
                currentUserId = currentUserId,
                isUpdating = updatingRequestIds.contains(request.id),
                isAddingToCalendar = false,
                onSelectParticipant = onSelectParticipant,
                onOpenChat = if (match != null || request.searchLobbyId != null) {
                    { onOpenChat(request) }
                } else {
                    null
                },
                onOpenDetails = { onOpenDetails(request) },
                onOpenCourt = request.proposedCourt?.let { court -> { onOpenCourt(court) } },
                onShare = if (rawStatus == "accepted" || rawStatus == "approved") {
                    { onShare(request) }
                } else {
                    null
                },
                onAddToCalendar = null,
                onAccept = if (request.isPendingForRecipient(currentUserId)) {
                    { onAccept(request) }
                } else {
                    null
                },
                onCancel = if (canManage) { { onCancel(request) } } else null,
                onMarkOutcome = if (request.needsOutcomeReview || request.canAddPhotoReport) {
                    { outcome -> onMarkOutcome(request, outcome) }
                } else {
                    null
                },
                onAddPhotoReport = if (request.canAddPhotoReport) { { onAddPhotoReport(request) } } else null,
                onConfirmReport = null,
                onProposeNext = if (match != null) { { onProposeNext(request) } } else null,
                onOpenGallery = onOpenGallery,
            )
        }
    }

    if (activeActivities.isNotEmpty()) {
        item { DarkSectionHeader(L10n.string("Personal visits", "Личные визиты"), activeActivities.size) }

        items(activeActivities.size) { index ->
            val activity = activeActivities[index]
            PersonalActivityUpcomingCard(
                activity = activity,
                isUpdating = updatingActivityIds.contains(activity.id),
                onAddPhotoReport = if (activity.hasEnded) { { onActivityReport(activity) } } else null,
                onCompleteWithoutPhoto = if (activity.canComplete) { { onActivityComplete(activity) } } else null,
                onCancel = if (activity.status.lowercase() == "planned") {
                    { onActivityCancel(activity) }
                } else {
                    null
                },
                onOpenCourt = { activity.court?.let(onOpenCourt) },
                onOpenGallery = onOpenGallery,
            )
        }
    }

    if (archivedRequests.isNotEmpty()) {
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp)
                    .clickable(onClick = onToggleHistory),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    (
                        if (isHistoryExpanded) {
                            L10n.string("Hide history", "Скрыть историю")
                        } else {
                            L10n.string("Show history", "Показать историю")
                        }
                        ).uppercase(),
                    style = AppText.captionSemibold.copy(letterSpacing = 1.4.sp),
                    color = Color.White.copy(alpha = 0.72f),
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "${archivedRequests.size}",
                    style = AppText.caption2Semibold,
                    color = Color.White.copy(alpha = 0.88f),
                    modifier = Modifier
                        .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(percent = 50))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }

        if (isHistoryExpanded) {
            items(archivedRequests.size) { index ->
                val request = archivedRequests[index]
                CompactUpcomingHistoryRow(
                    request = request,
                    displayName = request.upcomingDisplayName(currentUserId),
                    avatarUrl = request.upcomingAvatarUrl(currentUserId),
                    onOpenDetails = { onOpenDetails(request) },
                    onOpenChat = { onOpenChat(request) },
                )
            }
        }
    }
}

/** Port of `struct CompactUpcomingHistoryRow`. */
@Composable
private fun CompactUpcomingHistoryRow(
    request: MatchGameRequest,
    displayName: String,
    avatarUrl: String?,
    onOpenDetails: () -> Unit,
    onOpenChat: () -> Unit,
) {
    val shape = continuousShape(20.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.05f))
            .border(1.dp, Color.White.copy(alpha = 0.07f), shape)
            .clickable(onClick = onOpenDetails)
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RemoteAvatarView(name = displayName, path = avatarUrl, size = 40.dp)

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                displayName,
                style = AppText.subheadlineSemibold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "${request.sport.title} · ${request.proposedDatetime.formattedDateTime()}",
                style = AppText.caption,
                color = Color.White.copy(alpha = 0.58f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Text(
            request.statusLabel,
            style = AppText.caption2Semibold,
            color = request.statusTintColor,
            maxLines = 1,
        )

        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
                .clickable(onClick = onOpenChat),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.AutoMirrored.Filled.Message,
                null,
                tint = Color.White.copy(alpha = 0.8f),
                modifier = Modifier.size(15.dp),
            )
        }
    }
}

/** Port of `likesContent`. */
private fun androidx.compose.foundation.lazy.LazyListScope.likesContent(
    appModel: AppViewModel,
    users: List<DiscoverUser>,
    isLoading: Boolean,
) {
    if (users.isEmpty()) {
        if (!isLoading) {
            item {
                DarkEmptyState(
                    title = L10n.string("Nobody yet", "Пока никого"),
                    subtitle = L10n.string(
                        "When someone wants to play with you, they will show up here.",
                        "Когда кто-то захочет с тобой сыграть, он появится здесь.",
                    ),
                )
            }
        }
        return
    }

    item { DarkSectionHeader(L10n.string("Want to play with you", "Хотят с тобой поиграть"), users.size) }

    items(users.size) { index ->
        val user = users[index]
        DarkCard {
            Row(horizontalArrangement = Arrangement.spacedBy(13.dp), verticalAlignment = Alignment.CenterVertically) {
                RemoteAvatarView(name = user.displayName, path = user.avatarUrl, size = 58.dp)

                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(
                        user.age?.let { "${user.displayName}, $it" } ?: user.displayName,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        "${user.preferredSports.firstOrNull()?.title ?: ""} · ${user.districtDisplaySummary}",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFF69DB8F),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        user.explainabilityReasons.firstOrNull()
                            ?: L10n.string(
                                "This player has already said they would like to play with you.",
                                "Игрок уже отметил, что хочет с вами сыграть.",
                            ),
                        fontSize = 13.sp,
                        color = Color.White.copy(alpha = 0.62f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

/** Port of `searchContent`: the urgent searches other players have published. */
/**
 * Port of `searchContent` - the urgent-games tab: a sport rail over the list of
 * `ActiveHotSearchCard`s built from every visible player's own searches.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.searchContent(
    appModel: AppViewModel,
    users: List<DiscoverUser>,
    isLoading: Boolean,
    sportFilter: Sport?,
    hotFilter: ActiveHotSearchFilter,
    calendarDate: java.time.LocalDate,
    displayMode: ActiveHotSearchDisplayMode,
    selectedMapItemId: String?,
    onSelectMapItem: (String) -> Unit,
    onSelectMapCluster: (List<String>) -> Unit,
    localResponseStatuses: Map<String, String>,
    localResponseIds: Map<String, String>,
    onSelectSport: (Sport?) -> Unit,
    onSelectHotFilter: (ActiveHotSearchFilter) -> Unit,
    onSelectCalendarDate: (java.time.LocalDate) -> Unit,
    onOpenUser: (DiscoverUser) -> Unit,
    onOpenCourt: (Court) -> Unit,
    onOpenApprovedChat: (GameSearch) -> Unit,
    onRespond: (GameSearch) -> Unit,
    onCreateSearch: () -> Unit,
    onOpenRoute: (GameSearch) -> Unit,
) {
    val currentUserId = appModel.currentUser?.id

    fun currentUserResponse(search: GameSearch): SearchResponse? =
        currentUserId?.let { id -> search.responses.firstOrNull { it.responderUser.id == id } }

    // `isVisibleActiveHotSearch(_:)`
    fun isVisible(search: GameSearch): Boolean {
        if (search.searchType != SearchType.HOT) return false
        if (search.isActive == false) return false
        if (search.isExpired == true) return false
        return search.status.lowercase() !in setOf("matched", "closed", "canceled", "cancelled", "expired")
    }

    val allItems = users
        .flatMap { user -> user.gameSearches.map { user to it } }
        .filter { (user, search) ->
            if (user.id == currentUserId) return@filter false
            if (!isVisible(search)) return@filter false
            val status = localResponseStatuses[search.id] ?: currentUserResponse(search)?.status
            status != "rejected"
        }
        .sortedBy { (_, search) -> parseServerInstant(search.hotStartsAt) ?: java.time.Instant.MAX }

    val availableSports = allItems.map { it.second.sport }.distinct().sortedBy { it.title }
    val sportFiltered = allItems.filter { (_, search) -> sportFilter == null || search.sport == sportFilter }

    // `filteredActiveHotSearchItems`
    val visibleItems = sportFiltered.filter { (user, search) ->
        when (hotFilter) {
            ActiveHotSearchFilter.ALL -> true
            ActiveHotSearchFilter.TODAY -> isTodayHotSearch(search)
            ActiveHotSearchFilter.TOMORROW -> isTomorrowHotSearch(search)
            ActiveHotSearchFilter.CALENDAR -> isHotSearch(search, calendarDate)
            ActiveHotSearchFilter.NEARBY -> isNearbyHotSearch(appModel.currentUser, user)
            ActiveHotSearchFilter.LEVEL -> matchesCurrentUserLevel(appModel.currentUser, search)
        }
    }

    item {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ActiveHotSearchDateRail(
                filter = hotFilter,
                calendarDate = calendarDate,
                totalCount = sportFiltered.size,
                countOn = { date -> sportFiltered.count { (_, search) -> isHotSearch(search, date) } },
                onSelectAll = { onSelectHotFilter(ActiveHotSearchFilter.ALL) },
                onSelectDate = { date ->
                    onSelectCalendarDate(date)
                    onSelectHotFilter(ActiveHotSearchFilter.CALENDAR)
                },
            )
        }
    }

    item {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ActiveHotSearchFilterChip(
                title = ActiveHotSearchFilter.NEARBY.title,
                count = sportFiltered.count { (user, _) -> isNearbyHotSearch(appModel.currentUser, user) },
                isSelected = hotFilter == ActiveHotSearchFilter.NEARBY,
            ) { onSelectHotFilter(ActiveHotSearchFilter.NEARBY) }

            ActiveHotSearchFilterChip(
                title = ActiveHotSearchFilter.LEVEL.title,
                count = sportFiltered.count { (_, search) ->
                    matchesCurrentUserLevel(appModel.currentUser, search)
                },
                isSelected = hotFilter == ActiveHotSearchFilter.LEVEL,
            ) { onSelectHotFilter(ActiveHotSearchFilter.LEVEL) }
        }
    }

    if (availableSports.isNotEmpty()) {
        item {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                ActiveHotSearchSportChip(
                    title = L10n.string("All sports", "Все виды"),
                    sport = null,
                    isSelected = sportFilter == null,
                ) { onSelectSport(null) }

                availableSports.forEach { sport ->
                    ActiveHotSearchSportChip(
                        title = sport.title,
                        sport = sport,
                        isSelected = sportFilter == sport,
                    ) { onSelectSport(sport) }
                }
            }
        }
    }

    if (displayMode != ActiveHotSearchDisplayMode.MAP && visibleItems.isEmpty() && !isLoading) {
        item {
            UrgentSearchEmptyState(
                showsCreateButton = allItems.isEmpty(),
                onCreateSearch = onCreateSearch,
            )
        }
        return
    }

    if (displayMode == ActiveHotSearchDisplayMode.MAP) {
        val viewerCenter = (SupportedCity.resolve(appModel.currentUser?.city ?: appModel.guestDraft.city)
            ?: SupportedCity.SAINT_PETERSBURG)
        val mapItems = visibleItems.map { (user, search) ->
            ActiveHotSearchItem(user, search, viewerCenter.mapCenter)
        }
        val selectedItem = mapItems.firstOrNull { it.id == selectedMapItemId } ?: mapItems.firstOrNull()

        item {
            val shape = continuousShape(28.dp)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(shape)
                    .background(Color.Black)
                    .border(1.dp, AppTheme.court.copy(alpha = 0.22f), shape),
                contentAlignment = Alignment.BottomCenter,
            ) {
                ActiveHotSearchMapView(
                    items = mapItems.map {
                        HotSearchMapPin(it.id, it.search.sport, it.coordinate.latitude, it.coordinate.longitude)
                    },
                    selectedItemId = selectedItem?.id,
                    highlightedDistrictIds = mapItems.mapNotNull { it.districtId }.distinct().sorted(),
                    viewerMapCenter = selectedItem?.viewerMapCenter ?: viewerCenter.mapCenter,
                    viewerMapDiameterMeters = viewerCenter.mapDiameterMeters,
                    userCoordinate = null,
                    userName = appModel.currentUser?.displayName ?: L10n.string("You", "Вы"),
                    modifier = Modifier.fillMaxWidth().height(430.dp),
                    onSelect = onSelectMapItem,
                    onSelectCluster = onSelectMapCluster,
                )

                if (selectedItem != null) {
                    val own = currentUserResponse(selectedItem.search)
                    ActiveHotSearchMapCard(
                        item = selectedItem,
                        responseStatus = localResponseStatuses[selectedItem.search.id] ?: own?.status,
                        responseId = localResponseIds[selectedItem.search.id] ?: own?.id,
                        modifier = Modifier.padding(12.dp),
                        onOpenUser = { onOpenUser(selectedItem.user) },
                        onOpenCourt = onOpenCourt,
                        onOpenApprovedChat = { onOpenApprovedChat(selectedItem.search) },
                        onAction = { onRespond(selectedItem.search) },
                    )
                }
            }
        }
        return
    }

    items(visibleItems.size) { index ->
        val (user, search) = visibleItems[index]
        val own = currentUserResponse(search)
        val rawStatus = localResponseStatuses[search.id] ?: own?.status

        ActiveHotSearchCard(
            user = user,
            search = search,
            responseStatus = rawStatus,
            responseId = localResponseIds[search.id] ?: own?.id,
            onOpenUser = { onOpenUser(user) },
            onOpenCourt = onOpenCourt,
            onOpenApprovedChat = { onOpenApprovedChat(search) },
            onAction = { onRespond(search) },
        )
    }
}


/**
 * The iOS screen puts the bell in the navigation toolbar; Compose has no
 * toolbar here, so it sits at the end of the tab row, same badge and all.
 */
@Composable
private fun DiscoverHeaderRow(
    appModel: AppViewModel,
    onOpenNotifications: () -> Unit,
    tabs: @Composable () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().background(Color.Black),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.weight(1f)) { tabs() }

        if (appModel.isAuthenticated) {
            val unread = appModel.activitySummary.inboxBadgeCount
            Box(modifier = Modifier.padding(start = 8.dp)) {
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .clip(continuousShape(16.dp))
                        .background(Color.White.copy(alpha = 0.82f))
                        .clickable(onClick = onOpenNotifications),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.Notifications,
                        contentDescription = L10n.string("Notifications", "Уведомления"),
                        tint = AppTheme.ink,
                        modifier = Modifier.size(17.dp),
                    )
                }

                if (unread > 0) {
                    Text(
                        minOf(unread, 99).toString(),
                        style = AppText.caption2Semibold.copy(fontWeight = FontWeight.Bold),
                        color = Color.White,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .background(AppTheme.clay, RoundedCornerShape(percent = 50))
                            .padding(horizontal = 5.dp, vertical = 2.dp),
                    )
                }
            }
        }
    }
}
