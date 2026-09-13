package shop.sportsearch.app.ui.courts

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.filled.SportsTennis
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.matches.GameProposalSheet
import shop.sportsearch.app.ui.searches.SearchComposerScreen
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.continuousShape

private val screenBackground = Brush.linearGradient(
    listOf(Color.Black, Color(red = 4 / 255f, green = 13 / 255f, blue = 13 / 255f), Color.Black),
)

private const val SAVED_COURTS_PREFS = "sportsearch.courts"
private const val SAVED_COURTS_KEY = "savedCourtIDs"

/** Port of `struct CourtsView` in ios/TennisSearchIOS/Views/CourtsView.swift. */
@Composable
fun CourtsScreen(appModel: AppViewModel, initialSport: Sport? = null) {
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()
    val androidContext = LocalContext.current
    val prefs = remember {
        androidContext.getSharedPreferences(SAVED_COURTS_PREFS, android.content.Context.MODE_PRIVATE)
    }

    var courts by remember { mutableStateOf<List<Court>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    var selectedSport by remember { mutableStateOf(initialSport) }
    var selectedCourtId by remember { mutableStateOf<String?>(null) }
    var isLoadingCourts by remember { mutableStateOf(false) }
    var showFavoritesOnly by remember { mutableStateOf(false) }
    // `@AppStorage("savedCourtIDs")` - a comma-joined id list, same storage shape.
    var savedCourtIdsRaw by remember { mutableStateOf(prefs.getString(SAVED_COURTS_KEY, "").orEmpty()) }

    var detailCourt by remember { mutableStateOf<Court?>(null) }
    var searchComposerCourt by remember { mutableStateOf<Court?>(null) }
    var personalVisitCourt by remember { mutableStateOf<Court?>(null) }
    var playerProposal by remember { mutableStateOf<Pair<Court, MatchSummary>?>(null) }

    val savedCourtIds = remember(savedCourtIdsRaw) {
        savedCourtIdsRaw.split(",").filter { it.isNotEmpty() }.toSet()
    }

    fun toggleSavedCourt(court: Court) {
        val ids = savedCourtIds.toMutableSet()
        if (!ids.add(court.id)) ids.remove(court.id)
        savedCourtIdsRaw = ids.sorted().joinToString(",")
        prefs.edit().putString(SAVED_COURTS_KEY, savedCourtIdsRaw).apply()
    }

    val activeCityName = appModel.currentUser?.location?.city
        ?: appModel.currentUser?.city
        ?: appModel.guestDraft.location?.city
        ?: appModel.guestDraft.city

    fun updateCourt(result: Court) {
        // Detail and membership responses are unscoped; keep this list's server search context.
        val existing = courts.firstOrNull { it.id == result.id }
        val merged = if (result.nearby == null) result.copy(nearby = existing?.nearby) else result
        courts = courts.map { if (it.id == merged.id) merged else it }
        if (detailCourt?.id == merged.id) detailCourt = merged
    }

    suspend fun loadCourts() {
        isLoadingCourts = true
        runCatching {
            appModel.repository.fetchCourts(
                city = activeCityName,
                locationPlaceId = appModel.currentUser?.location?.id ?: appModel.guestDraft.location?.id,
                sport = selectedSport,
            )
        }.onSuccess { courts = it }.onFailure(appModel::present)
        isLoadingCourts = false
    }

    LaunchedEffect(activeCityName, selectedSport, appModel.currentUser?.id) {
        selectedCourtId = null
        appModel.setTabContentLoading("courts", true)
        loadCourts()
        appModel.setTabContentLoading("courts", false)
    }

    LaunchedEffect(appModel.pendingCourtID, courts) {
        val pending = appModel.pendingCourtID ?: return@LaunchedEffect
        courts.firstOrNull { it.id == pending }?.let { court ->
            appModel.pendingCourtID = null
            selectedCourtId = court.id
            detailCourt = court
            runCatching { appModel.repository.fetchCourt(court.id) }.onSuccess(::updateCourt)
        }
    }

    fun requireAuth(): Boolean {
        if (appModel.isAuthenticated) return true
        detailCourt = null
        appModel.presentAuth(AuthStep.EMAIL)
        return false
    }

    // Full-screen destinations, matching the iOS `.sheet` stack.
    detailCourt?.let { court ->
        HideBottomBarWhileVisible(appModel)
        CourtDetailSheet(
            court = court,
            isSaved = savedCourtIds.contains(court.id),
            accessLabel = courtAccessLabel(court),
            onDismiss = { detailCourt = null },
            onToggleSave = { toggleSavedCourt(court) },
            onToggleMembership = {
                if (requireAuth()) {
                    runCatching { appModel.repository.setCourtMembership(court.id, !court.isMember) }
                        .onSuccess {
                            updateCourt(it)
                            if (it.isMember) haptics.success() else haptics.warning()
                        }
                        .onFailure(appModel::present)
                }
            },
            onProposeGame = {
                if (requireAuth()) {
                    detailCourt = null
                    haptics.impactMedium()
                    searchComposerCourt = court
                }
            },
            onPlanPersonalVisit = {
                if (requireAuth()) {
                    detailCourt = null
                    haptics.impactMedium()
                    personalVisitCourt = court
                }
            },
            onProposeToPlayer = { player ->
                if (requireAuth()) {
                    haptics.impactMedium()
                    scope.launch {
                        runCatching { appModel.repository.ensureMatch(player.id) }
                            .onSuccess { match ->
                                detailCourt = null
                                playerProposal = court to match
                            }
                            .onFailure(appModel::present)
                    }
                }
            },
        )
        return
    }

    searchComposerCourt?.let { court ->
        SearchComposerScreen(
            appModel = appModel,
            initialCourt = court,
            initialSport = selectedSport ?: court.primarySport,
            onDismiss = { searchComposerCourt = null },
            onCreate = { search: GameSearch ->
                searchComposerCourt = null
                appModel.navigate(
                    AppNavigationTarget.Discover(
                        if (search.searchType == SearchType.HOT) DiscoverTab.HOT else DiscoverTab.SEEKING,
                        highlightedSearchID = search.id,
                    ),
                )
            },
        )
        return
    }

    personalVisitCourt?.let { court ->
        HideBottomBarWhileVisible(appModel)
        PersonalActivityComposerSheet(
            appModel = appModel,
            court = court,
            initialSport = selectedSport ?: court.primarySport,
            onDismiss = { personalVisitCourt = null },
            onCreated = {
                personalVisitCourt = null
                appModel.navigate(AppNavigationTarget.Discover(DiscoverTab.UPCOMING))
            },
        )
        return
    }

    playerProposal?.let { (court, match) ->
        GameProposalSheet(
            appModel = appModel,
            match = match,
            initialCourt = court,
            onDismiss = { playerProposal = null },
            onCreated = {
                playerProposal = null
                loadCourts()
            },
        )
        return
    }

    // `cityCourts` - keep server "nearby" results, otherwise filter by the active city.
    val cityCourts = courts.filter { court ->
        if (court.nearby != null) return@filter true
        val courtCity = court.city?.trim().orEmpty()
        if (courtCity.isEmpty()) return@filter false
        courtCity.equals(activeCityName.trim(), ignoreCase = true)
    }

    // `sortedCourts` - preferred districts float to the top, order otherwise preserved.
    val preferredDistrictIds = appModel.currentUser?.preferredDistricts?.takeIf { it.isNotEmpty() }
        ?: listOfNotNull(appModel.currentUser?.district?.takeIf { it.isNotEmpty() })
    val sortedCourts = if (preferredDistrictIds.isEmpty() || cityCourts.any { it.nearby != null }) {
        cityCourts
    } else {
        cityCourts.withIndex().sortedWith(
            compareBy(
                { preferredDistrictIds.indexOf(it.value.district).takeIf { i -> i >= 0 } ?: Int.MAX_VALUE },
                { it.index },
            ),
        ).map { it.value }
    }

    val sportFilteredCourts = (if (showFavoritesOnly) sortedCourts.filter { savedCourtIds.contains(it.id) } else sortedCourts)
        .filter { court ->
            val sport = selectedSport ?: return@filter true
            court.supportedSports.isEmpty() || court.supportedSports.contains(sport)
        }

    val normalizedQuery = query.trim().lowercase()
    val filteredCourts = if (normalizedQuery.isEmpty()) {
        sportFilteredCourts
    } else {
        sportFilteredCourts.filter { searchableText(it).contains(normalizedQuery) }
    }

    val suggestedCourts = if (normalizedQuery.isEmpty()) {
        emptyList()
    } else {
        val prefix = filteredCourts.filter { it.name.lowercase().startsWith(normalizedQuery) }
        val metro = filteredCourts.filter { court ->
            court.metroDisplayName?.lowercase()?.contains(normalizedQuery) == true &&
                prefix.none { it.id == court.id }
        }
        val district = filteredCourts.filter { court ->
            localizedDistrictName(court.district)?.lowercase()?.contains(normalizedQuery) == true &&
                prefix.none { it.id == court.id } && metro.none { it.id == court.id }
        }
        (prefix + metro + district).take(4)
    }

    if (isLoadingCourts && courts.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize().background(screenBackground)) {
            TennisBallsLoader(title = L10n.string("Loading courts", "Загружаем центры"))
        }
        return
    }

    Box(modifier = Modifier.fillMaxSize().background(screenBackground)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 16.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        L10n.string("Centers", "Центры"),
                        fontSize = 38.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                    Text(
                        L10n.string(
                            "$activeCityName · clubs, courts, and classes",
                            "$activeCityName · клубы, корты и секции",
                        ),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.58f),
                    )
                }
            }

            item {
                SearchField(
                    query = query,
                    onQueryChange = { query = it },
                    onClear = { query = "" },
                )
            }

            if (suggestedCourts.isNotEmpty()) {
                item {
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        suggestedCourts.forEach { court ->
                            val selected = selectedCourtId == court.id
                            val shape = continuousShape(16.dp)
                            Column(
                                modifier = Modifier
                                    .clip(shape)
                                    .background(Color.White.copy(alpha = if (selected) 0.14f else 0.07f))
                                    .border(
                                        1.dp,
                                        if (selected) CourtAccent.copy(alpha = 0.55f) else DarkStroke,
                                        shape,
                                    )
                                    .clickable {
                                        selectedCourtId = court.id
                                        haptics.selection()
                                    }
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Text(
                                    court.name,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color.White,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    court.metroDisplayName
                                        ?: localizedDistrictName(court.district)
                                        ?: court.address,
                                    style = AppText.captionSemibold,
                                    color = Color.White.copy(alpha = 0.5f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }
            }

            item {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    SportFilterChip(L10n.string("All", "Все"), null, selectedSport == null) {
                        selectedSport = null
                        showFavoritesOnly = false
                        haptics.selection()
                    }
                    // Server-side sport selection stays possible even with no local club for it.
                    Sport.entries.forEach { sport ->
                        SportFilterChip(sport.title, sport, selectedSport == sport) {
                            selectedSport = sport
                            showFavoritesOnly = false
                            haptics.selection()
                        }
                    }
                    FavoritesChip(showFavoritesOnly) {
                        showFavoritesOnly = !showFavoritesOnly
                        selectedSport = null
                        haptics.selection()
                    }
                }
            }

            item {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            L10n.string("All centers", "Все центры"),
                            fontSize = 26.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                        Text(
                            L10n.string(
                                "${filteredCourts.size} centers found",
                                "Найдено ${filteredCourts.size} центров",
                            ),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.52f),
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        L10n.string("Sort", "Сортировка"),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = CourtAccent,
                    )
                }
            }

            if (filteredCourts.isEmpty()) {
                item {
                    val shape = continuousShape(22.dp)
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(shape)
                            .background(Color.White.copy(alpha = 0.05f))
                            .border(1.dp, DarkStroke, shape)
                            .padding(vertical = 30.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(Icons.Filled.SportsTennis, null, tint = CourtAccent, modifier = Modifier.size(26.dp))
                        Text(
                            if (cityCourts.isEmpty()) {
                                L10n.string(
                                    "There are no clubs in $activeCityName yet",
                                    "В $activeCityName пока нет клубов",
                                )
                            } else {
                                L10n.string("Nothing found", "Ничего не найдено")
                            },
                            style = AppText.headline,
                            color = Color.White,
                        )
                        Text(
                            if (cityCourts.isEmpty()) {
                                L10n.string(
                                    "Clubs have not been added yet, but you can already find partners in this city.",
                                    "Клубы ещё не добавлены, но поиск партнёров в городе уже доступен.",
                                )
                            } else {
                                L10n.string(
                                    "Try another sport or search query.",
                                    "Попробуйте другой вид спорта или запрос.",
                                )
                            },
                            style = AppText.subheadline,
                            color = Color.White.copy(alpha = 0.52f),
                        )
                    }
                }
            } else {
                items(filteredCourts.size) { index ->
                    val court = filteredCourts[index]
                    CourtCard(
                        court = court,
                        selectedSport = selectedSport,
                        isSelected = selectedCourtId == court.id,
                        isSaved = savedCourtIds.contains(court.id),
                        onToggleSave = {
                            toggleSavedCourt(court)
                            haptics.selection()
                        },
                        onOpen = {
                            selectedCourtId = court.id
                            detailCourt = court
                            haptics.impactLight()
                            scope.launch {
                                runCatching { appModel.repository.fetchCourt(court.id) }
                                    .onSuccess(::updateCourt)
                                    .onFailure(appModel::present)
                            }
                        },
                    )
                }
            }
        }
    }
}

