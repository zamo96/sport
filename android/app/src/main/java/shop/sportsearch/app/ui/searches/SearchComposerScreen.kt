package shop.sportsearch.app.ui.searches

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.PersonAddAlt
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import kotlin.math.ceil
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.core.RunningRoutePoint
import shop.sportsearch.app.core.routeDefaultTitle
import shop.sportsearch.app.core.routeFollowsRoads
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.SuccessCelebrationOverlay
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.maps.RunningRoutePreviewMapView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `private enum HotSearchStep`. */
private enum class HotSearchStep {
    WHEN, WHO, LOCATION, CONFIRM;

    val badgeTitle: String
        get() = when (this) {
            WHEN -> L10n.string("1. When", "1. Когда")
            WHO -> L10n.string("2. Who", "2. Кого")
            LOCATION -> L10n.string("3. Where", "3. Где")
            CONFIRM -> L10n.string("4. Review", "4. Подтверждение")
        }
}

/**
 * Port of `struct SearchComposerView` in ios/TennisSearchIOS/Views/SearchesView.swift.
 *
 * The composer only ever creates urgent searches - `SearchType.userVisibleCases`
 * is `[hot]` on both clients - so the four steps are When / Who / Where / Review.
 */
@Composable
fun SearchComposerScreen(
    appModel: AppViewModel,
    initialSearch: GameSearch? = null,
    initialCourt: Court? = null,
    initialSport: Sport? = null,
    initialHotWindow: HotWindow? = null,
    initialHotStartTime: String? = null,
    onCreate: (GameSearch) -> Unit,
    onDismiss: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()

    val requestedSport = initialSearch?.sport ?: initialSport ?: initialCourt?.supportedSports?.firstOrNull() ?: Sport.TENNIS
    val initialCourtSports = initialCourt?.supportedSports.orEmpty()
    val resolvedSport = if (initialCourtSports.isEmpty() || initialCourtSports.contains(requestedSport)) {
        requestedSport
    } else {
        initialCourtSports.first()
    }

    var selectedSport by remember { mutableStateOf(resolvedSport) }
    var courts by remember { mutableStateOf<List<Court>>(emptyList()) }
    var selectedCourt by remember { mutableStateOf(initialSearch?.preferredCourt ?: initialCourt) }
    var customHotDate by remember { mutableStateOf<LocalDate?>(null) }
    var hotStep by remember { mutableStateOf(HotSearchStep.WHEN) }
    var isSaving by remember { mutableStateOf(false) }
    var showCelebration by remember { mutableStateOf(false) }
    var isClubPickerOpen by remember { mutableStateOf(false) }
    var isRoutePickerOpen by remember { mutableStateOf(false) }

    var draft by remember {
        mutableStateOf(
            SearchDraft(
                inviteSlug = null,
                preferredCourtId = initialCourt?.id,
                preferredDistricts = listOfNotNull(initialCourt?.district),
                preferredDays = listOf("wednesday", "saturday"),
                preferredTimeRanges = listOf("evening"),
                searchType = SearchType.HOT,
                hotWindow = initialHotWindow ?: HotWindow.TODAY,
                hotStartTime = initialHotStartTime ?: "19:00",
                durationMinutes = resolvedSport.defaultDurationMinutes,
                hasCourtBooked = false,
                sport = resolvedSport,
                selfLevel = null,
                selfLevelUnknown = true,
                desiredLevelMin = 4,
                desiredLevelMax = 6,
                format = resolvedSport.defaultFormat,
                playersNeeded = resolvedSport.defaultPlayersNeeded(resolvedSport.defaultFormat),
                comment = "",
            ).let { base ->
                initialSearch?.let { search ->
                    base.copy(
                        preferredCourtId = search.preferredCourt?.id,
                        preferredDistricts = search.preferredDistricts,
                        preferredDays = search.preferredDays,
                        preferredTimeRanges = search.preferredTimeRanges,
                        hotWindow = search.hotWindow,
                        hotStartTime = parseServerInstant(search.hotStartsAt)?.formattedHourMinute(),
                        hotStartsAt = search.hotStartsAt,
                        durationMinutes = search.durationMinutes,
                        hasCourtBooked = search.hasCourtBooked,
                        selfLevel = search.selfLevel,
                        selfLevelUnknown = search.selfLevelUnknown ?: false,
                        desiredLevelMin = search.desiredLevelMin ?: 1,
                        desiredLevelMax = search.desiredLevelMax ?: 10,
                        format = search.format,
                        playersNeeded = search.playersNeeded,
                        comment = search.comment.orEmpty(),
                    )
                } ?: base
            },
        )
    }

    // The SwiftUI composer is a full-screen `.sheet`, so the tab bar is not on
    // screen while it is open. Hiding the bar reproduces that and stops the tab
    // strip from eating the bottom of the flow.
    DisposableEffect(Unit) {
        appModel.bottomBarDisplayMode = BottomBarDisplayMode.HIDDEN
        onDispose { appModel.bottomBarDisplayMode = BottomBarDisplayMode.EXPANDED }
    }

    LaunchedEffect(Unit) {
        if (initialSearch == null && draft.inviteSlug == null) {
            draft = draft.copy(inviteSlug = UUID.randomUUID().toString().lowercase())
        }
        courts = runCatching { appModel.repository.fetchCourts() }.getOrElse {
            appModel.present(it)
            emptyList()
        }
    }

    // MARK: derived values

    val profileSportLevel = appModel.currentUser?.sportLevels?.get(selectedSport.wire)
        ?: appModel.currentUser?.tennisLevel
    val currentSportLevel = draft.selfLevel ?: profileSportLevel
    val editableSportLevel = currentSportLevel ?: 5

    val isCustomHotDateSelected = draft.hotWindow == null
    val resolvedHotDate = when {
        isCustomHotDateSelected && customHotDate != null -> customHotDate!!
        else -> LocalDate.now().plusDays(
            when (draft.hotWindow ?: HotWindow.TODAY) {
                HotWindow.TODAY -> 0L
                HotWindow.TOMORROW -> 1L
                HotWindow.DAY_AFTER_TOMORROW -> 2L
            },
        )
    }

    val sportCourts = courts.filter { court ->
        court.supportedSports.isEmpty() || court.supportedSports.contains(selectedSport)
    }

    val availableSports = remember(appModel.currentUser?.id, selectedCourt?.id) {
        val preferred = appModel.currentUser?.preferredSports.orEmpty()
        val courtSports = selectedCourt?.supportedSports?.takeIf { it.isNotEmpty() }
        var ordered = preferred + Sport.defaultAuthSports + Sport.entries
        if (courtSports != null) {
            ordered = ordered.filter { courtSports.contains(it) } + courtSports
        }
        ordered.distinct()
    }

    val canSubmit = !draft.hotStartTime.isNullOrBlank()
    val canAdvance = if (hotStep == HotSearchStep.WHEN) canSubmit else true

    fun goTo(step: HotSearchStep) {
        hotStep = step
    }

    suspend fun saveSearch() {
        if (isSaving) return
        isSaving = true
        try {
            var payload = draft.copy(
                searchType = SearchType.HOT,
                sport = selectedSport,
                preferredCourtId = selectedCourt?.id,
                inviteSlug = draft.inviteSlug ?: initialSearch?.inviteSlug ?: initialSearch?.id
                    ?: UUID.randomUUID().toString().lowercase(),
            )

            selectedCourt?.district?.let { district ->
                payload = payload.copy(
                    preferredDistricts = listOf(district) + payload.preferredDistricts.filter { it != district },
                )
            }
            if (payload.preferredCourtId != null) {
                payload = payload.copy(customVenueTitle = null, customVenueAddress = null)
            }
            payload = if (!payload.sport.isRouteSport) {
                payload.copy(runningRoute = null, runningRoutePoints = null)
            } else {
                payload.copy(
                    preferredCourtId = null,
                    customVenueTitle = null,
                    customVenueAddress = null,
                    hasCourtBooked = false,
                    preferredDistricts = emptyList(),
                    runningRoutePoints = payload.runningRoutePoints?.takeIf { it.isNotEmpty() },
                )
            }

            val level = currentSportLevel
            payload = payload.copy(
                preferredDistricts = payload.preferredDistricts.distinct(),
                selfLevel = level,
                selfLevelUnknown = level == null,
                desiredLevelMin = maxOf((level ?: 5) - 1, 1),
                desiredLevelMax = minOf((level ?: 5) + 1, 10),
                preferredDays = emptyList(),
                preferredTimeRanges = listOf(timeRangeFromHotStartTime(payload.hotStartTime ?: "19:00")),
                hotStartsAt = hotStartsAtPayloadValue(isCustomHotDateSelected, resolvedHotDate, payload.hotStartTime),
            )
            if (payload.hotStartsAt != null) {
                payload = payload.copy(hotWindow = null)
            }

            val created = if (initialSearch != null) {
                appModel.repository.updateSearch(initialSearch.id, payload)
            } else {
                appModel.repository.createSearch(payload)
            }

            if (initialSearch == null) {
                haptics.successCelebration()
                showCelebration = true
                delay(1700)
            }
            appModel.refreshActivitySummary()
            onCreate(created)
            onDismiss()
        } catch (error: Throwable) {
            appModel.present(error)
        } finally {
            isSaving = false
        }
    }

    if (isRoutePickerOpen) {
        RunningRoutePickerSheet(
            sport = selectedSport,
            points = draft.runningRoutePoints.orEmpty(),
            routeTitle = draft.runningRoute.orEmpty(),
            onDismiss = { isRoutePickerOpen = false },
            onDone = { points, title ->
                draft = draft.copy(runningRoutePoints = points, runningRoute = title)
                isRoutePickerOpen = false
            },
        )
        return
    }

    if (isClubPickerOpen) {
        SearchClubPickerSheet(
            sport = selectedSport,
            courts = sportCourts,
            selectedCourtId = selectedCourt?.id,
            selectsImmediately = false,
            repository = appModel.repository,
            suggestionCity = appModel.currentUser?.city ?: appModel.guestDraft.city,
            onSelectCustomAddress = { address ->
                // Port of `selectCustomVenueAddress(_:)`.
                val normalized = address.trim()
                if (normalized.isNotEmpty()) {
                    selectedCourt = null
                    draft = draft.copy(
                        preferredCourtId = null,
                        customVenueTitle = null,
                        customVenueAddress = normalized,
                        hasCourtBooked = false,
                    )
                }
                isClubPickerOpen = false
            },
            onSelect = { court ->
                selectedCourt = court
                draft = draft.copy(
                    preferredCourtId = court?.id,
                    preferredDistricts = court?.district?.let { district ->
                        listOf(district) + draft.preferredDistricts.filter { it != district }
                    } ?: draft.preferredDistricts,
                )
                isClubPickerOpen = false
            },
            onDismiss = { isClubPickerOpen = false },
        )
        return
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.White)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 18.dp)
                .padding(top = 18.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            SheetHeader(
                title = if (initialSearch == null) {
                    L10n.string("Find partners", "Найти партнёров")
                } else {
                    L10n.string("Edit search", "Изменить поиск")
                },
                onClose = onDismiss,
            )

            UrgentProgressHeader(step = hotStep)

            when (hotStep) {
                HotSearchStep.WHEN -> WhenStep(
                    draft = draft,
                    selectedSport = selectedSport,
                    resolvedHotDate = resolvedHotDate,
                    isCustomHotDateSelected = isCustomHotDateSelected,
                    customHotDate = customHotDate,
                    onWindowSelected = { window ->
                        draft = draft.copy(
                            hotWindow = window,
                            hotStartsAt = null,
                            hotStartTime = preferredHotStartTime(hotDate(window)),
                        )
                        customHotDate = null
                    },
                    onCustomDateSelected = { date ->
                        customHotDate = date
                        draft = draft.copy(
                            hotWindow = null,
                            hotStartsAt = null,
                            hotStartTime = preferredHotStartTime(date),
                        )
                    },
                    onTimeSelected = { draft = draft.copy(hotStartTime = it) },
                    onDurationChanged = { draft = draft.copy(durationMinutes = it) },
                )

                HotSearchStep.WHO -> Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    SportRailSection(
                        sports = availableSports,
                        selected = selectedSport,
                        onSelect = { sport ->
                            haptics.selection()
                            selectedSport = sport
                            val format = sport.defaultFormat
                            draft = draft.copy(
                                sport = sport,
                                format = format,
                                playersNeeded = sport.defaultPlayersNeeded(format),
                                durationMinutes = sport.defaultDurationMinutes,
                            )
                        },
                    )
                    CompactStatsSection(
                        appModel = appModel,
                        playersNeeded = draft.playersNeeded,
                        maxPlayers = selectedSport.maxPlayersNeeded,
                        level = editableSportLevel,
                        desiredMin = draft.desiredLevelMin,
                        desiredMax = draft.desiredLevelMax,
                        onPlayersChange = { draft = draft.copy(playersNeeded = it) },
                        onLevelChange = { draft = draft.copy(selfLevel = it, selfLevelUnknown = false) },
                    )
                    CommentSection(
                        comment = draft.comment,
                        onCommentChange = { draft = draft.copy(comment = it) },
                    )
                }

                HotSearchStep.LOCATION -> LocationStep(
                    sport = selectedSport,
                    selectedCourt = selectedCourt,
                    hasCourtBooked = draft.hasCourtBooked,
                    districts = draft.preferredDistricts,
                    routePoints = draft.runningRoutePoints.orEmpty(),
                    routeTitle = draft.runningRoute,
                    onOpenClubPicker = { isClubPickerOpen = true },
                    onOpenRoutePicker = { isRoutePickerOpen = true },
                    onClearCourt = {
                        selectedCourt = null
                        draft = draft.copy(preferredCourtId = null)
                    },
                    onToggleBooked = { draft = draft.copy(hasCourtBooked = it) },
                )

                HotSearchStep.CONFIRM -> ConfirmStep(
                    dateTitle = hotDateTitle(resolvedHotDate),
                    startTime = draft.hotStartTime ?: "19:00",
                    sport = selectedSport,
                    playersNeeded = draft.playersNeeded,
                    level = editableSportLevel,
                    locationTitle = locationTitle(selectedSport, selectedCourt, draft),
                    inviteUrl = AppConfig.searchInviteUrl(
                        draft.inviteSlug ?: initialSearch?.id.orEmpty(),
                    ),
                )
            }

            StepActions(
                step = hotStep,
                canAdvance = canAdvance && !isSaving,
                onBack = {
                    goTo(HotSearchStep.entries[(hotStep.ordinal - 1).coerceAtLeast(0)])
                },
                onPrimary = {
                    haptics.selection()
                    if (hotStep == HotSearchStep.CONFIRM) {
                        scope.launch { saveSearch() }
                    } else {
                        goTo(HotSearchStep.entries[(hotStep.ordinal + 1).coerceAtMost(HotSearchStep.CONFIRM.ordinal)])
                    }
                },
            )
        }

        if (showCelebration) {
            SuccessCelebrationOverlay(
                title = L10n.string("Urgent search published", "Срочный поиск опубликован"),
                subtitle = L10n.string("Players will see it in the feed", "Игроки увидят его в ленте"),
                icon = "🚀",
            )
        }
    }
}

