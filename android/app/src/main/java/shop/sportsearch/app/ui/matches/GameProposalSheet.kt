package shop.sportsearch.app.ui.matches

import android.content.Intent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import kotlin.math.ceil
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.core.BottomBarDisplayMode
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.SuccessCelebrationOverlay
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.searches.SearchClubPickerSheet
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `enum ProposalSheetContext`. */
enum class ProposalSheetContext {
    NEW, EDIT, RESCHEDULE, RELOCATE;

    val title: String
        get() = when (this) {
            NEW -> L10n.string("Propose a game", "Предложить игру")
            EDIT -> L10n.string("Edit proposal", "Изменить предложение")
            RESCHEDULE -> L10n.string("Suggest another time", "Предложить другое время")
            RELOCATE -> L10n.string("Suggest another venue", "Предложить другое место")
        }

    val subtitlePrefix: String
        get() = when (this) {
            NEW -> L10n.string("Create a new game", "Создай новую договоренность")
            EDIT -> L10n.string("Update the current game", "Обнови текущую договоренность")
            RESCHEDULE -> L10n.string("Update the game time", "Обнови время договоренности")
            RELOCATE -> L10n.string("Update the game venue", "Обнови место договоренности")
        }

    val submitTitle: String
        get() = when (this) {
            NEW -> L10n.string("Send proposal", "Отправить предложение")
            EDIT -> L10n.string("Save changes", "Сохранить изменения")
            RESCHEDULE -> L10n.string("Send new time", "Отправить новое время")
            RELOCATE -> L10n.string("Send new venue", "Отправить новое место")
        }
}

private val zone: ZoneId get() = ZoneId.systemDefault()

/**
 * `GameProposalSheet.initialProposalDate(from:)` - anything in the past is
 * pulled forward to tomorrow at the same clock time, defaulting to 19:00.
 */
private fun initialProposalDate(sourceDate: Instant?): Instant {
    val now = Instant.now()
    if (sourceDate == null) {
        return LocalDate.now(zone).plusDays(1).atTime(19, 0).atZone(zone).toInstant()
    }
    if (sourceDate > now) return sourceDate

    val time = sourceDate.atZone(zone).toLocalTime()
    return LocalDate.now(zone).plusDays(1).atTime(time.hour, time.minute).atZone(zone).toInstant()
}

private fun clampedFutureDate(date: Instant): Instant {
    if (date > Instant.now()) return date
    val time = date.atZone(zone).toLocalTime()
    return LocalDate.now(zone).plusDays(1).atTime(time.hour, time.minute).atZone(zone).toInstant()
}