/** `courtAccessLabel(_:)` without the CoreLocation branch - the map pass adds live distance. */
private fun courtAccessLabel(court: Court): String? {
    court.nearby?.let { nearby ->
        return listOfNotNull(court.city, nearby.distanceLabel).joinToString(" · ")
    }
    if (LocaleStore.current == AppLocale.EN && court.distanceLabel == "Рядом") return "Nearby"
    return court.distanceLabel
}

private fun searchableText(court: Court): String = listOfNotNull(
    court.name,
    court.city,
    court.address,
    court.metroDisplayName,
    localizedDistrictName(court.district),
    court.supportedSports.flatMap { listOf(it.title, it.wire) }.joinToString(" ").takeIf { it.isNotEmpty() },
).joinToString(" ").lowercase()

@Composable
private fun SearchField(query: String, onQueryChange: (String) -> Unit, onClear: () -> Unit) {
    val shape = continuousShape(20.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, DarkStroke, shape)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Search, null, tint = Color.White.copy(alpha = 0.44f), modifier = Modifier.size(18.dp))

        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (query.isEmpty()) {
                Text(
                    L10n.string("Club, metro, district, or sport", "Клуб, метро, район или спорт"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.32f),
                )
            }
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = AppText.body.copy(color = Color.White),
                cursorBrush = SolidColor(CourtAccent),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (query.isNotEmpty()) {
            Icon(
                Icons.Filled.Cancel,
                null,
                tint = Color.White.copy(alpha = 0.34f),
                modifier = Modifier.size(18.dp).clickable(onClick = onClear),
            )
        } else {
            Box(
                modifier = Modifier.size(34.dp).clip(CircleShape).background(CourtAccent.copy(alpha = 0.13f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.MyLocation, null, tint = CourtAccent, modifier = Modifier.size(15.dp))
            }
        }
    }
}