// MARK: - Header and progress

/** Port of `urgentSearchProgressHeader`. */
@Composable
private fun UrgentProgressHeader(step: HotSearchStep) {
    val shape = continuousShape(22.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppTheme.mint.copy(alpha = 0.7f))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("🚀", fontSize = 22.sp)
            Text(
                L10n.string("Urgent search", "Срочный поиск"),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
                modifier = Modifier.weight(1f),
            )
            Text(
                step.badgeTitle,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppTheme.court,
                modifier = Modifier
                    .background(AppTheme.mint, RoundedCornerShape(percent = 50))
                    .padding(horizontal = 10.dp, vertical = 7.dp),
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            HotSearchStep.entries.forEach { entry ->
                Box(
                    Modifier
                        .weight(1f)
                        .height(4.dp)
                        .background(
                            if (entry.ordinal <= step.ordinal) AppTheme.court else Color.Black.copy(alpha = 0.08f),
                            RoundedCornerShape(percent = 50),
                        ),
                )
            }
        }
    }
}

/** Port of `hotStepActions`. */
@Composable
private fun StepActions(
    step: HotSearchStep,
    canAdvance: Boolean,
    onBack: () -> Unit,
    onPrimary: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        if (step != HotSearchStep.WHEN) {
            Box(modifier = Modifier.weight(1f)) {
                SecondaryActionButton(
                    title = L10n.string("Back", "Назад"),
                    onClick = onBack,
                    tint = AppTheme.ink,
                )
            }
        }

        Box(modifier = Modifier.weight(1f)) {
            PrimaryActionButton(
                title = if (step == HotSearchStep.CONFIRM) {
                    "🚀 " + L10n.string("Publish urgent search", "Опубликовать срочно")
                } else {
                    L10n.string("Continue", "Продолжить")
                },
                onClick = onPrimary,
                tint = AppTheme.ink,
                enabled = canAdvance,
            )
        }
    }
}

