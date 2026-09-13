package shop.sportsearch.app.ui.searches

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct SearchDetailSheet` in ios/TennisSearchIOS/Views/SearchesView.swift. */
@Composable
fun SearchDetailSheet(
    appModel: AppViewModel,
    initialSearch: GameSearch,
    onDismiss: () -> Unit,
    onEdit: (GameSearch) -> Unit,
    onOpenLobby: (String) -> Unit,
    onReloadParent: suspend () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    HideBottomBarWhileVisible(appModel)
    val scope = rememberCoroutineScope()
    val androidContext = LocalContext.current

    var search by remember(initialSearch.id) { mutableStateOf(initialSearch) }
    var updatingSearchID by remember { mutableStateOf<String?>(null) }
    var updatingResponseID by remember { mutableStateOf<String?>(null) }
    var updatingOccurrenceID by remember { mutableStateOf<String?>(null) }
    var editingOccurrence by remember { mutableStateOf<RegularPairOccurrence?>(null) }
    var occurrenceCourts by remember { mutableStateOf<List<Court>>(emptyList()) }
    var didCopyInviteLink by remember { mutableStateOf(false) }
    var isPresentingResponses by remember { mutableStateOf(false) }
    var isFinalizingRoster by remember { mutableStateOf(false) }

    val approvedResponses = search.responses.filter { it.status == "approved" }
    val pendingResponses = search.responses.filter { it.status == "pending" }
    val remainingSeats = maxOf(search.playersNeeded - approvedResponses.size, 0)
    val isCompleted = search.status == "matched" || approvedResponses.size >= maxOf(search.playersNeeded, 1)
    val canManageSearch = !isCompleted
    val isActive = search.isActive ?: true
    val shouldShowLobbyButton = search.playersNeeded > 1 && approvedResponses.isNotEmpty()
    val usesRegularSlotLobby = search.searchType == SearchType.REGULAR && search.playersNeeded <= 1
    val inviteUrl = AppConfig.searchInviteUrl(search.inviteSlug ?: search.id)

    suspend fun reloadSearch() {
        runCatching { appModel.repository.fetchSearches() }
            .onSuccess { list -> list.firstOrNull { it.id == search.id }?.let { search = it } }
            .onFailure(appModel::present)
        onReloadParent()
    }

    fun shareInviteLink() {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(
                Intent.EXTRA_TEXT,
                L10n.string(
                    "Join my game search on TennisSearch",
                    "Присоединяйся к моему поиску игры в TennisSearch",
                ) + "\n" + inviteUrl,
            )
        }
        runCatching { androidContext.startActivity(Intent.createChooser(intent, null)) }
    }

    LaunchedEffect(didCopyInviteLink) {
        if (didCopyInviteLink) {
            delay(1400)
            didCopyInviteLink = false
        }
    }

    if (isPresentingResponses) {
        SearchResponsesSheet(
            appModel = appModel,
            search = search,
            updatingResponseID = updatingResponseID,
            isFinalizingRoster = isFinalizingRoster,
            onDismiss = { isPresentingResponses = false },
            onUpdateResponseStatus = { responseId, status ->
                scope.launch {
                    updatingResponseID = responseId
                    runCatching { appModel.repository.updateSearchResponseStatus(responseId, status) }
                        .onSuccess { result ->
                            search = search.applying(result)
                            runCatching { appModel.repository.fetchSearches() }.onSuccess { list ->
                                list.firstOrNull { it.id == search.id }?.let { search = it.applying(result) }
                            }
                            onReloadParent()
                        }
                        .onFailure(appModel::present)
                    updatingResponseID = null
                }
            },
            onShareInviteLink = ::shareInviteLink,
            onFinalizeRoster = {
                scope.launch {
                    val scheduledAt = parseServerInstant(search.hotStartsAt)
                    if (scheduledAt == null) {
                        appModel.errorMessage = L10n.string(
                            "Could not determine the game time",
                            "Не удалось определить время игры",
                        )
                        return@launch
                    }
                    isFinalizingRoster = true
                    runCatching {
                        appModel.repository.scheduleSearchGame(
                            searchId = search.id,
                            courtId = search.preferredCourt?.id,
                            scheduledAt = scheduledAt,
                            durationMinutes = search.durationMinutes ?: 90,
                        )
                    }.onSuccess { result ->
                        search = result.gameSearch
                        onReloadParent()
                        isPresentingResponses = false
                        result.gameRequestId?.let { id ->
                            onDismiss()
                            appModel.navigate(
                                AppNavigationTarget.Discover(DiscoverTab.UPCOMING, highlightedGameRequestID = id),
                            )
                        }
                    }.onFailure(appModel::present)
                    isFinalizingRoster = false
                }
            },
            onOpenLobby = {
                isPresentingResponses = false
                onOpenLobby(search.id)
            },
        )
        return
    }

    // `.sheet(item: $editingOccurrence)` в SearchesView.swift:1529.
    editingOccurrence?.let { occurrence ->
        val regularPair = search.regularPair
        if (regularPair == null) {
            editingOccurrence = null
        } else {
            RegularPairOccurrenceEditorSheet(
                occurrence = occurrence,
                courts = occurrenceCourts,
                onDismiss = { editingOccurrence = null },
                onSave = { date, courtId ->
                    updatingOccurrenceID = occurrence.id
                    runCatching {
                        appModel.repository.updateRegularPairOccurrence(
                            regularPairId = regularPair.id,
                            occurrenceId = occurrence.id,
                            status = null,
                            scheduledAt = date,
                            proposedCourtId = courtId,
                        )
                    }.onSuccess { reloadSearch() }.onFailure(appModel::present)
                    updatingOccurrenceID = null
                    editingOccurrence = null
                },
            )
            return
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Color.White).statusBarsPadding()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HeaderIcon(Icons.AutoMirrored.Filled.ArrowBack, onDismiss)
            Spacer(Modifier.weight(1f))
            Text(
                L10n.string("Game search", "Поиск игры"),
                style = AppText.headline,
                color = AppTheme.ink,
            )
            Spacer(Modifier.weight(1f))
            HeaderIcon(Icons.Filled.Share, ::shareInviteLink)
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = 16.dp)
                .padding(top = 14.dp, bottom = 34.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            DetailHero(search, isActive, approvedResponses.size, isCompleted)

            ResponseSummaryCard(search, pendingResponses.size) { isPresentingResponses = true }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                DetailActionButton(
                    L10n.string("Responses", "Отклики"),
                    Icons.Filled.HowToReg,
                    AppTheme.court,
                    Color.White,
                    bordered = false,
                    modifier = Modifier.weight(1f),
                ) { isPresentingResponses = true }

                if (canManageSearch) {
                    DetailActionButton(
                        L10n.string("Edit", "Изменить"),
                        Icons.Filled.Edit,
                        Color.White,
                        AppTheme.ink,
                        bordered = true,
                        modifier = Modifier.weight(1f),
                    ) { onEdit(search) }

                    DetailActionButton(
                        if (isActive) L10n.string("Pause", "Пауза") else L10n.string("Start", "Запуск"),
                        if (isActive) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        Color.White,
                        AppTheme.ink,
                        bordered = true,
                        modifier = Modifier.weight(1f),
                    ) {
                        scope.launch {
                            updatingSearchID = search.id
                            runCatching { appModel.repository.setSearchActive(search.id, !isActive) }
                                .onSuccess {
                                    search = it
                                    onReloadParent()
                                }
                                .onFailure(appModel::present)
                            updatingSearchID = null
                        }
                    }
                }
            }

            ParameterCard(search, remainingSeats)

            if (shouldShowLobbyButton) {
                LobbyActionCard(search, usesRegularSlotLobby) { onOpenLobby(search.id) }
            }

            search.regularPair?.let { regularPair ->
                SearchEmbeddedSection(
                    title = L10n.string("Recurring time slots", "Регулярные слоты"),
                    subtitle = L10n.string(
                        "Confirm upcoming slots and open the pair chat.",
                        "Подтверждай ближайшие слоты и открывай чат пары.",
                    ),
                ) {
                    val upcoming = regularPair.occurrences
                        .filter { (parseServerInstant(it.scheduledAt) ?: Instant.EPOCH) > Instant.now() }
                        .sortedBy { parseServerInstant(it.scheduledAt) ?: Instant.MAX }

                    fun updateOccurrence(occurrenceId: String, status: String?) {
                        scope.launch {
                            updatingOccurrenceID = occurrenceId
                            runCatching {
                                appModel.repository.updateRegularPairOccurrence(
                                    regularPairId = regularPair.id,
                                    occurrenceId = occurrenceId,
                                    status = status,
                                    scheduledAt = null,
                                    proposedCourtId = null,
                                )
                            }.onSuccess { reloadSearch() }.onFailure(appModel::present)
                            updatingOccurrenceID = null
                        }
                    }

                    RegularPairCard(
                        regularPair = regularPair,
                        currentUserId = appModel.currentUser?.id,
                        upcomingOccurrences = upcoming,
                        updatingOccurrenceID = updatingOccurrenceID,
                        onOpenChat = {
                            appModel.pendingChatMatchID = regularPair.matchId
                            onDismiss()
                            appModel.navigate(AppNavigationTarget.Matches)
                        },
                        onConfirmOccurrence = { updateOccurrence(it.id, "confirmed") },
                        onDeclineOccurrence = { updateOccurrence(it.id, "declined") },
                        onEditOccurrence = { occurrence ->
                            scope.launch {
                                if (occurrenceCourts.isEmpty()) {
                                    occurrenceCourts = runCatching { appModel.repository.fetchCourts() }
                                        .getOrElse { appModel.present(it); emptyList() }
                                }
                                editingOccurrence = occurrence
                            }
                        },
                    )
                }
            }

            InviteCard(
                inviteUrl = inviteUrl,
                didCopy = didCopyInviteLink,
                onCopy = {
                    val clipboard = androidContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("invite", inviteUrl))
                    didCopyInviteLink = true
                },
            )

            if (canManageSearch) {
                Box {
                    SecondaryActionButton(
                        title = if (isActive) {
                            L10n.string("Pause search", "Остановить поиск")
                        } else {
                            L10n.string("Start search", "Запустить поиск")
                        },
                        tint = Color.Red.copy(alpha = 0.88f),
                        enabled = updatingSearchID != search.id,
                        onClick = {
                            scope.launch {
                                updatingSearchID = search.id
                                runCatching { appModel.repository.setSearchActive(search.id, !isActive) }
                                    .onSuccess {
                                        search = it
                                        onReloadParent()
                                    }
                                    .onFailure(appModel::present)
                                updatingSearchID = null
                            }
                        },
                    )
                    if (updatingSearchID == search.id) {
                        Box(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(
                                color = AppTheme.court,
                                strokeWidth = 2.dp,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HeaderIcon(icon: ImageVector, onClick: () -> Unit) {
    Box(modifier = Modifier.size(44.dp).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = AppTheme.ink, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun DetailHero(search: GameSearch, isActive: Boolean, approvedCount: Int, isCompleted: Boolean) {
    val headline = when {
        isCompleted -> L10n.string("Roster complete", "Состав собран")
        search.desiredLevelMin != null && search.desiredLevelMax != null -> L10n.string(
            "Looking for ${search.playersNeeded} player(s), level ${search.desiredLevelMin}–${search.desiredLevelMax}",
            "Ищу ${search.playersNeeded} игроков уровня ${search.desiredLevelMin}–${search.desiredLevelMax}",
        )
        else -> L10n.string(
            "Looking for ${search.playersNeeded} player(s)",
            "Ищу ${search.playersNeeded} игроков",
        )
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(24.dp))
            .background(Brush.linearGradient(listOf(AppTheme.court, AppTheme.ink)))
            .padding(15.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier.size(42.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                SportIconView(sport = search.sport, color = Color.White, size = 20.dp)
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "${search.sport.title} · ${search.sport.formatTitle(search.format, search.playersNeeded)}",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.92f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    headline,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            AppInlineChip(
                text = if (isActive) L10n.string("Active", "Активен") else L10n.string("Paused", "На паузе"),
                tint = Color.White.copy(alpha = 0.18f),
                foreground = Color.White,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                HeroMeta(
                    Icons.Filled.CalendarMonth,
                    search.preferredDays.mapNotNull { DayOfWeek.from(it)?.shortTitle }.joinToString(", "),
                    Modifier.weight(1f),
                )
                HeroMeta(
                    Icons.Filled.Schedule,
                    search.preferredTimeRanges.map(::localizedTimePreferenceTitle).joinToString(" · "),
                    Modifier.weight(1f),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                HeroMeta(
                    Icons.Filled.Map,
                    search.preferredDistricts.mapNotNull(::localizedDistrictName).joinToString(", "),
                    Modifier.weight(1f),
                )
                HeroMeta(
                    Icons.Filled.Apartment,
                    search.preferredCourt?.name ?: L10n.string("No club", "Без клуба"),
                    Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun HeroMeta(icon: ImageVector, text: String, modifier: Modifier = Modifier) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(12.dp))
        Text(
            text.ifEmpty { L10n.string("Not specified", "Не указано") },
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.92f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ResponseSummaryCard(search: GameSearch, pendingCount: Int, onOpen: () -> Unit) {
    val shape = continuousShape(22.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .clickable(onClick = onOpen)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    L10n.string("${search.responses.size} responses", "${search.responses.size} откликов"),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                )
                if (pendingCount > 0) {
                    Text(
                        L10n.string("· $pendingCount new", "· $pendingCount новых"),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Red.copy(alpha = 0.9f),
                    )
                }
            }
            Text(
                L10n.string(
                    "Players who responded to this search",
                    "Откликнувшиеся игроки по этому поиску",
                ),
                style = AppText.subheadline,
                color = AppTheme.ink.copy(alpha = 0.56f),
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy((-10).dp)) {
            search.responses.take(4).forEach { response ->
                RemoteAvatarView(
                    name = response.responderUser.displayName,
                    path = response.responderUser.avatarUrl,
                    size = 34.dp,
                    modifier = Modifier.border(2.dp, Color.White, CircleShape),
                )
            }
            val overflow = maxOf(search.responses.size - 4, 0)
            if (overflow > 0) {
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.05f))
                        .border(2.dp, Color.White, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("+$overflow", style = AppText.captionBold, color = AppTheme.ink.copy(alpha = 0.72f))
                }
            }
        }

        Icon(
            Icons.Filled.ChevronRight,
            null,
            tint = AppTheme.ink.copy(alpha = 0.28f),
            modifier = Modifier.size(13.dp),
        )
    }
}

@Composable
private fun DetailActionButton(
    title: String,
    icon: ImageVector,
    background: Color,
    foreground: Color,
    bordered: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = continuousShape(14.dp)
    Row(
        modifier = modifier
            .height(38.dp)
            .clip(shape)
            .background(background)
            .then(if (bordered) Modifier.border(1.dp, Color.Black.copy(alpha = 0.08f), shape) else Modifier)
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = foreground, modifier = Modifier.size(13.dp))
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = foreground, maxLines = 1)
    }
}

@Composable
private fun ParameterCard(search: GameSearch, remainingSeats: Int) {
    data class Row3(val icon: ImageVector, val title: String, val value: String)

    val rows = buildList {
        add(
            Row3(
                Icons.Filled.SportsTennis,
                L10n.string("Game format", "Формат игры"),
                search.sport.formatTitle(search.format, search.playersNeeded),
            ),
        )
        add(
            Row3(
                Icons.Filled.People,
                L10n.string("Players needed", "Нужно игроков"),
                if (remainingSeats == 0) {
                    L10n.string("${search.playersNeeded} · roster complete", "${search.playersNeeded} · состав собран")
                } else {
                    L10n.string(
                        "${search.playersNeeded} · $remainingSeats left",
                        "${search.playersNeeded} · осталось $remainingSeats",
                    )
                },
            ),
        )

        val min = search.desiredLevelMin
        val max = search.desiredLevelMax
        if (min != null && max != null) {
            add(Row3(Icons.Filled.BarChart, L10n.string("Level", "Уровень"), "$min–$max"))
        }

        val schedule = if (search.searchType == SearchType.HOT) {
            listOfNotNull(search.hotWindow?.title, search.hotStartsAt?.formattedDateTime()).joinToString(" · ")
        } else {
            listOf(
                search.preferredDays.mapNotNull { DayOfWeek.from(it)?.shortTitle }.joinToString(", "),
                search.preferredTimeRanges.map(::localizedTimePreferenceTitle).joinToString(", "),
            ).filter { it.isNotEmpty() }.joinToString(" · ")
        }
        if (schedule.isNotEmpty()) {
            add(Row3(Icons.Filled.Schedule, L10n.string("Time", "Время"), schedule))
        }

        val districts = search.preferredDistricts.mapNotNull(::localizedDistrictName).joinToString(", ")
        if (districts.isNotEmpty()) {
            add(Row3(Icons.Filled.Map, L10n.string("Districts", "Районы"), districts))
        }

        val venue = search.preferredCourt?.name
            ?: search.customVenueAddress
            ?: search.customVenueTitle
            ?: if (search.sport.isRouteSport) {
                L10n.string("Route not specified", "Маршрут не указан")
            } else {
                L10n.string("Not specified", "Не указан")
            }
        add(
            Row3(
                Icons.Filled.Apartment,
                if (search.sport.isRouteSport) {
                    L10n.string("Route", "Маршрут")
                } else {
                    L10n.string("Court / club", "Корт / клуб")
                },
                venue,
            ),
        )

        if (search.sport.isRouteSport) {
            search.runningRoute?.trim()?.takeIf { it.isNotEmpty() }?.let {
                add(Row3(Icons.Filled.Route, L10n.string("Route details", "Детали маршрута"), it))
            }
        }

        add(
            Row3(
                Icons.AutoMirrored.Filled.Message,
                L10n.string("Comment", "Комментарий"),
                search.comment?.trim()?.takeIf { it.isNotEmpty() } ?: L10n.string("Not specified", "Не указан"),
            ),
        )
    }

    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape),
    ) {
        Text(
            L10n.string("Details", "Параметры"),
            fontSize = 21.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
            modifier = Modifier.padding(horizontal = 18.dp).padding(top = 16.dp, bottom = 4.dp),
        )

        rows.forEachIndexed { index, row ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(modifier = Modifier.size(22.dp), contentAlignment = Alignment.CenterStart) {
                    Icon(row.icon, null, tint = AppTheme.ink.copy(alpha = 0.64f), modifier = Modifier.size(15.dp))
                }
                Text(
                    row.title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppTheme.ink.copy(alpha = 0.72f),
                )
                Spacer(Modifier.weight(1f))
                Text(
                    row.value,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppTheme.ink,
                    textAlign = TextAlign.End,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1.6f, fill = false),
                )
                Icon(
                    Icons.Filled.ChevronRight,
                    null,
                    tint = AppTheme.ink.copy(alpha = 0.24f),
                    modifier = Modifier.size(12.dp),
                )
            }

            if (index < rows.lastIndex) {
                Box(
                    Modifier
                        .padding(start = 52.dp)
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(AppTheme.ink.copy(alpha = 0.08f)),
                )
            }
        }
    }
}

@Composable
private fun LobbyActionCard(search: GameSearch, usesRegularSlotLobby: Boolean, onOpen: () -> Unit) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppTheme.mint.copy(alpha = 0.46f))
            .border(1.dp, AppTheme.court.copy(alpha = 0.14f), shape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                if (search.searchType == SearchType.REGULAR) Icons.Filled.CalendarMonth else Icons.Filled.Groups,
                null,
                tint = AppTheme.court,
                modifier = Modifier.size(22.dp),
            )
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    if (usesRegularSlotLobby) {
                        L10n.string("Suggest a time to play", "Предложите время для игры")
                    } else {
                        L10n.string("Roster and game chat", "Состав и чат игры")
                    },
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                )
                Text(
                    if (usesRegularSlotLobby) {
                        L10n.string(
                            "Open the shared roster to suggest time slots and discuss the game.",
                            "Открой общий состав, чтобы предложить слоты и обсудить детали игры.",
                        )
                    } else {
                        L10n.string(
                            "Open the roster chat to discuss details without a time-slot poll.",
                            "Открой общий чат состава, чтобы уточнить детали без опроса по слотам.",
                        )
                    },
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.62f),
                )
            }
        }

        PrimaryActionButton(
            title = if (usesRegularSlotLobby) {
                L10n.string("Suggest time slots", "Предложить слоты")
            } else {
                L10n.string("Open roster", "Открыть состав")
            },
            tint = AppTheme.ink,
            onClick = onOpen,
        )
    }
}

@Composable
private fun InviteCard(inviteUrl: String, didCopy: Boolean, onCopy: () -> Unit) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            L10n.string("Invitation link", "Ссылка-приглашение"),
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
        )
        Text(
            L10n.string(
                "Share the link so players can respond",
                "Делитесь ссылкой, чтобы игроки могли откликнуться",
            ),
            style = AppText.subheadline,
            color = AppTheme.ink.copy(alpha = 0.58f),
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(continuousShape(18.dp))
                .background(Color.Black.copy(alpha = 0.03f))
                .padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                inviteUrl,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.court,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )

            Row(
                modifier = Modifier.clickable(onClick = onCopy),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (didCopy) {
                    Text(
                        L10n.string("Copied", "Скопировано"),
                        style = AppText.caption2Semibold,
                        color = AppTheme.court,
                    )
                }
                Icon(
                    if (didCopy) Icons.Filled.Check else Icons.Filled.ContentCopy,
                    null,
                    tint = if (didCopy) AppTheme.court else AppTheme.ink,
                    modifier = Modifier.size(17.dp),
                )
            }
        }
    }
}

/** Port of `struct SearchEmbeddedSection`. */
@Composable
fun SearchEmbeddedSection(
    title: String,
    subtitle: String,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.padding(top = 2.dp).fillMaxWidth().height(1.dp).background(AppTheme.ink.copy(alpha = 0.08f)))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = AppText.headline, color = AppTheme.ink)
            Text(subtitle, style = AppText.subheadline, color = AppTheme.ink.copy(alpha = 0.6f))
        }
        content()
    }
}
