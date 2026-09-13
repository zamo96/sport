package shop.sportsearch.app.ui.searches

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.AppNavigationTarget
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.DayOfWeek
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.RegularPairOccurrence
import shop.sportsearch.app.core.RegularPairSummary
import shop.sportsearch.app.core.TimeRange
import shop.sportsearch.app.core.displayName
import shop.sportsearch.app.core.parseServerInstant
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.AppScreen
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.EmptyStateView
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.LoadingOverlay
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/** Port of `struct RegularPairDetailSheet`. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun RegularPairDetailSheet(
    appModel: AppViewModel,
    regularPairId: String,
    onDismiss: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    HideBottomBarWhileVisible(appModel)

    val scope = rememberCoroutineScope()
    val zone = remember { ZoneId.systemDefault() }

    var regularPair by remember { mutableStateOf<RegularPairSummary?>(null) }
    var courts by remember { mutableStateOf<List<Court>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var editingOccurrence by remember { mutableStateOf<RegularPairOccurrence?>(null) }
    var updatingOccurrenceId by remember { mutableStateOf<String?>(null) }

    suspend fun loadRegularPair() {
        isLoading = true
        runCatching { appModel.repository.fetchRegularPair(regularPairId) }
            .onSuccess { regularPair = it }
            .onFailure(appModel::present)
        isLoading = false
    }

    suspend fun loadCourtsIfNeeded() {
        if (courts.isNotEmpty()) return
        runCatching { appModel.repository.fetchCourts() }
            .onSuccess { courts = it }
            .onFailure(appModel::present)
    }

    suspend fun updateOccurrence(
        occurrenceId: String,
        status: String?,
        scheduledAt: Instant?,
        proposedCourtId: String?,
    ) {
        updatingOccurrenceId = occurrenceId
        runCatching {
            appModel.repository.updateRegularPairOccurrence(
                regularPairId = regularPairId,
                occurrenceId = occurrenceId,
                status = status,
                scheduledAt = scheduledAt,
                proposedCourtId = proposedCourtId,
            )
        }.onSuccess {
            editingOccurrence = null
            loadRegularPair()
            appModel.refreshActivitySummary()
        }.onFailure(appModel::present)
        updatingOccurrenceId = null
    }

    LaunchedEffect(regularPairId) {
        loadRegularPair()
        loadCourtsIfNeeded()
    }

    // `upcomingOccurrences` - only future slots, earliest first.
    val upcoming = remember(regularPair) {
        regularPair?.occurrences.orEmpty()
            .filter { (parseServerInstant(it.scheduledAt) ?: Instant.MIN) > Instant.now() }
            .sortedBy { parseServerInstant(it.scheduledAt) ?: Instant.MAX }
    }

    editingOccurrence?.let { occurrence ->
        RegularPairOccurrenceEditorSheet(
            occurrence = occurrence,
            courts = courts,
            onDismiss = { editingOccurrence = null },
            onSave = { date, courtId ->
                updateOccurrence(occurrence.id, null, date, courtId)
            },
        )
        return
    }

    AppScreen {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                SheetHeader(
                    title = L10n.string("Regular pair", "Регулярная пара"),
                    onClose = onDismiss,
                )
            }

            val pair = regularPair
            when {
                pair != null -> {
                    item { RegularPairHeaderCard(appModel, pair, onDismiss) { scope.launch { loadRegularPair() } } }

                    if (upcoming.isEmpty()) {
                        item {
                            SectionCard(
                                title = L10n.string("Upcoming slots", "Ближайшие слоты"),
                                subtitle = L10n.string("No new proposals yet.", "Новых предложений пока нет."),
                            ) {
                                EmptyStateView(
                                    title = L10n.string("No slots yet", "Слоты пока не появились"),
                                    subtitle = L10n.string(
                                        "Once the schedule syncs, the next two weeks of games appear here.",
                                        "Когда расписание синхронизируется, здесь появятся ближайшие игры на 2 недели.",
                                    ),
                                ) {
                                    Icon(
                                        Icons.Filled.Group,
                                        contentDescription = null,
                                        tint = AppTheme.court,
                                        modifier = Modifier.height(34.dp),
                                    )
                                }
                            }
                        }
                    } else {
                        item {
                            SectionCard(
                                title = L10n.string("Upcoming slots", "Ближайшие слоты"),
                                subtitle = L10n.string(
                                    "Confirm quickly, or adjust the date, time and club.",
                                    "Можно быстро подтвердить или поправить дату, время и клуб.",
                                ),
                            ) {}
                        }

                        items(upcoming.size) { index ->
                            val occurrence = upcoming[index]
                            RegularPairOccurrenceDetailCard(
                                occurrence = occurrence,
                                partnerName = pair.partnerUser.displayName,
                                courts = courts,
                                currentUserId = appModel.currentUser?.id,
                                isUpdating = updatingOccurrenceId == occurrence.id,
                                onConfirm = { scope.launch { updateOccurrence(occurrence.id, "confirmed", null, null) } },
                                onDecline = { scope.launch { updateOccurrence(occurrence.id, "declined", null, null) } },
                                onShiftDay = { delta ->
                                    val current = parseServerInstant(occurrence.scheduledAt)
                                    val next = current?.atZone(zone)?.plusDays(delta.toLong())?.toInstant()
                                    when {
                                        next == null -> appModel.errorMessage =
                                            L10n.string("Could not change the slot date.", "Не удалось изменить дату слота.")
                                        !next.isAfter(Instant.now()) -> appModel.errorMessage =
                                            L10n.string("A slot cannot move into the past.", "Слот нельзя перенести в прошлое.")
                                        else -> scope.launch { updateOccurrence(occurrence.id, null, next, null) }
                                    }
                                },
                                onApplyTimeRange = { range ->
                                    val current = parseServerInstant(occurrence.scheduledAt)
                                    val next = current?.let { applyTimeRange(it, range, zone) }
                                    when {
                                        next == null -> appModel.errorMessage =
                                            L10n.string("Could not change the slot time.", "Не удалось изменить время слота.")
                                        !next.isAfter(Instant.now()) -> appModel.errorMessage =
                                            L10n.string("That time has already passed.", "Выбранное время уже прошло.")
                                        else -> scope.launch { updateOccurrence(occurrence.id, null, next, null) }
                                    }
                                },
                                onApplyCourt = { courtId ->
                                    scope.launch { updateOccurrence(occurrence.id, null, null, courtId) }
                                },
                                onEdit = {
                                    scope.launch {
                                        loadCourtsIfNeeded()
                                        editingOccurrence = occurrence
                                    }
                                },
                            )
                        }
                    }
                }

                isLoading -> item { LoadingOverlay(modifier = Modifier.height(180.dp)) }

                else -> item {
                    SectionCard(
                        title = L10n.string("Regular pair", "Регулярная пара"),
                        subtitle = L10n.string("Could not load the data.", "Не удалось загрузить данные."),
                    ) {
                        PrimaryActionButton(
                            title = L10n.string("Try again", "Повторить"),
                            onClick = { scope.launch { loadRegularPair() } },
                            tint = AppTheme.ink,
                        )
                    }
                }
            }
        }
    }
}

/** `date(byApplying:to:)` - morning 09:00, afternoon 14:00, evening 19:00. */
private fun applyTimeRange(base: Instant, range: TimeRange, zone: ZoneId): Instant {
    val day = base.atZone(zone).toLocalDate()
    val hour = when (range) {
        TimeRange.MORNING -> 9
        TimeRange.DAY -> 14
        TimeRange.EVENING -> 19
    }
    return LocalDateTime.of(day, java.time.LocalTime.of(hour, 0)).atZone(zone).toInstant()
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun RegularPairHeaderCard(
    appModel: AppViewModel,
    pair: RegularPairSummary,
    onDismiss: () -> Unit,
    onRefresh: () -> Unit,
) {
    SectionCard(
        title = pair.partnerUser.displayName,
        subtitle = L10n.string(
            "Confirm slots, change the time and club, then move to the chat.",
            "Подтверждай слоты, меняй время и клуб, а потом переходи в чат.",
        ),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            RemoteAvatarView(name = pair.partnerUser.displayName, path = pair.partnerUser.avatarUrl, size = 60.dp)

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    L10n.string("Regular pair", "Регулярная пара").uppercase(),
                    style = AppText.captionSemibold,
                    letterSpacing = 1.6.sp,
                    color = AppTheme.court,
                )
                pair.comment?.trim()?.takeIf { it.isNotEmpty() }?.let { comment ->
                    Text(
                        comment,
                        style = AppText.footnote,
                        color = AppTheme.ink.copy(alpha = 0.68f),
                        maxLines = 3,
                    )
                }
            }
        }

        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            pair.preferredDays.forEach { day ->
                AppInlineChip(DayOfWeek.from(day)?.title ?: day, AppTheme.cream, AppTheme.ink)
            }
            pair.preferredTimeRanges.forEach { range ->
                AppInlineChip(TimeRange.from(range)?.title ?: range, AppTheme.cream, AppTheme.ink)
            }
            pair.preferredCourt?.name?.let { AppInlineChip(it, AppTheme.mint, AppTheme.court) }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SecondaryActionButton(
                title = L10n.string("Open chat", "Открыть чат"),
                onClick = {
                    appModel.pendingChatMatchID = pair.matchId
                    appModel.navigate(AppNavigationTarget.Matches)
                    onDismiss()
                },
                modifier = Modifier.weight(1f),
                tint = AppTheme.ink,
            )
            PrimaryActionButton(
                title = L10n.string("Refresh", "Обновить"),
                onClick = onRefresh,
                modifier = Modifier.weight(1f),
                tint = AppTheme.court,
            )
        }
    }
}