// MARK: - Step 1: when

/** Port of `hotSettingsSection`. */
@Composable
private fun WhenStep(
    draft: SearchDraft,
    selectedSport: Sport,
    resolvedHotDate: LocalDate,
    isCustomHotDateSelected: Boolean,
    customHotDate: LocalDate?,
    onWindowSelected: (HotWindow) -> Unit,
    onCustomDateSelected: (LocalDate) -> Unit,
    onTimeSelected: (String) -> Unit,
    onDurationChanged: (Int) -> Unit,
) {
    var isCalendarExpanded by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                L10n.string("When would you like to play?", "Когда хотите сыграть?"),
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
            )
            Text(
                L10n.string("Choose a day and a convenient time", "Выберите день и удобное время"),
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.56f),
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            HotWindow.entries.forEach { window ->
                HotWindowRow(
                    icon = when (window) {
                        HotWindow.TODAY -> Icons.Filled.Schedule          // calendar.badge.clock
                        HotWindow.TOMORROW -> Icons.Filled.WbSunny        // sun.max
                        HotWindow.DAY_AFTER_TOMORROW -> Icons.Filled.CalendarMonth
                    },
                    title = window.title,
                    subtitle = hotWindowSubtitle(window),
                    selected = draft.hotWindow == window,
                    onClick = {
                        isCalendarExpanded = false
                        onWindowSelected(window)
                    },
                )
            }

            HotWindowRow(
                icon = Icons.Filled.EditCalendar,
                title = L10n.string("Another date", "Другая дата"),
                subtitle = if (isCustomHotDateSelected) {
                    hotDateTitle(resolvedHotDate)
                } else {
                    L10n.string("Choose in calendar", "Выбрать в календаре")
                },
                selected = isCustomHotDateSelected,
                trailingIcon = if (isCustomHotDateSelected) Icons.Filled.CheckCircle else Icons.Filled.ExpandMore,
                onClick = {
                    onCustomDateSelected(customHotDate ?: defaultCustomHotDate())
                    isCalendarExpanded = !isCalendarExpanded
                },
            )

            AnimatedVisibility(visible = isCustomHotDateSelected && isCalendarExpanded) {
                HotDateCalendarCard(
                    selection = customHotDate ?: defaultCustomHotDate(),
                    onSelect = onCustomDateSelected,
                )
            }
        }

        Text(
            L10n.string("What time?", "Во сколько?"),
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
        )

        val times = hotQuickTimes(resolvedHotDate)
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            times.forEach { time ->
                val selected = (draft.hotStartTime ?: "19:00") == time
                val shape = continuousShape(16.dp)
                Box(
                    modifier = Modifier
                        .size(width = 84.dp, height = 50.dp)
                        .clip(shape)
                        .background(if (selected) AppTheme.court else Color.White)
                        .border(
                            1.dp,
                            if (selected) AppTheme.court else Color.Black.copy(alpha = 0.07f),
                            shape,
                        )
                        .clickable { onTimeSelected(time) },
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

        // FieldShell + Stepper in SwiftUI
        val duration = draft.durationMinutes ?: selectedSport.defaultDurationMinutes
        val fieldShape = continuousShape(22.dp)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                L10n.string("Duration", "Длительность").uppercase(),
                style = AppText.captionSemibold.copy(letterSpacing = 1.4.sp),
                color = AppTheme.ink.copy(alpha = 0.68f),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(fieldShape)
                    .background(AppTheme.creamLight)
                    .border(1.dp, AppTheme.court.copy(alpha = 0.16f), fieldShape)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    L10n.string("$duration min", "$duration мин"),
                    style = AppText.headline,
                    color = AppTheme.ink,
                    modifier = Modifier.weight(1f),
                )
                StepperButton(Icons.Filled.Remove, enabled = duration > 30) {
                    onDurationChanged((duration - 30).coerceAtLeast(30))
                }
                Spacer(Modifier.width(8.dp))
                StepperButton(Icons.Filled.Add, enabled = duration < 180) {
                    onDurationChanged((duration + 30).coerceAtMost(180))
                }
            }
        }
    }
}