/** Port of `struct GameProposalSheet`. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun GameProposalSheet(
    appModel: AppViewModel,
    match: MatchSummary,
    context: ProposalSheetContext = ProposalSheetContext.NEW,
    seedRequest: MatchGameRequest? = null,
    initialCourt: Court? = null,
    onDismiss: () -> Unit,
    onCreated: suspend () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()
    val androidContext = LocalContext.current

    val sourceRequest = remember(match.id, seedRequest, context) {
        if (context == ProposalSheetContext.NEW) seedRequest else (seedRequest ?: match.latestGameRequest)
    }

    var draft by remember {
        val sourceCourt = sourceRequest?.proposedCourt ?: initialCourt
        val courtSports = sourceCourt?.supportedSports.orEmpty()
        val preferredCourtSport = match.otherUser.preferredSports.firstOrNull { courtSports.contains(it) }
            ?: courtSports.firstOrNull()
            ?: sourceCourt?.primarySport
        val preferredSport = sourceRequest?.sport ?: preferredCourtSport
            ?: match.otherUser.preferredSports.firstOrNull() ?: Sport.TENNIS
        val preferredFormat = sourceRequest?.format ?: preferredSport.defaultFormat
        val defaultLevel = match.otherUser.sportLevels[preferredSport.wire] ?: match.otherUser.tennisLevel ?: 5

        mutableStateOf(
            GameProposalDraft(
                proposedCourtId = initialCourt?.id ?: if (context == ProposalSheetContext.NEW) null else sourceCourt?.id,
                proposedDatetime = initialProposalDate(sourceRequest?.proposedDate),
                durationMinutes = sourceRequest?.durationMinutes ?: 90,
                levelRangeMin = maxOf(defaultLevel - 1, 1),
                levelRangeMax = minOf(defaultLevel + 1, 10),
                sport = preferredSport,
                format = preferredFormat,
                comment = sourceRequest?.comment ?: "",
            ),
        )
    }

    var courts by remember { mutableStateOf<List<Court>>(emptyList()) }
    var isLoadingCourts by remember { mutableStateOf(false) }
    var isSubmitting by remember { mutableStateOf(false) }
    var isClubPickerPresented by remember { mutableStateOf(false) }
    var localError by remember { mutableStateOf<String?>(null) }
    var isExactDateTimeSelected by remember { mutableStateOf(sourceRequest != null) }
    var isCelebrationPresented by remember { mutableStateOf(false) }
    var requiresBookingDateTimeChange by remember { mutableStateOf(false) }
    var bookingDateTimeBaseline by remember { mutableStateOf<Instant?>(null) }
    var isDatePickerPresented by remember { mutableStateOf(false) }
    var isTimePickerPresented by remember { mutableStateOf(false) }
    val bookingCallFlow = remember { BookingCallFlow() }

    // The sheet owns the whole screen, like a `.presentationDetents([.large])`.
    DisposableEffect(Unit) {
        appModel.bottomBarDisplayMode = BottomBarDisplayMode.HIDDEN
        onDispose {
            appModel.bottomBarDisplayMode = BottomBarDisplayMode.EXPANDED
            bookingCallFlow.reset()
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> bookingCallFlow.onStopped()
                Lifecycle.Event.ON_RESUME -> bookingCallFlow.onResumed()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val bookingErrorText = L10n.string(
        "Update the date or time to match the actual booking",
        "Измените дату или время на фактически забронированные",
    )

    fun clearBookingDateTimeRequirement() {
        requiresBookingDateTimeChange = false
        bookingDateTimeBaseline = null
        if (localError == bookingErrorText) localError = null
    }

    fun markBookingDateTimeChanged() {
        val baseline = bookingDateTimeBaseline ?: return
        if (!requiresBookingDateTimeChange) return
        val a = draft.proposedDatetime.atZone(zone).withSecond(0).withNano(0)
        val b = baseline.atZone(zone).withSecond(0).withNano(0)
        if (a != b) clearBookingDateTimeRequirement()
    }

    val filteredCourts = remember(courts, draft.sport) {
        val sportCourts = courts.filter { court ->
            court.supportedSports.isEmpty() || court.supportedSports.contains(draft.sport)
        }
        sportCourts.ifEmpty { courts }
    }

    val selectedCourt = filteredCourts.firstOrNull { it.id == draft.proposedCourtId }
        ?: courts.firstOrNull { it.id == draft.proposedCourtId }

    val availableSports = remember(appModel.currentUser, match.otherUser, initialCourt) {
        val courtSports = initialCourt?.supportedSports.orEmpty()
        if (courtSports.isNotEmpty()) {
            courtSports
        } else {
            val mine = appModel.currentUser?.preferredSports.orEmpty()
            (mine + match.otherUser.preferredSports + Sport.entries).distinct()
        }
    }

    LaunchedEffect(Unit) {
        if (courts.isNotEmpty()) return@LaunchedEffect
        isLoadingCourts = true
        runCatching { appModel.repository.fetchCourts() }
            .onSuccess { loaded ->
                courts = loaded
                if (draft.proposedCourtId == null || loaded.none { it.id == draft.proposedCourtId }) {
                    draft = draft.copy(proposedCourtId = initialCourt?.id)
                }
            }
            .onFailure { localError = it.message }
        isLoadingCourts = false
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.White)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(horizontal = 18.dp)
                .padding(top = 18.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            ProposalHeader(title = context.title, user = match.otherUser, onClose = onDismiss)

            ProposalHero(
                context = context,
                otherName = match.otherUser.displayName,
                summaryTitle = draft.proposedDatetime.proposalDateTimeText(),
                summarySubtitle = listOf(
                    draft.sport.title,
                    draft.sport.formatTitle(draft.format).localizedMatchesText,
                    selectedCourt?.name ?: draft.sport.venuePendingTitle.localizedMatchesText,
                ).joinToString(" · "),
                sportTitle = draft.sport.title,
            )

            SportSelector(
                sports = availableSports,
                selected = draft.sport,
                levelOf = { appModel.currentUser?.sportLevels?.get(it.wire) ?: appModel.currentUser?.tennisLevel },
                onSelect = { sport ->
                    haptics.selection()
                    val nextFormat = sport.resolveFormat(draft.format)
                    val keepCourt = draft.proposedCourtId?.takeIf { id ->
                        courts.firstOrNull { it.id == id }
                            ?.let { it.supportedSports.isEmpty() || it.supportedSports.contains(sport) } == true
                    }
                    if (keepCourt == null) bookingCallFlow.reset()
                    draft = draft.copy(sport = sport, format = nextFormat, proposedCourtId = keepCourt)
                },
            )

            DateTimeSection(
                proposedDatetime = draft.proposedDatetime,
                isExactSelected = isExactDateTimeSelected,
                requiresBookingChange = requiresBookingDateTimeChange,
                onPickDay = { offset ->
                    val time = draft.proposedDatetime.atZone(zone).toLocalTime()
                    val target = LocalDate.now(zone).plusDays(offset.toLong())
                        .atTime(time.hour, time.minute).atZone(zone).toInstant()
                    draft = draft.copy(proposedDatetime = clampedFutureDate(target))
                    isExactDateTimeSelected = false
                    markBookingDateTimeChanged()
                    haptics.selection()
                },
                onPickTime = { time ->
                    val parts = time.split(":").mapNotNull(String::toIntOrNull)
                    if (parts.size == 2) {
                        val day = draft.proposedDatetime.atZone(zone).toLocalDate()
                        val target = day.atTime(parts[0], parts[1]).atZone(zone).toInstant()
                        draft = draft.copy(proposedDatetime = clampedFutureDate(target))
                        isExactDateTimeSelected = false
                        markBookingDateTimeChanged()
                        haptics.selection()
                    }
                },
                onOpenExactDate = { isDatePickerPresented = true },
                onOpenExactTime = { isTimePickerPresented = true },
            )

            CourtSection(
                sport = draft.sport,
                isLoading = isLoadingCourts,
                courts = filteredCourts,
                selectedCourt = selectedCourt,
                onOpenPicker = {
                    haptics.selection()
                    isClubPickerPresented = true
                },
                onCall = { court ->
                    val uri = court.dialUri ?: return@CourtSection
                    val intent = Intent(Intent.ACTION_DIAL, uri.toUri())
                    val accepted = runCatching { androidContext.startActivity(intent); true }.getOrDefault(false)
                    bookingCallFlow.start(scope, accepted)
                },
            )

            LevelSection(
                min = draft.levelRangeMin ?: 1,
                max = draft.levelRangeMax ?: 10,
                onMin = { draft = draft.copy(levelRangeMin = minOf(it, draft.levelRangeMax ?: 10)) },
                onMax = { draft = draft.copy(levelRangeMax = maxOf(it, draft.levelRangeMin ?: 1)) },
                haptics = { haptics.selection() },
            )

            CommentSection(value = draft.comment, onChange = { draft = draft.copy(comment = it) })

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                localError?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = AppText.subheadlineSemibold, color = Color.Red, modifier = Modifier.fillMaxWidth())
                }

                Box {
                    PrimaryActionButton(
                        title = context.submitTitle,
                        tint = AppTheme.ink,
                        enabled = !isSubmitting && !requiresBookingDateTimeChange,
                        onClick = {
                            scope.launch {
                                if (requiresBookingDateTimeChange) {
                                    localError = bookingErrorText
                                    return@launch
                                }
                                if (draft.proposedDatetime <= Instant.now()) {
                                    localError = L10n.string(
                                        "Choose a future date and time",
                                        "Выбери будущую дату и время",
                                    )
                                    draft = draft.copy(proposedDatetime = clampedFutureDate(draft.proposedDatetime))
                                    return@launch
                                }

                                isSubmitting = true
                                localError = null
                                val requestId = seedRequest?.id
                                runCatching {
                                    if (context != ProposalSheetContext.NEW && requestId != null) {
                                        appModel.repository.updateGameRequest(requestId, draft)
                                        haptics.successCelebration()
                                        isCelebrationPresented = true
                                        delay(1700)
                                    } else {
                                        appModel.repository.createGameRequest(match.id, draft)
                                        haptics.success()
                                    }
                                }.onSuccess {
                                    onCreated()
                                    onDismiss()
                                }.onFailure { localError = it.message }
                                isSubmitting = false
                            }
                        },
                    )

                    if (isSubmitting) {
                        Box(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                        }
                    }
                }

                SecondaryActionButton(
                    title = L10n.string("Cancel", "Отмена"),
                    onClick = onDismiss,
                    tint = AppTheme.ink,
                )
            }
        }

        if (isCelebrationPresented) {
            SuccessCelebrationOverlay(
                title = L10n.string("Game updated", "Игра изменена"),
                subtitle = L10n.string("Waiting for your partner's confirmation", "Ждем подтверждения партнера"),
                icon = "✅",
            )
        }
    }

    if (isClubPickerPresented) {
        SearchClubPickerSheet(
            sport = draft.sport,
            courts = filteredCourts,
            selectedCourtId = draft.proposedCourtId,
            selectsImmediately = false,
            allowsNoCourt = true,
            onDismiss = { isClubPickerPresented = false },
            onSelect = { court ->
                bookingCallFlow.reset()
                draft = draft.copy(proposedCourtId = court?.id)
                if (court != null) haptics.selection()
            },
        )
    }

    if (isDatePickerPresented) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = draft.proposedDatetime.toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { isDatePickerPresented = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        val picked = Instant.ofEpochMilli(millis).atZone(ZoneId.of("UTC")).toLocalDate()
                        val time = draft.proposedDatetime.atZone(zone).toLocalTime()
                        draft = draft.copy(
                            proposedDatetime = clampedFutureDate(
                                LocalDateTime.of(picked, time).atZone(zone).toInstant(),
                            ),
                        )
                        isExactDateTimeSelected = true
                        markBookingDateTimeChanged()
                    }
                    isDatePickerPresented = false
                }) { Text("OK", color = AppTheme.court) }
            },
            dismissButton = {
                TextButton(onClick = { isDatePickerPresented = false }) {
                    Text(L10n.string("Cancel", "Отмена"), color = AppTheme.ink)
                }
            },
        ) {
            DatePicker(state = state)
        }
    }

    if (isTimePickerPresented) {
        val current = draft.proposedDatetime.atZone(zone).toLocalTime()
        val state = rememberTimePickerState(initialHour = current.hour, initialMinute = current.minute, is24Hour = true)
        AlertDialog(
            onDismissRequest = { isTimePickerPresented = false },
            containerColor = Color.White,
            title = { Text(L10n.string("Exact date and time", "Точная дата и время"), color = AppTheme.ink) },
            text = { TimePicker(state = state) },
            confirmButton = {
                TextButton(onClick = {
                    val day = draft.proposedDatetime.atZone(zone).toLocalDate()
                    draft = draft.copy(
                        proposedDatetime = clampedFutureDate(
                            LocalDateTime.of(day, LocalTime.of(state.hour, state.minute)).atZone(zone).toInstant(),
                        ),
                    )
                    isExactDateTimeSelected = true
                    markBookingDateTimeChanged()
                    isTimePickerPresented = false
                }) { Text("OK", color = AppTheme.court) }
            },
            dismissButton = {
                TextButton(onClick = { isTimePickerPresented = false }) {
                    Text(L10n.string("Cancel", "Отмена"), color = AppTheme.ink)
                }
            },
        )
    }

    if (bookingCallFlow.isResultPresented) {
        AlertDialog(
            onDismissRequest = { bookingCallFlow.reset() },
            containerColor = Color.White,
            title = { Text(L10n.string("Were you able to book?", "Удалось забронировать?"), color = AppTheme.ink) },
            text = {
                Text(
                    L10n.string(
                        "Confirm the booking or update the proposal's date and time.",
                        "Подтвердите бронь или измените дату и время предложения.",
                    ),
                    color = AppTheme.ink.copy(alpha = 0.7f),
                )
            },
            confirmButton = {
                Column {
                    TextButton(onClick = {
                        bookingCallFlow.reset()
                        clearBookingDateTimeRequirement()
                    }) { Text(L10n.string("Yes, the time matches", "Да, время совпало"), color = AppTheme.court) }

                    TextButton(onClick = {
                        bookingCallFlow.reset()
                        bookingDateTimeBaseline = draft.proposedDatetime
                        requiresBookingDateTimeChange = true
                        localError = bookingErrorText
                    }) {
                        Text(
                            L10n.string("Booked a different time", "Забронировал на другое время"),
                            color = AppTheme.ink,
                        )
                    }

                    TextButton(onClick = {
                        bookingCallFlow.reset()
                        clearBookingDateTimeRequirement()
                    }) { Text(L10n.string("I didn't book", "Не забронировал"), color = AppTheme.ink) }
                }
            },
            dismissButton = {
                TextButton(onClick = { bookingCallFlow.reset() }) {
                    Text(L10n.string("Cancel", "Отмена"), color = AppTheme.ink.copy(alpha = 0.6f))
                }
            },
        )
    }
}

private fun Instant.proposalDateTimeText(): String = toServerISOString().formattedDateTime()

@Composable
private fun ProposalHeader(title: String, user: DiscoverUser, onClose: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.04f))
                .clickable(onClick = onClose),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Close, null, tint = AppTheme.ink, modifier = Modifier.size(18.dp))
        }

        Text(
            title,
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
            textAlign = TextAlign.Center,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )

        RemoteAvatarView(name = user.displayName, path = user.avatarUrl, size = 44.dp)
    }
}

@Composable
private fun ProposalHero(
    context: ProposalSheetContext,
    otherName: String,
    summaryTitle: String,
    summarySubtitle: String,
    sportTitle: String,
) {
    val shape = continuousShape(28.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppTheme.mint.copy(alpha = 0.72f))
            .border(1.dp, AppTheme.court.copy(alpha = 0.12f), shape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier.size(54.dp).clip(CircleShape).background(AppTheme.court.copy(alpha = 0.13f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.EditCalendar, null, tint = AppTheme.court, modifier = Modifier.size(22.dp))
            }

            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(
                    L10n.string("${context.subtitlePrefix} with $otherName", "${context.subtitlePrefix} с $otherName"),
                    fontSize = 23.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                )
                Text(
                    L10n.string(
                        "Choose a sport, time, and venue. The other player will see the proposal in Matches and can confirm it.",
                        "Выбери спорт, время и клуб. Второй игрок увидит предложение в мэтче и сможет подтвердить игру.",
                    ),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppTheme.ink.copy(alpha = 0.56f),
                    lineHeight = 20.sp,
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ProposalSummaryPill(Icons.Filled.Schedule, summaryTitle)
            ProposalSummaryPill(Icons.Filled.SportsTennis, sportTitle)
        }

        Text(
            summarySubtitle,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppTheme.court,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ProposalSummaryPill(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String) {
    Row(
        modifier = Modifier
            .height(32.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.74f))
            .padding(horizontal = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = AppTheme.ink.copy(alpha = 0.78f), modifier = Modifier.size(14.dp))
        Text(
            title,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppTheme.ink.copy(alpha = 0.78f),
            maxLines = 1,
        )
    }
}

@Composable
private fun SportSelector(
    sports: List<Sport>,
    selected: Sport,
    levelOf: (Sport) -> Int?,
    onSelect: (Sport) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(L10n.string("What are you playing?", "Что играем?"), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = AppTheme.ink)
            Spacer(Modifier.weight(1f))
            Text(L10n.string("Sport", "Вид спорта"), style = AppText.subheadline, color = AppTheme.court)
        }

        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            sports.forEach { sport ->
                val isSelected = selected == sport
                val level = levelOf(sport)
                val cardShape = continuousShape(26.dp)
                Column(
                    modifier = Modifier
                        .width(98.dp)
                        .height(126.dp)
                        .appShadow(
                            AppTheme.ink.copy(alpha = if (isSelected) 0.08f else 0.03f),
                            radius = if (isSelected) 16.dp else 10.dp,
                            offsetY = 8.dp,
                            shape = cardShape,
                        )
                        .clip(cardShape)
                        .background(Color.White)
                        .border(
                            if (isSelected) 2.dp else 1.dp,
                            if (isSelected) AppTheme.court else Color.Black.copy(alpha = 0.08f),
                            cardShape,
                        )
                        .clickable { onSelect(sport) }
                        .padding(vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(52.dp)
                            .clip(continuousShape(20.dp))
                            .background(if (isSelected) AppTheme.mint else Color.White),
                        contentAlignment = Alignment.Center,
                    ) {
                        SportIconView(
                            sport = sport,
                            color = if (isSelected) AppTheme.court else AppTheme.ink.copy(alpha = 0.92f),
                            size = 30.dp,
                        )
                    }

                    Text(
                        sport.title,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = AppTheme.ink,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        modifier = Modifier.width(86.dp),
                    )

                    level?.let {
                        Text(
                            L10n.string("lvl $it", "ур. $it"),
                            style = AppText.caption2Semibold,
                            color = if (isSelected) AppTheme.court else AppTheme.ink.copy(alpha = 0.54f),
                        )
                    }
                }
            }
        }
    }
}

private val proposalQuickTimes: List<String> =
    generateSequence(8 * 60) { it + 30 }.takeWhile { it <= 22 * 60 + 30 }
        .map { "%02d:%02d".format(it / 60, it % 60) }
        .toList()

@Composable
private fun DateTimeSection(
    proposedDatetime: Instant,
    isExactSelected: Boolean,
    requiresBookingChange: Boolean,
    onPickDay: (Int) -> Unit,
    onPickTime: (String) -> Unit,
    onOpenExactDate: () -> Unit,
    onOpenExactTime: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(L10n.string("When are you playing?", "Когда играем?"), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = AppTheme.ink)

        if (requiresBookingChange) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.ErrorOutline, null, tint = Color(0xFFFF9800), modifier = Modifier.size(16.dp))
                Text(
                    L10n.string("Enter the actual booking date or time", "Укажите дату или время фактической брони"),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color(0xFFFF9800),
                )
            }
        }

        val selectedDay = proposedDatetime.atZone(zone).toLocalDate()
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            listOf(
                L10n.string("Today", "Сегодня") to 0,
                L10n.string("Tomorrow", "Завтра") to 1,
                L10n.string("Day after tomorrow", "Послезавтра") to 2,
            ).forEach { (title, offset) ->
                val target = LocalDate.now(zone).plusDays(offset.toLong())
                val selected = !isExactSelected && selectedDay == target
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .height(58.dp)
                        .clip(continuousShape(20.dp))
                        .background(if (selected) AppTheme.court else Color.Black.copy(alpha = 0.04f))
                        .clickable { onPickDay(offset) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        title,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (selected) Color.White else AppTheme.ink.copy(alpha = 0.82f),
                        maxLines = 1,
                    )
                    Text(
                        target.atStartOfDay(zone).toInstant().formattedDayMonth(),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = (if (selected) Color.White else AppTheme.ink.copy(alpha = 0.82f)).copy(alpha = 0.72f),
                    )
                }
            }
        }

        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            proposalQuickTimes.forEach { time ->
                val selected = !isExactSelected && proposedDatetime.formattedHourMinute() == time
                val shape = continuousShape(16.dp)
                Box(
                    modifier = Modifier
                        .width(84.dp)
                        .height(50.dp)
                        .clip(shape)
                        .background(if (selected) AppTheme.court else Color.White)
                        .border(1.dp, if (selected) AppTheme.court else Color.Black.copy(alpha = 0.07f), shape)
                        .clickable { onPickTime(time) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        time,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (selected) Color.White else AppTheme.ink.copy(alpha = 0.82f),
                    )
                }
            }
        }

        // SwiftUI's compact DatePicker is one control for both halves; Compose
        // has separate date and time dialogs, so the row exposes both.
        val shape = continuousShape(20.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(if (isExactSelected) AppTheme.mint.copy(alpha = 0.86f) else Color.White)
                .border(
                    1.dp,
                    if (isExactSelected) AppTheme.court.copy(alpha = 0.58f) else Color.Black.copy(alpha = 0.06f),
                    shape,
                )
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                L10n.string("Exact date and time", "Точная дата и время"),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (isExactSelected) AppTheme.court else AppTheme.ink,
                modifier = Modifier.weight(1f),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DateTimeChip(proposedDatetime.formattedDayMonth(), onOpenExactDate)
                DateTimeChip(proposedDatetime.formattedHourMinute(), onOpenExactTime)
            }
        }
    }
}

@Composable
private fun DateTimeChip(text: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(AppTheme.court.copy(alpha = 0.12f))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = AppTheme.court)
    }
}

@Composable
private fun CourtSection(
    sport: Sport,
    isLoading: Boolean,
    courts: List<Court>,
    selectedCourt: Court?,
    onOpenPicker: () -> Unit,
    onCall: (Court) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(sport.venueFieldTitle, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = AppTheme.ink)
            Spacer(Modifier.weight(1f))
            if (courts.isNotEmpty()) {
                Row(
                    modifier = Modifier.clickable(onClick = onOpenPicker),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Search, null, tint = AppTheme.court, modifier = Modifier.size(16.dp))
                    Text(L10n.string("Choose on map", "Выбрать на карте"), style = AppText.subheadlineSemibold, color = AppTheme.court)
                }
            }
        }

        when {
            isLoading -> InfoPanel {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(color = AppTheme.court, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                    Text(L10n.string("Loading venues", "Загружаем места"), style = AppText.subheadline, color = AppTheme.ink.copy(alpha = 0.58f))
                }
            }

            courts.isEmpty() -> InfoPanel {
                Text(
                    L10n.string("No venues available for this sport", "Нет доступных мест для этого спорта"),
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.58f),
                )
            }

            else -> SelectedCourtCard(selectedCourt, onOpenPicker, onCall)
        }
    }
}

@Composable
private fun InfoPanel(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(24.dp))
            .background(Color.Black.copy(alpha = 0.04f))
            .padding(18.dp),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

@Composable
private fun SelectedCourtCard(court: Court?, onOpenPicker: () -> Unit, onCall: (Court) -> Unit) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenPicker),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier.size(46.dp).clip(CircleShape).background(AppTheme.mint),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Place, null, tint = AppTheme.court, modifier = Modifier.size(19.dp))
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    court?.name ?: L10n.string("Choose a venue", "Выбери клуб"),
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    courtSubtitle(court),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppTheme.ink.copy(alpha = 0.55f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Icon(
                    if (court == null) Icons.Filled.ChevronRight else Icons.Filled.CheckCircle,
                    null,
                    tint = if (court == null) AppTheme.ink.copy(alpha = 0.24f) else AppTheme.court,
                    modifier = Modifier.size(22.dp),
                )
                Text(
                    if (court == null) L10n.string("Choose", "Выбрать") else L10n.string("Change", "Изменить"),
                    style = AppText.captionBold,
                    color = AppTheme.court,
                )
            }
        }

        if (court?.dialUri != null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .clip(continuousShape(16.dp))
                    .background(AppTheme.court)
                    .clickable { onCall(court) },
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Call, null, tint = Color.White, modifier = Modifier.size(16.dp))
                Text(
                    L10n.string("Call and book", "Позвонить и забронировать"),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }
    }
}

private fun courtSubtitle(court: Court?): String {
    if (court == null) {
        return L10n.string("You can confirm the venue later", "Место можно уточнить позже")
    }
    val subtitle = listOfNotNull(court.metroDisplayName, localizedDistrictName(court.district), court.distanceLabel)
        .filter { it.isNotEmpty() }
        .joinToString(" · ")
    return subtitle.ifEmpty { court.address }
}

@Composable
private fun LevelSection(
    min: Int,
    max: Int,
    onMin: (Int) -> Unit,
    onMax: (Int) -> Unit,
    haptics: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
        LevelCard(L10n.string("Min. level", "Мин. уровень"), min, { onMin(it) }, haptics, Modifier.weight(1f))
        LevelCard(L10n.string("Max. level", "Макс. уровень"), max, { onMax(it) }, haptics, Modifier.weight(1f))
    }
}

@Composable
private fun LevelCard(
    title: String,
    value: Int,
    onValue: (Int) -> Unit,
    haptics: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = continuousShape(28.dp)
    Column(
        modifier = modifier
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = AppTheme.ink)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(continuousShape(18.dp))
                .background(Color.Black.copy(alpha = 0.04f)),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LevelAdjustButton(Icons.Filled.Remove, value <= 1) { haptics(); onValue(value - 1) }
            Text(
                "$value",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f),
            )
            LevelAdjustButton(Icons.Filled.Add, value >= 10) { haptics(); onValue(value + 1) }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val filled = ceil(value / 2.0).toInt()
            (1..5).forEach { index ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(8.dp)
                        .clip(CircleShape)
                        .background(if (index <= filled) AppTheme.court else Color.Black.copy(alpha = 0.08f)),
                )
            }
        }
    }
}

@Composable
private fun LevelAdjustButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    disabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(38.dp)
            .clip(CircleShape)
            .background(Color.White)
            .clickable(enabled = !disabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            null,
            tint = if (disabled) AppTheme.ink.copy(alpha = 0.25f) else AppTheme.ink,
            modifier = Modifier.size(15.dp),
        )
    }
}

@Composable
private fun CommentSection(value: String, onChange: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(24.dp))
            .background(Color.Black.copy(alpha = 0.03f))
            .padding(18.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            Icons.Filled.EditCalendar,
            null,
            tint = AppTheme.ink.copy(alpha = 0.78f),
            modifier = Modifier.size(20.dp).padding(top = 4.dp),
        )

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                L10n.string("Comment (optional)", "Комментарий (необязательно)"),
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.56f),
            )
            Box {
                if (value.isEmpty()) {
                    Text(
                        L10n.string("For example: anytime after 7 PM", "Например: удобно после 19:00"),
                        style = AppText.subheadline,
                        color = AppTheme.ink.copy(alpha = 0.38f),
                    )
                }
                BasicTextField(
                    value = value,
                    onValueChange = onChange,
                    textStyle = AppText.subheadline.copy(color = AppTheme.ink),
                    cursorBrush = SolidColor(AppTheme.court),
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}
