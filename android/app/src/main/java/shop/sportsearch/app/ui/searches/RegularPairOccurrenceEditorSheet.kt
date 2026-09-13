package shop.sportsearch.app.ui.searches

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Train
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.RegularPairOccurrence
import shop.sportsearch.app.core.formattedHourMinute
import shop.sportsearch.app.core.formattedWeekdayDayMonth
import shop.sportsearch.app.core.localizedDistrictName
import shop.sportsearch.app.core.parseServerInstant
import shop.sportsearch.app.ui.components.AppScreen
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.FieldShell
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/** `filteredCourts` shows this many when the query is empty. */
private const val COURT_PREVIEW_LIMIT = 18

/** Port of `struct RegularPairOccurrenceEditorSheet`. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun RegularPairOccurrenceEditorSheet(
    occurrence: RegularPairOccurrence,
    courts: List<Court>,
    onDismiss: () -> Unit,
    onSave: suspend (Instant, String?) -> Unit,
) {
    DismissOnSystemBack(onDismiss)

    val zone = remember { ZoneId.systemDefault() }
    val scope = rememberCoroutineScope()

    var scheduledAt by remember {
        mutableStateOf(parseServerInstant(occurrence.scheduledAt) ?: Instant.now().plusSeconds(3600))
    }
    var proposedCourtId by remember { mutableStateOf(occurrence.proposedCourt?.id) }
    var courtQuery by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var isDatePickerPresented by remember { mutableStateOf(false) }
    var isTimePickerPresented by remember { mutableStateOf(false) }

    // `filteredCourts` - the chosen club floats to the top, the rest sort by name.
    val filteredCourts = remember(courts, courtQuery, proposedCourtId) {
        val sorted = courts.sortedWith(
            compareBy({ it.id != proposedCourtId }, { it.name.lowercase() }),
        )
        val query = courtQuery.trim().lowercase()
        if (query.isEmpty()) {
            sorted.take(COURT_PREVIEW_LIMIT)
        } else {
            sorted.filter { court -> court.searchableText.contains(query) }
        }
    }

    AppScreen {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                SheetHeader(
                    title = L10n.string("Adjust the slot", "Настроить слот"),
                    onClose = onDismiss,
                )
            }

            item {
                SectionCard(
                    title = L10n.string("Change the slot", "Изменить слот"),
                    subtitle = L10n.string(
                        "A new date or club clears the old confirmations and asks both of you again.",
                        "Новая дата или клуб сбросят старые подтверждения и попросят ответить заново.",
                    ),
                ) {
                    FieldShell(title = L10n.string("Date and time", "Дата и время")) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            SecondaryActionButton(
                                title = scheduledAt.formattedWeekdayDayMonth(),
                                onClick = { isDatePickerPresented = true },
                                tint = AppTheme.ink,
                                modifier = Modifier.weight(1f),
                            )
                            SecondaryActionButton(
                                title = scheduledAt.formattedHourMinute(),
                                onClick = { isTimePickerPresented = true },
                                tint = AppTheme.ink,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }

                    FieldShell(title = L10n.string("Club", "Клуб")) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            CourtSearchField(courtQuery) { courtQuery = it }

                            Column(
                                modifier = Modifier.heightIn(max = 280.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                CourtOptionRow(
                                    title = L10n.string("No club", "Без клуба"),
                                    subtitle = L10n.string(
                                        "Leave the slot without a venue",
                                        "Оставить слот без привязки к центру",
                                    ),
                                    isSelected = proposedCourtId == null,
                                ) { proposedCourtId = null }

                                when {
                                    courts.isEmpty() -> CourtHint(
                                        L10n.string("Loading the club list.", "Список клубов загружается."),
                                    )
                                    filteredCourts.isEmpty() -> CourtHint(
                                        L10n.string(
                                            "Nothing found. Try a club name, metro station or district.",
                                            "Ничего не найдено. Попробуй название клуба, метро или район.",
                                        ),
                                    )
                                    else -> filteredCourts.forEach { court ->
                                        CourtOptionRow(
                                            title = court.name,
                                            subtitle = court.subtitleLine,
                                            metaItems = court.metaItems,
                                            isSelected = proposedCourtId == court.id,
                                        ) { proposedCourtId = court.id }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SecondaryActionButton(
                        title = L10n.string("Cancel", "Отмена"),
                        onClick = onDismiss,
                        tint = AppTheme.ink,
                        modifier = Modifier.weight(1f),
                    )
                    PrimaryActionButton(
                        title = if (isSaving) {
                            L10n.string("Saving…", "Сохраняем…")
                        } else {
                            L10n.string("Save", "Сохранить")
                        },
                        onClick = {
                            scope.launch {
                                isSaving = true
                                onSave(scheduledAt, proposedCourtId)
                                isSaving = false
                                onDismiss()
                            }
                        },
                        modifier = Modifier.weight(1f),
                        tint = AppTheme.court,
                        enabled = !isSaving,
                    )
                }
            }
        }
    }

    if (isDatePickerPresented) {
        val state = rememberDatePickerState(initialSelectedDateMillis = scheduledAt.toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { isDatePickerPresented = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        val picked = Instant.ofEpochMilli(millis).atZone(ZoneId.of("UTC")).toLocalDate()
                        val time = scheduledAt.atZone(zone).toLocalTime()
                        scheduledAt = LocalDateTime.of(picked, time).atZone(zone).toInstant()
                    }
                    isDatePickerPresented = false
                }) { Text("OK", color = AppTheme.court) }
            },
            dismissButton = {
                TextButton(onClick = { isDatePickerPresented = false }) {
                    Text(L10n.string("Cancel", "Отмена"), color = AppTheme.ink)
                }
            },
        ) { DatePicker(state = state) }
    }

    if (isTimePickerPresented) {
        val current = scheduledAt.atZone(zone).toLocalTime()
        val state = rememberTimePickerState(initialHour = current.hour, initialMinute = current.minute, is24Hour = true)
        AlertDialog(
            onDismissRequest = { isTimePickerPresented = false },
            containerColor = Color.White,
            title = { Text(L10n.string("Date and time", "Дата и время"), color = AppTheme.ink) },
            text = { TimePicker(state = state) },
            confirmButton = {
                TextButton(onClick = {
                    val day = scheduledAt.atZone(zone).toLocalDate()
                    scheduledAt = LocalDateTime.of(day, java.time.LocalTime.of(state.hour, state.minute))
                        .atZone(zone).toInstant()
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
}

/** `searchableText(for:)`. */
private val Court.searchableText: String
    get() = listOfNotNull(name, address, metroDisplayName, localizedDistrictName(district))
        .joinToString(" ") { it.lowercase() }