@Composable
private fun HotWindowRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    selected: Boolean,
    trailingIcon: ImageVector? = Icons.Filled.CheckCircle,
    onClick: () -> Unit,
) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) AppTheme.mint.copy(alpha = 0.55f) else Color.White)
            .border(
                1.dp,
                if (selected) AppTheme.court.copy(alpha = 0.35f) else Color.Black.copy(alpha = 0.06f),
                shape,
            )
            .clickable(onClick = onClick)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(CircleShape)
                .background(if (selected) AppTheme.mint else Color.Black.copy(alpha = 0.04f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (selected) AppTheme.court else AppTheme.ink.copy(alpha = 0.72f),
                modifier = Modifier.size(18.dp),
            )
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                title,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (selected) AppTheme.court else AppTheme.ink,
            )
            Text(
                subtitle,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.48f),
            )
        }

        if (selected) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = AppTheme.court, modifier = Modifier.size(20.dp))
        } else if (trailingIcon == Icons.Filled.ExpandMore) {
            Icon(
                Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = AppTheme.ink.copy(alpha = 0.42f),
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

/** Port of `HotDateCalendarCard`: a month grid starting today. */
@Composable
private fun HotDateCalendarCard(selection: LocalDate, onSelect: (LocalDate) -> Unit) {
    val today = LocalDate.now()
    val shape = continuousShape(20.dp)
    val firstOfMonth = selection.withDayOfMonth(1)
    val daysInMonth = selection.lengthOfMonth()
    // Monday-first, matching the Russian calendar the iOS card uses.
    val leadingBlanks = (firstOfMonth.dayOfWeek.value + 6) % 7

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            firstOfMonth.formattedMonthTitle(),
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
        )

        Row(modifier = Modifier.fillMaxWidth()) {
            DayOfWeek.entries.forEach { day ->
                Text(
                    day.shortTitle,
                    style = AppText.caption2Semibold,
                    color = AppTheme.ink.copy(alpha = 0.42f),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        val cells = leadingBlanks + daysInMonth
        val rows = ceil(cells / 7.0).toInt()
        repeat(rows) { row ->
            Row(modifier = Modifier.fillMaxWidth()) {
                repeat(7) { column ->
                    val index = row * 7 + column
                    val dayNumber = index - leadingBlanks + 1
                    if (dayNumber in 1..daysInMonth) {
                        val date = firstOfMonth.withDayOfMonth(dayNumber)
                        val isPast = date.isBefore(today)
                        val isSelected = date == selection
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(40.dp)
                                .clip(CircleShape)
                                .background(if (isSelected) AppTheme.court else Color.Transparent)
                                .clickable(enabled = !isPast) { onSelect(date) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                dayNumber.toString(),
                                style = AppText.subheadlineSemibold,
                                color = when {
                                    isSelected -> Color.White
                                    isPast -> AppTheme.ink.copy(alpha = 0.24f)
                                    else -> AppTheme.ink
                                },
                            )
                        }
                    } else {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun StepperButton(icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.05f))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = AppTheme.ink.copy(alpha = if (enabled) 0.82f else 0.28f),
            modifier = Modifier.size(18.dp),
        )
    }
}

// MARK: - Step 2: who

/** Port of `sportRailSection`. */
@Composable
private fun SportRailSection(sports: List<Sport>, selected: Sport, onSelect: (Sport) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                L10n.string("What are you looking for?", "Что ищем?"),
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
                modifier = Modifier.weight(1f),
            )
            Text(
                L10n.string("Choose a sport", "Выбрать вид спорта"),
                style = AppText.subheadline.copy(fontWeight = FontWeight.Medium),
                color = AppTheme.court,
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            sports.forEach { sport ->
                val isSelected = selected == sport
                val cardShape = continuousShape(26.dp)
                Column(
                    modifier = Modifier
                        .size(width = 98.dp, height = 118.dp)
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
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.width(86.dp),
                    )
                }
            }
        }
    }
}

/** Port of `compactStatsSection`: the players counter and the level card, side by side. */
@Composable
private fun CompactStatsSection(
    appModel: AppViewModel,
    playersNeeded: Int,
    maxPlayers: Int,
    level: Int,
    desiredMin: Int,
    desiredMax: Int,
    onPlayersChange: (Int) -> Unit,
    onLevelChange: (Int) -> Unit,
) {
    val haptics = rememberAppHaptics()
    val cardShape = continuousShape(28.dp)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .clip(cardShape)
                .background(Color.White)
                .border(1.dp, Color.Black.copy(alpha = 0.06f), cardShape)
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                L10n.string("Players needed", "Нужно игроков"),
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp)
                    .clip(continuousShape(20.dp))
                    .background(Color.Black.copy(alpha = 0.04f)),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                StepperButton(Icons.Filled.Remove, enabled = playersNeeded > 1) {
                    haptics.selection()
                    onPlayersChange(playersNeeded - 1)
                }
                Text(
                    playersNeeded.toString(),
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppTheme.ink,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
                StepperButton(Icons.Filled.Add, enabled = playersNeeded < maxPlayers) {
                    haptics.selection()
                    onPlayersChange(playersNeeded + 1)
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                val user = appModel.currentUser
                if (user != null) {
                    RemoteAvatarView(name = user.displayName, path = user.avatarUrl, size = 28.dp)
                } else {
                    Box(
                        Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(AppTheme.clay.copy(alpha = 0.9f)),
                    )
                }
                repeat(minOf(playersNeeded, 2)) { index ->
                    Box(
                        Modifier
                            .offset(x = (-8 * (index + 1)).dp)
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(AppTheme.ink.copy(alpha = 0.18f + index * 0.08f)),
                    )
                }
                Text(
                    L10n.string("You + ${openSeatsLabel(playersNeeded)}", "Вы + ${openSeatsLabel(playersNeeded)}"),
                    style = AppText.subheadline.copy(fontWeight = FontWeight.Medium),
                    color = AppTheme.court,
                    maxLines = 2,
                    modifier = Modifier.padding(start = 10.dp),
                )
            }
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .clip(cardShape)
                .background(Color.White)
                .border(1.dp, Color.Black.copy(alpha = 0.06f), cardShape)
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                L10n.string("Level", "Уровень"),
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
            )

            Text(
                sportLevelTitle(level),
                fontSize = 19.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppTheme.ink,
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(42.dp)
                    .clip(continuousShape(16.dp))
                    .background(Color.Black.copy(alpha = 0.04f)),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                StepperButton(Icons.Filled.Remove, enabled = level > 1) {
                    haptics.selection()
                    onLevelChange(level - 1)
                }
                Text(
                    level.toString(),
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
                StepperButton(Icons.Filled.Add, enabled = level < 10) {
                    haptics.selection()
                    onLevelChange(level + 1)
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                val filled = ceil(level / 2.0).toInt()
                (1..5).forEach { index ->
                    Box(
                        Modifier
                            .weight(1f)
                            .height(8.dp)
                            .background(
                                if (index <= filled) AppTheme.court else Color.Black.copy(alpha = 0.08f),
                                RoundedCornerShape(percent = 50),
                            ),
                    )
                }
            }

            Text(
                L10n.string(
                    "Looking for level $desiredMin-$desiredMax players",
                    "Ищем игроков $desiredMin-$desiredMax",
                ),
                style = AppText.footnote,
                color = AppTheme.ink.copy(alpha = 0.45f),
            )
        }
    }
}

