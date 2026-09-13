package shop.sportsearch.app.ui.searches

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.EmptyStateView
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.maps.RunningRouteDetailSheet
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.time.Instant

/** Port of `private enum SearchListFilter`. */
private enum class SearchListFilter {
    ALL, ACTIVE, WITH_RESPONSES, PAUSED, COMPLETED;

    val title: String
        get() = when (this) {
            ALL -> L10n.string("All", "Все")
            ACTIVE -> L10n.string("Active", "Активные")
            WITH_RESPONSES -> L10n.string("With responses", "С откликами")
            PAUSED -> L10n.string("Paused", "На паузе")
            COMPLETED -> L10n.string("Completed", "Завершённые")
        }
}

private data class SearchSectionModel(val title: String, val subtitle: String, val searches: List<GameSearch>)

private fun isCompletedSearch(search: GameSearch): Boolean {
    if (search.status.lowercase() in setOf("matched", "completed", "finished")) return true
    return search.responses.count { it.status == "approved" } >= maxOf(search.playersNeeded, 1)
}

/** Port of `struct SearchesView` in ios/TennisSearchIOS/Views/SearchesView.swift. */
@Composable
fun SearchesScreen(appModel: AppViewModel) {
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()

    var searches by remember { mutableStateOf<List<GameSearch>>(emptyList()) }
    var isLoadingSearches by remember { mutableStateOf(false) }
    var selectedFilter by remember { mutableStateOf(SearchListFilter.ALL) }
    var updatingSearchID by remember { mutableStateOf<String?>(null) }
    var isCreateFABExpanded by remember { mutableStateOf(true) }
    var hasInteractedWithCreateFAB by remember { mutableStateOf(false) }

    var isPresentingComposer by remember { mutableStateOf(false) }
    var editingSearch by remember { mutableStateOf<GameSearch?>(null) }
    var presentedSearch by remember { mutableStateOf<GameSearch?>(null) }
    var presentedSearchLobbyID by remember { mutableStateOf<String?>(null) }
    var routeSearch by remember { mutableStateOf<GameSearch?>(null) }

    val currentUserId = appModel.currentUser?.id

    fun isOwned(search: GameSearch): Boolean =
        search.createdByUserId == null || currentUserId == null || search.createdByUserId == currentUserId

    fun hasMyResponse(search: GameSearch): Boolean =
        currentUserId != null && search.responses.any { it.responderUser.id == currentUserId }

    suspend fun loadSearches() {
        val shouldReportMenuLoading = searches.isEmpty()
        if (shouldReportMenuLoading) appModel.setTabContentLoading("searches", true)
        isLoadingSearches = true
        runCatching { appModel.repository.fetchSearches() }
            .onSuccess { searches = it }
            .onFailure(appModel::present)
        isLoadingSearches = false
        if (shouldReportMenuLoading) appModel.setTabContentLoading("searches", false)
    }

    LaunchedEffect(Unit) {
        if (appModel.pendingCreateSearchPrefill != null) isPresentingComposer = true
        loadSearches()
    }

    LaunchedEffect(appModel.pendingCreateSearchPrefill) {
        if (appModel.pendingCreateSearchPrefill != null) isPresentingComposer = true
    }

    LaunchedEffect(appModel.pendingSearchLobbyID, searches) {
        val searchId = appModel.pendingSearchLobbyID ?: return@LaunchedEffect
        if (searches.isEmpty()) return@LaunchedEffect
        val found = searches.firstOrNull { it.id == searchId }
        if (found != null && isOwned(found)) presentedSearch = found else presentedSearchLobbyID = searchId
        appModel.pendingSearchLobbyID = null
    }

    // `task(id: createFABAutoCollapseKey)` - the pill shrinks on its own after 2.5 s.
    LaunchedEffect(searches.isEmpty(), hasInteractedWithCreateFAB) {
        if (searches.isEmpty() || hasInteractedWithCreateFAB) return@LaunchedEffect
        delay(2500)
        isCreateFABExpanded = false
    }

    // --- Full-screen destinations ---
    if (isPresentingComposer) {
        SearchComposerScreen(
            appModel = appModel,
            initialSport = appModel.pendingCreateSearchPrefill?.sport,
            initialHotWindow = appModel.pendingCreateSearchPrefill?.hotWindow,
            initialHotStartTime = appModel.pendingCreateSearchPrefill?.hotStartTime,
            onDismiss = {
                isPresentingComposer = false
                appModel.pendingCreateSearchPrefill = null
            },
            onCreate = { created ->
                searches = listOf(created) + searches
                isPresentingComposer = false
                appModel.pendingCreateSearchPrefill = null
            },
        )
        return
    }

    editingSearch?.let { search ->
        SearchComposerScreen(
            appModel = appModel,
            initialSearch = search,
            onDismiss = { editingSearch = null },
            onCreate = { updated ->
                searches = searches.map { if (it.id == updated.id) updated else it }
                editingSearch = null
            },
        )
        return
    }

    presentedSearch?.let { search ->
        SearchDetailSheet(
            appModel = appModel,
            initialSearch = search,
            onDismiss = { presentedSearch = null },
            onEdit = { selected ->
                presentedSearch = null
                editingSearch = selected
            },
            onOpenLobby = { searchId ->
                presentedSearch = null
                presentedSearchLobbyID = searchId
            },
            onReloadParent = { loadSearches() },
        )
        return
    }

    routeSearch?.let { search ->
        HideBottomBarWhileVisible(appModel)
        RunningRouteDetailSheet(
            title = search.runningRoute ?: search.sport.routeDefaultTitle,
            sport = search.sport,
            points = search.runningRoutePoints,
            onDismiss = { routeSearch = null },
        )
        return
    }

    presentedSearchLobbyID?.let { searchId ->
        SearchLobbyScreen(
            appModel = appModel,
            searchId = searchId,
            onDismiss = { presentedSearchLobbyID = null },
        )
        return
    }

    // iOS only ever lists urgent searches on this tab.
    val visibleSearches = searches.filter { it.searchType == SearchType.HOT }

    val activeSearchCount = visibleSearches.count { isOwned(it) && !isCompletedSearch(it) && (it.isActive ?: true) }
    val pendingResponsesCount = visibleSearches.sumOf { search ->
        if (isOwnedActiveHotSearchForAttention(search, currentUserId)) {
            search.responses.count { it.status == "pending" }
        } else {
            0
        }
    }
    val nextUpcomingLine = visibleSearches
        .mapNotNull { search ->
            val regularDate = search.regularPair?.occurrences
                ?.mapNotNull { parseServerInstant(it.scheduledAt) }
                ?.filter { it > Instant.now() }
                ?.minOrNull()
            val hotDate = parseServerInstant(search.hotStartsAt)
            listOfNotNull(regularDate, hotDate).minOrNull()
        }
        .minOrNull()
        ?.formattedShortRelative()
        ?: L10n.string("None yet", "Пока нет")

    val filteredSearches = when (selectedFilter) {
        SearchListFilter.ALL -> visibleSearches
        SearchListFilter.ACTIVE -> visibleSearches.filter { isOwned(it) && !isCompletedSearch(it) && (it.isActive ?: true) }
        SearchListFilter.WITH_RESPONSES ->
            visibleSearches.filter { (isOwned(it) && it.responses.isNotEmpty()) || hasMyResponse(it) }
        SearchListFilter.PAUSED -> visibleSearches.filter { isOwned(it) && !isCompletedSearch(it) && !(it.isActive ?: true) }
        SearchListFilter.COMPLETED -> visibleSearches.filter { isCompletedSearch(it) }
    }

    val allSections = listOf(
        SearchSectionModel(
            L10n.string("Active", "Активные"),
            L10n.string("Searches currently visible to players.", "Поиски, которые сейчас видят игроки."),
            visibleSearches.filter { isOwned(it) && !isCompletedSearch(it) && (it.isActive ?: true) },
        ),
        SearchSectionModel(
            L10n.string("My responses", "Мои отклики"),
            L10n.string(
                "Other players' searches you have responded to.",
                "Поиски других игроков, куда ты уже откликнулся.",
            ),
            visibleSearches.filter { !isOwned(it) && hasMyResponse(it) },
        ),
        SearchSectionModel(
            L10n.string("Paused", "Остановлены"),
            L10n.string(
                "These searches are hidden and waiting to be resumed.",
                "Эти поиски сняты с показа и ждут перезапуска.",
            ),
            visibleSearches.filter { isOwned(it) && !isCompletedSearch(it) && !(it.isActive ?: true) },
        ),
        SearchSectionModel(
            L10n.string("Completed", "Завершены"),
            L10n.string(
                "Players have been found or the search is closed.",
                "Игроки найдены или поиск уже закрыт.",
            ),
            visibleSearches.filter { isOwned(it) && isCompletedSearch(it) },
        ),
    ).filter { it.searches.isNotEmpty() }

    fun openCard(search: GameSearch) {
        if (isOwned(search)) presentedSearch = search else presentedSearchLobbyID = search.id
    }

    @Composable
    fun cardFor(search: GameSearch) {
        SearchOverviewCard(
            search = search,
            currentUserId = currentUserId,
            updatingSearchID = updatingSearchID,
            onOpenDetails = { openCard(search) },
            onEdit = {
                if (isOwned(search)) editingSearch = search else presentedSearchLobbyID = search.id
            },
            onOpenRoute = { routeSearch = search },
            onToggleActive = { nextActive ->
                if (!isOwned(search)) return@SearchOverviewCard
                scope.launch {
                    updatingSearchID = search.id
                    runCatching { appModel.repository.setSearchActive(search.id, nextActive) }
                        .onSuccess { updated ->
                            searches = searches.map { if (it.id == updated.id) updated else it }
                        }
                        .onFailure(appModel::present)
                    updatingSearchID = null
                    loadSearches()
                }
            },
        )
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.White)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 172.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item {
                Text(
                    L10n.string("My searches", "Мои поиски"),
                    fontSize = 25.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                )
            }

            item {
                val shape = continuousShape(24.dp)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(shape)
                        .background(Color.White)
                        .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
                        .padding(vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SummaryCell(
                        L10n.string("Active urgent", "Активные срочные"),
                        "$activeSearchCount",
                        AppTheme.court,
                        Icons.Filled.LocalFireDepartment,
                        Modifier.weight(1f),
                    )
                    VerticalHairline()
                    SummaryCell(
                        L10n.string("New responses", "Новые отклики"),
                        "$pendingResponsesCount",
                        Color.Red.copy(alpha = 0.9f),
                        Icons.Filled.People,
                        Modifier.weight(1f),
                    )
                    VerticalHairline()
                    SummaryCell(
                        L10n.string("Next game", "Ближайшая игра"),
                        nextUpcomingLine,
                        AppTheme.court,
                        Icons.Filled.Schedule,
                        Modifier.weight(1f),
                    )
                }
            }

            item {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    SearchListFilter.entries.forEach { filter ->
                        val selected = selectedFilter == filter
                        Box(
                            modifier = Modifier
                                .height(40.dp)
                                .clip(CircleShape)
                                .background(if (selected) AppTheme.court else Color.White)
                                .border(
                                    1.dp,
                                    if (selected) AppTheme.court else Color.Black.copy(alpha = 0.08f),
                                    CircleShape,
                                )
                                .clickable { selectedFilter = filter }
                                .padding(horizontal = 16.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                filter.title,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (selected) Color.White else AppTheme.ink.copy(alpha = 0.86f),
                            )
                        }
                    }
                }
            }

            if (filteredSearches.isEmpty() && !isLoadingSearches) {
                item {
                    SectionCard(
                        title = if (activeSearchCount == 0) {
                            L10n.string("No active searches", "Активных поисков нет")
                        } else {
                            L10n.string("Nothing here yet", "Пока пусто")
                        },
                        subtitle = if (activeSearchCount == 0) {
                            L10n.string(
                                "Create a search so nearby players can respond.",
                                "Создай поиск, чтобы игроки рядом могли откликнуться.",
                            )
                        } else {
                            L10n.string(
                                "There are no searches in this section right now.",
                                "В этом разделе сейчас нет поисков.",
                            )
                        },
                    ) {
                        EmptyStateView(
                            title = if (activeSearchCount == 0) {
                                L10n.string("Create your search", "Создай свой поиск")
                            } else {
                                L10n.string("No searches in this section", "Нет поисков в этом разделе")
                            },
                            subtitle = if (activeSearchCount == 0) {
                                L10n.string(
                                    "Choose a sport, time, and place. Responses will appear here.",
                                    "Укажи вид спорта, время и место. Отклики появятся здесь.",
                                )
                            } else {
                                L10n.string("Change the filter or come back later.", "Смени фильтр или вернись позже.")
                            },
                        ) {
                            Icon(Icons.Filled.Search, null, tint = AppTheme.court, modifier = Modifier.size(28.dp))
                        }
                    }
                }
            } else if (selectedFilter == SearchListFilter.ALL) {
                allSections.forEach { section ->
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                section.title,
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = AppTheme.ink,
                            )
                            Text(
                                section.subtitle,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                color = AppTheme.ink.copy(alpha = 0.52f),
                            )
                        }
                    }
                    items(section.searches.size) { index -> cardFor(section.searches[index]) }
                }
            } else {
                items(filteredSearches.size) { index -> cardFor(filteredSearches[index]) }
            }
        }

        // `createSearchFAB`
        val fabBottomPadding by animateDpAsState(
            when (appModel.bottomBarDisplayMode) {
                BottomBarDisplayMode.EXPANDED -> 108.dp
                BottomBarDisplayMode.COMPACT -> 30.dp
                BottomBarDisplayMode.HIDDEN -> 16.dp
            },
            label = "fabBottom",
        )
        val fabWidth by animateDpAsState(
            if (isCreateFABExpanded) 190.dp else 60.dp,
            spring(dampingRatio = 0.86f),
            label = "fabWidth",
        )

        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 18.dp, bottom = fabBottomPadding)
                .width(fabWidth)
                .height(60.dp)
                .clip(CircleShape)
                .background(AppTheme.court.copy(alpha = 0.78f))
                .border(1.dp, Color.White.copy(alpha = 0.5f), CircleShape)
                .clickable {
                    hasInteractedWithCreateFAB = true
                    isCreateFABExpanded = false
                    haptics.impactMedium()
                    isPresentingComposer = true
                },
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Add, null, tint = AppTheme.ink, modifier = Modifier.size(21.dp))
            if (isCreateFABExpanded) {
                Text(
                    L10n.string("Create search", "Создать поиск"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppTheme.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun VerticalHairline() {
    Box(Modifier.width(1.dp).height(44.dp).background(AppTheme.ink.copy(alpha = 0.1f)))
}

@Composable
private fun SummaryCell(
    title: String,
    value: String,
    accent: Color,
    icon: ImageVector,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            title,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = AppTheme.ink.copy(alpha = 0.58f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                value,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Box(
                modifier = Modifier.size(28.dp).clip(CircleShape).background(accent.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, null, tint = accent, modifier = Modifier.size(14.dp))
            }
        }
    }
}