/** `courtSubtitle(for:)`. */
private val Court.subtitleLine: String
    get() = listOfNotNull(metroDisplayName, localizedDistrictName(district), address)
        .filter { it.isNotEmpty() }
        .joinToString(" • ")

private val Court.metaItems: List<Pair<ImageVector, String>>
    get() = listOfNotNull(
        metroDisplayName?.let { Icons.Filled.Train to it },
        localizedDistrictName(district)?.let { Icons.Filled.Map to it },
        address.takeIf { it.isNotEmpty() }?.let { Icons.Outlined.Place to it },
    )

@Composable
private fun CourtSearchField(query: String, onQueryChange: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(16.dp))
            .background(AppTheme.creamLight)
            .padding(horizontal = 12.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Filled.Search,
            contentDescription = null,
            tint = AppTheme.ink.copy(alpha = 0.48f),
            modifier = Modifier.size(18.dp),
        )
        Box(modifier = Modifier.weight(1f)) {
            if (query.isEmpty()) {
                Text(
                    L10n.string("Find a club, metro or district", "Найти клуб, метро или район"),
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.48f),
                )
            }
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = AppText.subheadline.copy(color = AppTheme.ink),
                cursorBrush = SolidColor(AppTheme.court),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun CourtHint(text: String) {
    Text(
        text,
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        style = AppText.footnote,
        color = AppTheme.ink.copy(alpha = 0.62f),
    )
}

/** Port of `courtOptionRow(title:subtitle:metaItems:isSelected:action:)`. */
@Composable
private fun CourtOptionRow(
    title: String,
    subtitle: String,
    metaItems: List<Pair<ImageVector, String>> = emptyList(),
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    val shape = continuousShape(16.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (isSelected) AppTheme.mint else AppTheme.creamLight)
            .border(
                1.dp,
                if (isSelected) AppTheme.court.copy(alpha = 0.2f) else Color.White.copy(alpha = 0.75f),
                shape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = AppText.subheadlineSemibold, color = AppTheme.ink)

            if (metaItems.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    metaItems.forEach { (icon, text) ->
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(icon, contentDescription = null, tint = AppTheme.court, modifier = Modifier.size(10.dp))
                            Text(
                                text,
                                style = AppText.caption,
                                color = AppTheme.ink.copy(alpha = 0.64f),
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            } else {
                Text(subtitle, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.64f))
            }
        }

        Spacer(Modifier.size(8.dp))

        if (isSelected) {
            Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = AppTheme.court,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}