/** Port of `commentSection`. */
@Composable
private fun CommentSection(comment: String, onCommentChange: (String) -> Unit) {
    val shape = continuousShape(24.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.Black.copy(alpha = 0.03f))
            .padding(18.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            Icons.Outlined.ChatBubbleOutline,
            contentDescription = null,
            tint = AppTheme.ink.copy(alpha = 0.78f),
            modifier = Modifier.size(20.dp).padding(top = 4.dp),
        )

        Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.weight(1f)) {
            Text(
                L10n.string("Comment (optional)", "Комментарий (необязательно)"),
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.56f),
            )
            OutlinedTextField(
                value = comment,
                onValueChange = onCommentChange,
                placeholder = {
                    Text(
                        L10n.string("For example: I'd like to play after 7 PM", "Например: хочу сыграть после 19:00"),
                        style = AppText.subheadline,
                        color = AppTheme.ink.copy(alpha = 0.38f),
                    )
                },
                minLines = 2,
                maxLines = 4,
                textStyle = AppText.subheadline,
                keyboardOptions = KeyboardOptions(
                    capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Sentences,
                ),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedTextColor = AppTheme.ink,
                    unfocusedTextColor = AppTheme.ink,
                    cursorColor = AppTheme.court,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

// MARK: - Step 3: where

/** Port of `hotLocationSection`, both the club/district and the route branch. */
@Composable
private fun LocationStep(
    sport: Sport,
    selectedCourt: Court?,
    hasCourtBooked: Boolean,
    districts: List<String>,
    routePoints: List<RunningRoutePoint>,
    routeTitle: String?,
    onOpenClubPicker: () -> Unit,
    onOpenRoutePicker: () -> Unit,
    onClearCourt: () -> Unit,
    onToggleBooked: (Boolean) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                if (sport.isRouteSport) {
                    L10n.string("Where is the route?", "Где маршрут?")
                } else {
                    L10n.string("Where are we playing?", "Где играем?")
                },
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
            )
            Text(
                if (sport.isRouteSport) {
                    L10n.string(
                        "Mark the route on the map. Clubs and districts aren't needed here.",
                        "Отметьте маршрут на карте. Клубы и районы здесь не нужны.",
                    )
                } else {
                    L10n.string(
                        "Choose a district or a club if it's already booked",
                        "Выберите район или клуб, если он уже забронирован",
                    )
                },
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.56f),
            )
        }

        if (sport.isRouteSport) {
            // Port of `runningRouteSection`.
            val points = routePoints
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            sport.routeDefaultTitle,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = AppTheme.ink,
                        )
                        Text(
                            // `runningRouteSummary`
                            if (points.size >= 2) {
                                val name = routeTitle?.trim()?.takeIf { it.isNotEmpty() }
                                    ?: L10n.string("Route on map", "Маршрут на карте")
                                L10n.string("${points.size} points · $name", "${points.size} точек · $name")
                            } else {
                                L10n.string(
                                    "Mark the start, finish, and key points",
                                    "Нарисуйте старт, финиш и ключевые точки",
                                )
                            },
                            style = AppText.captionSemibold,
                            color = AppTheme.ink.copy(alpha = 0.56f),
                        )
                    }

                    Row(
                        modifier = Modifier
                            .height(38.dp)
                            .clip(androidx.compose.foundation.shape.RoundedCornerShape(percent = 50))
                            .background(AppTheme.court)
                            .clickable(onClick = onOpenRoutePicker)
                            .padding(horizontal = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Filled.Route,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            if (points.isNotEmpty()) {
                                L10n.string("Edit", "Изменить")
                            } else {
                                L10n.string("Draw", "Нарисовать")
                            },
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }
                }

                if (points.size >= 2) {
                    val shape = continuousShape(20.dp)
                    RunningRoutePreviewMapView(
                        points = points,
                        followsRoads = sport.routeFollowsRoads,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(150.dp)
                            .clip(shape)
                            .border(1.dp, Color.Black.copy(alpha = 0.08f), shape),
                    )
                } else {
                    val shape = continuousShape(20.dp)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(shape)
                            .background(Color.White)
                            .border(1.dp, Color.Black.copy(alpha = 0.07f), shape)
                            .clickable(onClick = onOpenRoutePicker)
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(42.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(AppTheme.mint),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Filled.Map,
                                contentDescription = null,
                                tint = AppTheme.court,
                                modifier = Modifier.size(18.dp),
                            )
                        }

                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                L10n.string(
                                    "Mark route points on the map",
                                    "Отметьте точки маршрута на карте",
                                ),
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                color = AppTheme.ink,
                            )
                            Text(
                                L10n.string(
                                    "Players will see the route on the search card.",
                                    "Маршрут будет виден игрокам в карточке поиска.",
                                ),
                                style = AppText.caption,
                                color = AppTheme.ink.copy(alpha = 0.56f),
                            )
                        }

                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = AppTheme.ink.copy(alpha = 0.32f),
                            modifier = Modifier.size(12.dp),
                        )
                    }
                }
            }
            return@Column
        }

        // courtToggle
        val toggleShape = continuousShape(22.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(toggleShape)
                .background(Color.White.copy(alpha = 0.78f))
                .border(1.dp, Color.Black.copy(alpha = 0.06f), toggleShape)
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(sport.venueBookedTitle, style = AppText.subheadlineSemibold, color = AppTheme.ink)
                Text(
                    L10n.string(
                        "Select this if you only need to agree on the roster and time.",
                        "Отметь, если осталось только согласовать состав и время.",
                    ),
                    style = AppText.caption,
                    color = AppTheme.ink.copy(alpha = 0.6f),
                )
            }

            // The SwiftUI toggle is a custom 54x32 pill, not a system Switch.
            Box(
                modifier = Modifier
                    .size(width = 54.dp, height = 32.dp)
                    .clip(continuousShape(18.dp))
                    .background(if (hasCourtBooked) AppTheme.court else AppTheme.cream)
                    .clickable { onToggleBooked(!hasCourtBooked) },
                contentAlignment = if (hasCourtBooked) Alignment.CenterEnd else Alignment.CenterStart,
            ) {
                Box(
                    Modifier
                        .padding(4.dp)
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(Color.White),
                )
            }
        }

        // Club selector row (the SwiftUI version pairs this with a map preview).
        val clubShape = continuousShape(22.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(clubShape)
                .background(Color.White)
                .border(1.dp, Color.Black.copy(alpha = 0.06f), clubShape)
                .clickable(onClick = onOpenClubPicker)
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(AppTheme.mint),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Place, contentDescription = null, tint = AppTheme.court, modifier = Modifier.size(18.dp))
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    selectedCourt?.name ?: L10n.string("Choose a club", "Выбрать клуб"),
                    style = AppText.subheadlineSemibold,
                    color = AppTheme.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    selectedCourt?.let {
                        listOfNotNull(it.metroDisplayName, localizedDistrictName(it.district), it.address)
                            .joinToString(" · ")
                    } ?: if (districts.isEmpty()) {
                        L10n.string("We'll show nearby clubs", "Покажем клубы рядом")
                    } else {
                        districts.mapNotNull(::localizedDistrictName).take(3).joinToString(", ")
                    },
                    style = AppText.caption,
                    color = AppTheme.ink.copy(alpha = 0.52f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            if (selectedCourt != null) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = L10n.string("Clear", "Очистить"),
                    tint = AppTheme.ink.copy(alpha = 0.42f),
                    modifier = Modifier
                        .size(20.dp)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = onClearCourt,
                        ),
                )
            }
        }
    }
}

