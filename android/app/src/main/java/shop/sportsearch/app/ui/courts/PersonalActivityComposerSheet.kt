package shop.sportsearch.app.ui.courts

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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberDatePickerState
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

private val zone: ZoneId get() = ZoneId.systemDefault()

/** Port of `struct PersonalActivityComposerSheet` in CourtsView.swift. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun PersonalActivityComposerSheet(
    appModel: AppViewModel,
    court: Court,
    initialSport: Sport?,
    onDismiss: () -> Unit,
    onCreated: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()

    val availableSports = court.supportedSports.ifEmpty { listOf(Sport.TENNIS) }
    var selectedSport by remember {
        mutableStateOf(
            initialSport?.takeIf { availableSports.contains(it) } ?: availableSports.first(),
        )
    }
    var selectedDate by remember { mutableStateOf(LocalDate.now(zone).plusDays(1)) }
    var selectedTime by remember { mutableStateOf("09:00") }
    var durationMinutes by remember { mutableStateOf(selectedSport.defaultDurationMinutes) }
    var comment by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var isDatePickerPresented by remember { mutableStateOf(false) }

    val quickTimes = remember {
        generateSequence(9 * 60) { it + 30 }.takeWhile { it <= 23 * 60 + 30 }
            .map { "%02d:%02d".format(it / 60, it % 60) }
            .toList()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .navigationBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 18.dp, bottom = 34.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(17.dp))
            }
            Spacer(Modifier.weight(1f))
            Text(
                L10n.string("Personal visit", "Личный визит"),
                style = AppText.headlineBold,
                color = Color.White,
            )
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(40.dp))
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(22.dp))
                .background(Color.White.copy(alpha = 0.06f))
                .border(1.dp, DarkStroke, continuousShape(22.dp))
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CourtImageTile(court, 72.dp)

            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    court.name,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    listOfNotNull(court.metroDisplayName, localizedDistrictName(court.district)).joinToString(" · "),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppTheme.court,
                    maxLines = 2,
                )
                Text(
                    court.displayAddress,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.52f),
                    maxLines = 2,
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                L10n.string("What are you planning?", "Что планируете?"),
                style = AppText.headlineBold,
                color = Color.White,
            )
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                availableSports.forEach { sport ->
                    val selected = selectedSport == sport
                    Row(
                        modifier = Modifier
                            .height(42.dp)
                            .clip(CircleShape)
                            .background(if (selected) AppTheme.court else Color.White.copy(alpha = 0.08f))
                            .clickable {
                                selectedSport = sport
                                durationMinutes = sport.defaultDurationMinutes
                                haptics.selection()
                            }
                            .padding(horizontal = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SportIconView(
                            sport = sport,
                            color = if (selected) Color.Black else Color.White,
                            size = 15.dp,
                        )
                        Text(
                            sport.title,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (selected) Color.Black else Color.White,
                        )
                    }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(L10n.string("Date", "Дата"), style = AppText.headlineBold, color = Color.White)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(18.dp))
                    .background(Color.White.copy(alpha = 0.08f))
                    .clickable { isDatePickerPresented = true }
                    .padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    selectedDate.atStartOfDay(zone).toInstant().formattedDayMonth(),
                    style = AppText.headline,
                    color = Color.White,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    L10n.string("Change", "Изменить"),
                    style = AppText.captionBold,
                    color = AppTheme.court,
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(L10n.string("Time", "Время"), style = AppText.headlineBold, color = Color.White)
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                quickTimes.forEach { time ->
                    val selected = selectedTime == time
                    val shape = continuousShape(16.dp)
                    Box(
                        modifier = Modifier
                            .width(84.dp)
                            .height(48.dp)
                            .clip(shape)
                            .background(if (selected) AppTheme.court else Color.White.copy(alpha = 0.08f))
                            .border(
                                1.dp,
                                if (selected) AppTheme.court.copy(alpha = 0.42f) else Color.White.copy(alpha = 0.1f),
                                shape,
                            )
                            .clickable {
                                selectedTime = time
                                haptics.selection()
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            time,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (selected) Color.Black else Color.White,
                        )
                    }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(L10n.string("Duration", "Длительность"), style = AppText.headlineBold, color = Color.White)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(18.dp))
                    .background(Color.White.copy(alpha = 0.08f))
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    L10n.string("$durationMinutes min", "$durationMinutes мин"),
                    style = AppText.headline,
                    color = Color.White,
                    modifier = Modifier.weight(1f),
                )
                StepperButton(Icons.Filled.Remove, durationMinutes <= 15) {
                    durationMinutes = (durationMinutes - 15).coerceAtLeast(15)
                    haptics.selection()
                }
                StepperButton(Icons.Filled.Add, durationMinutes >= 360) {
                    durationMinutes = (durationMinutes + 15).coerceAtMost(360)
                    haptics.selection()
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(L10n.string("Note", "Заметка"), style = AppText.headlineBold, color = Color.White)
            OutlinedTextField(
                value = comment,
                onValueChange = { comment = it },
                modifier = Modifier.fillMaxWidth().height(110.dp),
                placeholder = {
                    Text(
                        L10n.string(
                            "For example: leg workout, 40 minutes on the track",
                            "Например: тренировка ног, дорожка 40 минут",
                        ),
                        color = Color.White.copy(alpha = 0.38f),
                        style = AppText.subheadline,
                    )
                },
                textStyle = AppText.subheadline.copy(color = Color.White),
                shape = continuousShape(18.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.White.copy(alpha = 0.08f),
                    unfocusedContainerColor = Color.White.copy(alpha = 0.08f),
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    cursorColor = AppTheme.court,
                ),
            )
        }

        Box {
            PrimaryActionButton(
                title = if (isSaving) {
                    L10n.string("Saving...", "Сохраняем...")
                } else {
                    L10n.string("Plan visit", "Запланировать визит")
                },
                tint = AppTheme.court,
                enabled = !isSaving,
                onClick = {
                    scope.launch {
                        isSaving = true
                        val parts = selectedTime.split(":").mapNotNull(String::toIntOrNull)
                        val scheduledAt = selectedDate
                            .atTime(parts.getOrElse(0) { 9 }, parts.getOrElse(1) { 0 })
                            .atZone(zone).toInstant()

                        runCatching {
                            appModel.repository.createPersonalActivity(
                                PersonalActivityDraft(
                                    courtId = court.id,
                                    sport = selectedSport,
                                    scheduledAt = scheduledAt,
                                    durationMinutes = durationMinutes,
                                    comment = comment,
                                ),
                            )
                        }.onSuccess {
                            haptics.success()
                            onCreated()
                            onDismiss()
                        }.onFailure(appModel::present)
                        isSaving = false
                    }
                },
            )

            if (isSaving) {
                Box(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                }
            }
        }
    }

    if (isDatePickerPresented) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = selectedDate.atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { isDatePickerPresented = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        selectedDate = Instant.ofEpochMilli(millis).atZone(ZoneId.of("UTC")).toLocalDate()
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
}

@Composable
private fun StepperButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    disabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.1f))
            .clickable(enabled = !disabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            null,
            tint = if (disabled) Color.White.copy(alpha = 0.25f) else Color.White,
            modifier = Modifier.size(15.dp),
        )
    }
}