@Composable
private fun SportFilterChip(title: String, sport: Sport?, isSelected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(if (isSelected) CourtAccent else Color.White.copy(alpha = 0.06f))
            .border(1.dp, if (isSelected) CourtAccent else DarkStroke, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (sport != null) {
            SportIconView(sport = sport, color = if (isSelected) Color.Black else Color.White, size = 14.dp)
        }
        Text(
            title,
            style = AppText.subheadlineSemibold,
            color = if (isSelected) Color.Black else Color.White,
            maxLines = 1,
        )
    }
}

@Composable
private fun FavoritesChip(isOn: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(if (isOn) CourtAccent else Color.White.copy(alpha = 0.06f))
            .border(1.dp, if (isOn) CourtAccent else DarkStroke, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (isOn) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            null,
            tint = if (isOn) Color.Black else Color.White,
            modifier = Modifier.size(12.dp),
        )
        Text(
            L10n.string("Favorites", "Избранные"),
            style = AppText.subheadlineSemibold,
            color = if (isOn) Color.Black else Color.White,
            maxLines = 1,
        )
    }
}

/** Port of `courtCard(_:)`. */
@Composable
private fun CourtCard(
    court: Court,
    selectedSport: Sport?,
    isSelected: Boolean,
    isSaved: Boolean,
    onToggleSave: () -> Unit,
    onOpen: () -> Unit,
) {
    val shape = continuousShape(22.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(Color.White.copy(alpha = 0.075f), Color.White.copy(alpha = 0.04f)),
                ),
            )
            .border(1.dp, if (isSelected) CourtAccent.copy(alpha = 0.48f) else DarkStroke, shape)
            .clickable(onClick = onOpen)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
            CourtImageTile(court, 112.dp)

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            court.name,
                            fontSize = 21.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            court.sportsTitle(selectedSport),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = CourtAccent,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }

                    Box(
                        modifier = Modifier.size(34.dp).clickable(onClick = onToggleSave),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            if (isSaved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                            null,
                            tint = Color.White.copy(alpha = 0.92f),
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }

                Text(
                    listOfNotNull(localizedDistrictName(court.district), courtAccessLabel(court)).joinToString(" · "),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.68f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Outlined.Place,
                        null,
                        tint = Color.White.copy(alpha = 0.56f),
                        modifier = Modifier.size(13.dp),
                    )
                    Text(
                        court.metroDisplayName ?: court.displayAddress,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.56f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    court.displayTags.take(3).forEach { CourtAmenityPill(it) }
                }
            }
        }

        Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            ActiveSearchBadge(court)

            Spacer(Modifier.weight(1f))

            CourtActiveSearchAvatars(
                users = court.activeSearchPreviewUsers,
                overflowCount = maxOf(court.activeSearchPlayersCount - court.activeSearchPreviewUsers.size, 0),
                size = 28.dp,
            )

            Icon(
                Icons.Filled.ChevronRight,
                null,
                tint = Color.White.copy(alpha = 0.34f),
                modifier = Modifier.size(14.dp),
            )
        }
    }
}

@Composable
private fun ActiveSearchBadge(court: Court) {
    val count = if (court.activeSearchPlayersCount > 0) court.activeSearchPlayersCount else court.activeSearchesCount
    val hasSearches = count > 0

    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(if (hasSearches) CourtAccent else Color.White.copy(alpha = 0.28f)),
        )
        Text(
            if (hasSearches) activeSearchText(count) else L10n.string("No active searches", "Нет активных поисков"),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (hasSearches) Color.White.copy(alpha = 0.82f) else Color.White.copy(alpha = 0.46f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