// MARK: - Step 4: review

/** Port of `urgentConfirmationSection`. */
@Composable
private fun ConfirmStep(
    dateTitle: String,
    startTime: String,
    sport: Sport,
    playersNeeded: Int,
    level: Int,
    locationTitle: String,
    inviteUrl: String,
) {
    val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
    val haptics = rememberAppHaptics()
    val cardShape = continuousShape(22.dp)

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(
            L10n.string("Review and publish", "Проверьте и опубликуйте"),
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
        )

        // inviteBanner
        val bannerShape = continuousShape(22.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(bannerShape)
                .background(AppTheme.mint.copy(alpha = 0.6f))
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.88f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Groups, contentDescription = null, tint = AppTheme.ink, modifier = Modifier.size(19.dp))
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    L10n.string("Faster with friends", "Быстрее с друзьями"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                )
                Text(
                    L10n.string("Invite friends and play more often", "Пригласите друзей и собирайте игры чаще"),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppTheme.ink.copy(alpha = 0.64f),
                    maxLines = 2,
                )
            }

            Text(
                L10n.string("Invite", "Пригласить"),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                modifier = Modifier
                    .clip(RoundedCornerShape(percent = 50))
                    .background(AppTheme.ink)
                    .clickable {
                        haptics.selection()
                        clipboard.setText(androidx.compose.ui.text.AnnotatedString(inviteUrl))
                    }
                    .padding(horizontal = 16.dp, vertical = 11.dp),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(cardShape)
                .background(Color.White)
                .border(1.dp, Color.Black.copy(alpha = 0.06f), cardShape)
                .padding(14.dp),
        ) {
            ConfirmationRow(Icons.Filled.CalendarMonth, L10n.string("When", "Когда"), "$dateTitle, $startTime")
            ConfirmationDivider()
            ConfirmationRow(Icons.Filled.SportsTennis, L10n.string("Sport", "Вид спорта"), sport.title)
            ConfirmationDivider()
            ConfirmationRow(
                Icons.Filled.PersonAddAlt,
                L10n.string("Players needed", "Нужно игроков"),
                L10n.string("You + ${openSeatsLabel(playersNeeded)}", "Вы + ${openSeatsLabel(playersNeeded)}"),
            )
            ConfirmationDivider()
            ConfirmationRow(
                Icons.Filled.BarChart,
                L10n.string("Level", "Уровень"),
                "${maxOf(level - 1, 1)}-${minOf(level + 1, 10)}",
            )
            ConfirmationDivider()
            ConfirmationRow(Icons.Filled.Place, L10n.string("Location", "Место"), locationTitle)
        }
    }
}

