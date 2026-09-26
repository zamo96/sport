package shop.sportsearch.app.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.automirrored.outlined.Message
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlin.math.abs
import kotlinx.coroutines.delay
import shop.sportsearch.app.core.AppNavigationTarget
import shop.sportsearch.app.core.AuthStep
import shop.sportsearch.app.core.BottomBarDisplayMode
import shop.sportsearch.app.core.DiscoverTab
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.auth.AuthScreen
import shop.sportsearch.app.ui.components.AppScreen
import shop.sportsearch.app.ui.components.LoadingOverlay
import shop.sportsearch.app.ui.components.LocaleRecommendationBanner
import shop.sportsearch.app.ui.components.MenuTabLoadingOverlay
import shop.sportsearch.app.ui.components.ServerRecoveryOverlay
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.courts.CourtsScreen
import shop.sportsearch.app.ui.discover.DiscoverScreen
import shop.sportsearch.app.ui.matches.MatchesScreen
import shop.sportsearch.app.ui.profile.ProfileScreen
import shop.sportsearch.app.ui.searches.SearchesScreen
import shop.sportsearch.app.ui.theme.AppRadius
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.consents.ConsentReviewMode
import shop.sportsearch.app.ui.consents.ConsentReviewScreen
import shop.sportsearch.app.ui.consents.PhoneLinkScreen
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct ContentView`. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun RootScreen(appModel: AppViewModel) {
    AppScreen {
        if (appModel.canEnterApp) {
            MainTabView(appModel)
        } else {
            AuthScreen(appModel, initialStep = AuthStep.INTRO, embedded = true)
        }

        // The banner sits above every tab, as it does in `TennisSearchIOSApp`.
        appModel.pendingLocaleRecommendation?.let { recommendation ->
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(horizontal = 16.dp)
                    .padding(top = 10.dp)
                    .zIndex(100f),
            ) {
                LocaleRecommendationBanner(
                    recommendation = recommendation,
                    onAccept = appModel::acceptLocaleRecommendation,
                    onDismiss = appModel::dismissLocaleRecommendation,
                )
            }
        }

        if (appModel.isBusy) {
            LoadingOverlay()
        }

        // Port of the iOS `fullScreenCover`: closes only with an answer, after which
        // the server clears `reviewRequired`.
        val consentProfile = appModel.currentUser
        if (appModel.isConsentReviewRequired && consentProfile != null) {
            Box(modifier = Modifier.fillMaxSize().zIndex(50f)) {
                ConsentReviewScreen(appModel, consentProfile, ConsentReviewMode.REQUIRED)
            }
        } else if (appModel.isPhoneLinkPromptVisible) {
            // After the consent screen, once per launch: a Russian account without a phone.
            Box(modifier = Modifier.fillMaxSize().zIndex(50f)) {
                PhoneLinkScreen(appModel, isPrompt = true) { appModel.dismissPhoneLinkPrompt() }
            }
        }

        appModel.serverRecoveryNotice?.let { notice ->
            ServerRecoveryOverlay(
                title = notice.title,
                message = notice.message,
                onDismiss = appModel::dismissServerRecoveryNotice,
            )

            // iOS auto-dismisses the notice after 3.2s.
            LaunchedEffect(notice.id) {
                delay(3200)
                if (appModel.serverRecoveryNotice?.id == notice.id) {
                    appModel.dismissServerRecoveryNotice()
                }
            }
        }
    }

    appModel.errorMessage?.let { message ->
        // Material 3 tints the default dialog surface from the primary colour,
        // which reads lavender against this palette. The iOS alert is neutral,
        // so the surface and text are pinned to the app's own colours.
        AlertDialog(
            onDismissRequest = { appModel.errorMessage = null },
            title = { Text(L10n.string("Error", "Ошибка")) },
            text = { Text(message) },
            containerColor = Color.White,
            titleContentColor = AppTheme.ink,
            textContentColor = AppTheme.ink.copy(alpha = 0.72f),
            shape = continuousShape(AppRadius.sheet),
            confirmButton = {
                TextButton(onClick = { appModel.errorMessage = null }) {
                    Text("OK", color = AppTheme.court)
                }
            },
        )
    }

    appModel.presentedAuthStep?.let { step ->
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = appModel::dismissPresentedAuth,
            sheetState = sheetState,
            containerColor = AppTheme.creamLight,
            shape = continuousShape(32.dp),
        ) {
            AuthScreen(appModel, initialStep = step, embedded = false)
        }
    }
}

/** Port of `private enum MainTab`. */
enum class MainTab {
    DISCOVER, MATCHES, SEARCHES, COURTS, PROFILE;

    val title: String
        get() = when (this) {
            DISCOVER -> L10n.string("Home", "Главная")
            MATCHES -> L10n.string("Matches", "Мэтчи")
            SEARCHES -> L10n.string("Searches", "Мои поиски")
            COURTS -> L10n.string("Courts", "Центры")
            PROFILE -> L10n.string("Profile", "Профиль")
        }

    val loadingTitle: String
        get() = when (this) {
            DISCOVER -> L10n.string("Refreshing players", "Обновляем игроков")
            MATCHES -> L10n.string("Loading matches", "Загружаем мэтчи")
            SEARCHES -> L10n.string("Loading searches", "Загружаем поиски")
            COURTS -> L10n.string("Loading courts", "Загружаем центры")
            PROFILE -> L10n.string("Loading profile", "Загружаем профиль")
        }

    /**
     * SF Symbols renders the selected tab in semibold; Material icons have no
     * weight axis, so the filled/outlined pair carries the same distinction.
     */
    fun icon(selected: Boolean): ImageVector = when (this) {
        DISCOVER -> if (selected) Icons.Filled.Explore else Icons.Outlined.Explore        // safari
        MATCHES -> if (selected) Icons.AutoMirrored.Filled.Message else Icons.AutoMirrored.Outlined.Message         // message
        SEARCHES -> if (selected) Icons.Filled.Search else Icons.Outlined.Search          // magnifyingglass.circle
        COURTS -> if (selected) Icons.Filled.Map else Icons.Outlined.Map                  // map
        PROFILE -> if (selected) Icons.Filled.Person else Icons.Outlined.Person           // person
    }

    val key: String get() = name.lowercase()
}

/** Port of `private struct MainTabView`. */
@Composable
private fun MainTabView(appModel: AppViewModel) {
    var selectedTab by remember { mutableStateOf(MainTab.DISCOVER) }
    var courtsInitialSport by remember { mutableStateOf<Sport?>(null) }
    var discoverHighlightedUserID by remember { mutableStateOf<String?>(null) }
    var discoverHighlightedSearchID by remember { mutableStateOf<String?>(null) }
    var discoverHighlightedGameRequestID by remember { mutableStateOf<String?>(null) }

    // Port of `handlePendingNavigation`.
    LaunchedEffect(appModel.pendingNavigationTarget) {
        when (val target = appModel.pendingNavigationTarget) {
            null -> return@LaunchedEffect
            is AppNavigationTarget.Discover -> {
                appModel.lastSelectedDiscoverTab =
                    if (target.tab == DiscoverTab.SEEKING) DiscoverTab.HOT else target.tab
                discoverHighlightedUserID = target.highlightedUserID
                discoverHighlightedSearchID = target.highlightedSearchID
                discoverHighlightedGameRequestID = target.highlightedGameRequestID
                selectedTab = MainTab.DISCOVER
            }
            AppNavigationTarget.Matches -> selectedTab = MainTab.MATCHES
            AppNavigationTarget.Searches -> selectedTab = MainTab.SEARCHES
            is AppNavigationTarget.SearchLobby -> {
                appModel.pendingSearchLobbyID = target.searchId
                selectedTab = MainTab.SEARCHES
            }
            is AppNavigationTarget.CreateSearch -> {
                appModel.pendingCreateSearchPrefill = target.prefill
                selectedTab = MainTab.SEARCHES
            }
            AppNavigationTarget.Profile -> selectedTab = MainTab.PROFILE
            is AppNavigationTarget.Courts -> {
                courtsInitialSport = target.sport
                selectedTab = MainTab.COURTS
            }
            is AppNavigationTarget.Chat -> {
                appModel.pendingChatMatchID = target.matchId
                selectedTab = MainTab.MATCHES
            }
        }
        appModel.clearPendingNavigation()
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                when (selectedTab) {
                    MainTab.DISCOVER -> DiscoverScreen(
                        appModel = appModel,
                        initialTab = appModel.lastSelectedDiscoverTab,
                        highlightedUserID = discoverHighlightedUserID,
                        highlightedSearchID = discoverHighlightedSearchID,
                        highlightedGameRequestID = discoverHighlightedGameRequestID,
                        onTabChanged = { appModel.lastSelectedDiscoverTab = it },
                    )
                    MainTab.MATCHES -> if (appModel.isAuthenticated) {
                        MatchesScreen(appModel)
                    } else {
                        AuthGateView(
                            appModel = appModel,
                            title = L10n.string("Matches are available after email verification", "Мэтчи откроются после email"),
                            subtitle = L10n.string(
                                "Verify your email first to create matches, chat, and receive notifications.",
                                "Сначала подтверди почту, чтобы создавать мэтчи, переписываться и получать уведомления.",
                            ),
                            buttonTitle = L10n.string("Continue", "Продолжить"),
                        )
                    }
                    MainTab.SEARCHES -> if (appModel.isAuthenticated) {
                        SearchesScreen(appModel)
                    } else {
                        AuthGateView(
                            appModel = appModel,
                            title = L10n.string("Searches are saved to your account", "Поиски сохраняются в аккаунте"),
                            subtitle = L10n.string(
                                "You can browse players as a guest. Verify your email to publish searches.",
                                "Сейчас можно смотреть игроков в гостевом режиме. Чтобы публиковать свои поиски, нужен email.",
                            ),
                            buttonTitle = L10n.string("Verify email", "Подтвердить email"),
                        )
                    }
                    MainTab.COURTS -> CourtsScreen(appModel, initialSport = courtsInitialSport)
                    MainTab.PROFILE -> ProfileScreen(appModel)
                }
            }

            BottomTabBar(
                appModel = appModel,
                selectedTab = selectedTab,
                onSelect = { tab ->
                    if (tab == MainTab.DISCOVER) {
                        appModel.lastSelectedDiscoverTab =
                            if (appModel.hasActiveUpcomingGameRequests) DiscoverTab.UPCOMING else DiscoverTab.SWIPE
                        discoverHighlightedUserID = null
                        discoverHighlightedSearchID = null
                        discoverHighlightedGameRequestID = null
                    }
                    if (tab == MainTab.COURTS) courtsInitialSport = null
                    selectedTab = tab
                },
            )
        }

        if (appModel.isTabContentLoading(selectedTab.key)) {
            MenuTabLoadingOverlay(title = selectedTab.loadingTitle)
        }
    }
}

/**
 * Port of `telegramTabBar(width:)`. Every measurement below is the value from
 * ContentView.swift: 14pt outer inset, 32pt container radius, a 24pt / 58pt
 * selection pill, 72pt tap targets and the drag-to-slide gesture.
 */
@Composable
private fun BottomTabBar(
    appModel: AppViewModel,
    selectedTab: MainTab,
    onSelect: (MainTab) -> Unit,
) {
    val mode = appModel.bottomBarDisplayMode
    if (mode == BottomBarDisplayMode.HIDDEN) return

    val isCompact = mode == BottomBarDisplayMode.COMPACT
    val haptics = rememberAppHaptics()
    val density = LocalDensity.current

    var isSliding by remember { mutableStateOf(false) }
    var dragLocationX by remember { mutableStateOf<Float?>(null) }
    var pendingTab by remember { mutableStateOf<MainTab?>(null) }

    val displayedTab = if (isSliding) pendingTab ?: selectedTab else selectedTab

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .height(if (isCompact) 20.dp else 98.dp)
            .padding(horizontal = 14.dp, vertical = 0.dp),
        contentAlignment = Alignment.BottomCenter,
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = if (isCompact) 4.dp else 8.dp),
        ) {
            val barWidth: Dp = maxWidth
            val tabCount = MainTab.entries.size
            val tabWidth = barWidth / tabCount
            val barWidthPx = with(density) { barWidth.toPx() }
            val tabWidthPx = with(density) { tabWidth.toPx() }

            fun centerXPx(tab: MainTab): Float =
                (MainTab.entries.indexOf(tab) * tabWidthPx) + tabWidthPx / 2f

            val indicatorCenterPx = if (isSliding && dragLocationX != null) {
                dragLocationX!!.coerceIn(tabWidthPx / 2f, barWidthPx - tabWidthPx / 2f)
            } else {
                centerXPx(selectedTab)
            }

            val baseIndicatorWidthPx = maxOf(with(density) { 56.dp.toPx() }, tabWidthPx * 0.82f)
            val indicatorWidthPx = if (isSliding && dragLocationX != null) {
                val clamped = dragLocationX!!.coerceIn(tabWidthPx / 2f, barWidthPx - tabWidthPx / 2f)
                val drift = abs(clamped - centerXPx(selectedTab))
                minOf(baseIndicatorWidthPx + drift * 0.18f, tabWidthPx * 0.96f)
            } else {
                baseIndicatorWidthPx
            }

            val animatedIndicatorCenter by animateDpAsState(
                targetValue = with(density) { indicatorCenterPx.toDp() },
                animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow),
                label = "indicatorCenter",
            )
            val animatedIndicatorWidth by animateDpAsState(
                targetValue = with(density) { indicatorWidthPx.toDp() },
                animationSpec = spring(dampingRatio = 0.84f, stiffness = Spring.StiffnessMediumLow),
                label = "indicatorWidth",
            )

            val containerShape = continuousShape(if (isCompact) 999.dp else 32.dp)

            Box(
                modifier = Modifier
                    .then(if (isCompact) Modifier.width(58.dp).height(8.dp) else Modifier.fillMaxWidth().height(76.dp))
                    .align(Alignment.BottomCenter)
                    .appShadow(Color.Black.copy(alpha = 0.16f), radius = 18.dp, offsetY = 8.dp, shape = containerShape)
                    .clip(containerShape)
                    .background(Color.Black.copy(alpha = if (isCompact) 0.72f else 0.92f))
                    // Stands in for `.ultraThinMaterial` over black, which no
                    // Compose API reproduces below API 31.
                    .background(Color.White.copy(alpha = if (isCompact) 0.02f else 0.04f))
                    .border(1.dp, Color.White.copy(alpha = if (isCompact) 0.14f else 0.08f), containerShape)
                    .pointerInput(isCompact, selectedTab) {
                        if (isCompact) return@pointerInput
                        detectHorizontalDragGestures(
                            onDragStart = { offset ->
                                isSliding = true
                                dragLocationX = offset.x
                                pendingTab = tabAt(offset.x, tabWidthPx)
                            },
                            onDragEnd = {
                                pendingTab?.let {
                                    haptics.selection()
                                    onSelect(it)
                                }
                                pendingTab = null
                                isSliding = false
                                dragLocationX = null
                            },
                            onDragCancel = {
                                pendingTab = null
                                isSliding = false
                                dragLocationX = null
                            },
                        ) { change, _ ->
                            dragLocationX = change.position.x
                            pendingTab = tabAt(change.position.x, tabWidthPx)
                        }
                    },
            ) {
                if (isCompact) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.Center)
                            .size(width = 44.dp, height = 5.dp)
                            .background(Color.White.copy(alpha = 0.82f), RoundedCornerShape(percent = 50)),
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .offset(x = animatedIndicatorCenter - animatedIndicatorWidth / 2, y = (-1).dp)
                            .size(width = animatedIndicatorWidth, height = 58.dp)
                            .appShadow(
                                Color.Black.copy(alpha = 0.22f),
                                radius = 18.dp,
                                offsetY = 12.dp,
                                shape = continuousShape(24.dp),
                            )
                            .clip(continuousShape(24.dp))
                            .background(AppTheme.tabIndicator),
                    )

                    Row(modifier = Modifier.fillMaxWidth().height(72.dp).align(Alignment.Center)) {
                        MainTab.entries.forEach { tab ->
                            TabBarItem(
                                tab = tab,
                                isActive = displayedTab == tab,
                                badge = badgeText(appModel, tab),
                                badgeColor = if (tab == MainTab.SEARCHES) AppTheme.court else Color.Red,
                                modifier = Modifier.width(tabWidth),
                                onClick = {
                                    pendingTab = null
                                    dragLocationX = null
                                    isSliding = false
                                    haptics.selection()
                                    onSelect(tab)
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun tabAt(x: Float, tabWidthPx: Float): MainTab {
    val index = (x / tabWidthPx).toInt().coerceIn(0, MainTab.entries.size - 1)
    return MainTab.entries[index]
}

/** Port of `badgeText(for:)`. */
private fun badgeText(appModel: AppViewModel, tab: MainTab): String? {
    val summary = appModel.activitySummary
    val count = when (tab) {
        MainTab.DISCOVER -> summary.discoverBadgeCount
        MainTab.MATCHES -> if (appModel.isAuthenticated) summary.inboxBadgeCount else 0
        MainTab.SEARCHES -> if (appModel.isAuthenticated) summary.activeSearchesCount else 0
        else -> 0
    }
    return if (count > 0) minOf(count, 99).toString() else null
}

@Composable
private fun TabBarItem(
    tab: MainTab,
    isActive: Boolean,
    badge: String?,
    badgeColor: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val tint by animateColorAsState(
        targetValue = if (isActive) AppTheme.tabAccent else Color.White.copy(alpha = 0.92f),
        label = "tabTint",
    )

    Column(
        modifier = modifier
            .height(72.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(modifier = Modifier.height(24.dp), contentAlignment = Alignment.Center) {
            Icon(
                imageVector = tab.icon(isActive),
                contentDescription = tab.title,
                tint = tint,
                modifier = Modifier.size(21.dp),
            )

            badge?.let {
                Text(
                    text = it,
                    style = AppText.caption2.copy(fontWeight = FontWeight.Bold),
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 14.dp, y = (-10).dp)
                        .background(badgeColor, RoundedCornerShape(percent = 50))
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
            }
        }

        Box(modifier = Modifier.height(5.dp))

        Text(
            text = tab.title,
            style = AppText.caption2.copy(fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Medium),
            color = tint,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Port of `private struct AuthGateView`. */
@Composable
private fun AuthGateView(
    appModel: AppViewModel,
    title: String,
    subtitle: String,
    buttonTitle: String,
) {
    AppScreen {
        Column(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Lock,
                contentDescription = null,
                tint = Color(0xFFFF9500),
                modifier = Modifier.size(34.dp),
            )
            Box(Modifier.height(18.dp))
            Text(title, style = AppText.title3Bold, color = AppTheme.ink, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Box(Modifier.height(18.dp))
            Text(subtitle, style = AppText.subheadline, color = AppTheme.mutedInk, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Box(Modifier.height(18.dp))
            shop.sportsearch.app.ui.components.PrimaryActionButton(
                title = buttonTitle,
                onClick = { appModel.presentAuth(AuthStep.EMAIL) },
                tint = AppTheme.ink,
            )
        }
    }
}