@Composable
private fun ConfirmationRow(icon: ImageVector, title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = AppTheme.ink.copy(alpha = 0.68f),
            modifier = Modifier.size(14.dp),
        )
        Text(
            title,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = AppTheme.ink.copy(alpha = 0.58f),
        )
        Text(
            value,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppTheme.ink,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun ConfirmationDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Color.Black.copy(alpha = 0.06f)))
}

// MARK: - Helpers ported from SearchComposerView

private fun hotDate(window: HotWindow): LocalDate = LocalDate.now().plusDays(
    when (window) {
        HotWindow.TODAY -> 0L
        HotWindow.TOMORROW -> 1L
        HotWindow.DAY_AFTER_TOMORROW -> 2L
    },
)

/** `hotWindowSubtitle(for:)` - "d MMM" in the display locale. */
private fun hotWindowSubtitle(window: HotWindow): String = hotDate(window).formattedDayMonth()

/** `hotDateTitle`. */
private fun hotDateTitle(date: LocalDate): String {
    val today = LocalDate.now()
    return when (date) {
        today -> L10n.string("Today", "Сегодня")
        today.plusDays(1) -> L10n.string("Tomorrow", "Завтра")
        today.plusDays(2) -> L10n.string("Day after tomorrow", "Послезавтра")
        else -> date.formattedDayMonth()
    }
}

/** `roundedUpMinutesFromNow()`. */
private fun roundedUpMinutesFromNow(): Int {
    val now = LocalTime.now()
    val total = now.hour * 60 + now.minute
    return minOf(ceil(total / 30.0).toInt() * 30, 23 * 60 + 30)
}

/** `timeLabel(minutes:)`. */
private fun timeLabel(minutes: Int): String {
    val safe = maxOf(0, minutes)
    return "%02d:%02d".format(safe / 60, safe % 60)
}

/** `hotQuickTimes`: half-hour slots from now (today) or from midnight. */
private fun hotQuickTimes(date: LocalDate): List<String> {
    val start = if (date == LocalDate.now()) roundedUpMinutesFromNow() else 0
    val clamped = start.coerceIn(0, 23 * 60 + 30)
    val times = (clamped..(23 * 60 + 30) step 30).map(::timeLabel)
    return times.ifEmpty { listOf(timeLabel(clamped)) }
}

/** `preferredHotStartTime(for:)`. */
private fun preferredHotStartTime(date: LocalDate): String =
    if (date == LocalDate.now()) timeLabel(roundedUpMinutesFromNow()) else "09:00"

/** `defaultCustomHotDate`: three days out. */
private fun defaultCustomHotDate(): LocalDate = LocalDate.now().plusDays(3)

/** `timeRangeFromHotStartTime(_:)`. */
private fun timeRangeFromHotStartTime(value: String): String {
    val hour = value.substringBefore(":").toIntOrNull() ?: 19
    return when {
        hour < 12 -> TimeRange.MORNING.wire
        hour < 18 -> TimeRange.DAY.wire
        else -> TimeRange.EVENING.wire
    }
}

/** `hotStartsAtPayloadValue()`: only sent for a custom date. */
private fun hotStartsAtPayloadValue(
    isCustomDate: Boolean,
    date: LocalDate,
    startTime: String?,
): String? {
    if (!isCustomDate) return null
    val time = startTime ?: "19:00"
    val hour = time.substringBefore(":").toIntOrNull() ?: return null
    val minute = time.substringAfter(":", "0").toIntOrNull() ?: 0
    return date.atTime(hour, minute).atZone(ZoneId.systemDefault()).toInstant().toServerISOString()
}

/** `sportLevelSummary.title`. */
private fun sportLevelTitle(level: Int): String = when (level) {
    1, 2 -> L10n.string("Beginner", "Начальный")
    3, 4 -> L10n.string("Basic", "Базовый")
    5, 6 -> L10n.string("Intermediate", "Средний")
    7, 8 -> L10n.string("Advanced", "Продвинутый")
    else -> L10n.string("Expert", "Сильный")
}

/** `openSeatsLabel` with `openSeatsWord`: Russian plural agreement. */
private fun openSeatsLabel(count: Int): String = if (LocaleStore.current == AppLocale.EN) {
    "$count open ${if (count == 1) "spot" else "spots"}"
} else {
    "$count ${openSeatsWord(count)} открыто"
}

private fun openSeatsWord(count: Int): String {
    if (count % 100 in 11..14) return "мест"
    return when (count % 10) {
        1 -> "место"
        2, 3, 4 -> "места"
        else -> "мест"
    }
}

/** `locationTitle`. */
private fun locationTitle(sport: Sport, court: Court?, draft: SearchDraft): String {
    if (sport.isRouteSport) {
        draft.runningRoute?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        if (!draft.runningRoutePoints.isNullOrEmpty()) return sport.routeDefaultTitle
        return L10n.string("No route", "Без маршрута")
    }

    court?.name?.let { return it }
    draft.customVenueAddress?.let { return it }
    draft.customVenueTitle?.let { return it }
    val names = draft.preferredDistricts.mapNotNull(::localizedDistrictName)
    return if (names.isEmpty()) L10n.string("No preference", "Без привязки") else names.take(3).joinToString(", ")
}

private fun LocalDate.formattedDayMonth(): String =
    java.time.format.DateTimeFormatter
        .ofPattern("d MMM", java.util.Locale.forLanguageTag(LocaleStore.current.code))
        .format(this)

private fun LocalDate.formattedMonthTitle(): String =
    java.time.format.DateTimeFormatter
        .ofPattern("LLLL yyyy", java.util.Locale.forLanguageTag(LocaleStore.current.code))
        .format(this)
        .replaceFirstChar { it.uppercase() }
