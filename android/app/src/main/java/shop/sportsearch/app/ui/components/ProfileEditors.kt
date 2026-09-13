package shop.sportsearch.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.DayOfWeek
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.TimeRange
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import kotlin.math.ceil

/**
 * Ports of `AppSportSelectionGrid`, `AppSportSelectionCard`,
 * `AppSingleSportSelectionGrid`, `AppAvailabilityWeekEditor` and
 * `AppAvailabilityWindowCard` in ios/TennisSearchIOS/Views/UIComponents.swift.
 *
 * As in the Swift originals, several strings here are hard-coded Russian
 * instead of going through `L10n`; kept as-is so both clients read the same.
 */

private fun levelTone(level: Int): String = when (level) {
    1, 2 -> "Новичок"
    3, 4 -> "База"
    5, 6 -> "Уверенный"
    7, 8 -> "Сильный"
    else -> "Турнирный"
}

@Composable
fun AppSportSelectionGrid(
    title: String,
    sports: List<Sport>,
    selectedSports: List<Sport>,
    levels: Map<String, Int>,
    onSelectedSportsChange: (List<Sport>) -> Unit,
    onLevelsChange: (Map<String, Int>) -> Unit,
) {
    val haptics = rememberAppHaptics()

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            title.uppercase(),
            style = AppText.captionSemibold.copy(letterSpacing = 1.4.sp),
            color = AppTheme.ink.copy(alpha = 0.68f),
        )

        // LazyVGrid with two flexible columns; a plain Column of Rows keeps this
        // usable inside the outer vertical scroll.
        sports.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { sport ->
                    AppSportSelectionCard(
                        sport = sport,
                        isSelected = selectedSports.contains(sport),
                        level = levels[sport.wire] ?: 5,
                        onLevelChange = { onLevelsChange(levels + (sport.wire to it)) },
                        modifier = Modifier.weight(1f),
                        onToggle = {
                            haptics.selection()
                            if (selectedSports.contains(sport)) {
                                onSelectedSportsChange(selectedSports.filterNot { it == sport })
                                onLevelsChange(levels - sport.wire)
                            } else {
                                onSelectedSportsChange(selectedSports + sport)
                                onLevelsChange(levels + (sport.wire to (levels[sport.wire] ?: 5)))
                            }
                        },
                    )
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun AppSportSelectionCard(
    sport: Sport,
    isSelected: Boolean,
    level: Int,
    onLevelChange: (Int) -> Unit,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = continuousShape(24.dp)

    Column(
        modifier = modifier
            .appShadow(
                AppTheme.ink.copy(alpha = if (isSelected) 0.14f else 0.05f),
                radius = if (isSelected) 18.dp else 10.dp,
                offsetY = if (isSelected) 14.dp else 8.dp,
                shape = shape,
            )
            .clip(shape)
            .background(
                if (isSelected) {
                    Brush.linearGradient(listOf(AppTheme.court, AppTheme.ink))
                } else {
                    Brush.verticalGradient(
                        listOf(Color.White.copy(alpha = 0.92f), AppTheme.creamLight.copy(alpha = 0.95f)),
                    )
                },
            )
            .border(1.dp, Color.White.copy(alpha = if (isSelected) 0.16f else 0.74f), shape)
            .clickable(onClick = onToggle)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(continuousShape(14.dp))
                    .background(if (isSelected) Color.White.copy(alpha = 0.16f) else Color.White),
                contentAlignment = Alignment.Center,
            ) {
                SportIconView(
                    sport = sport,
                    color = if (isSelected) Color.White else AppTheme.court,
                    size = 18.dp,
                )
            }

            Text(
                sport.title,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) Color.White else AppTheme.ink,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Text(
            "Добавь в свои виды спорта",
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = if (isSelected) Color.White.copy(alpha = 0.76f) else AppTheme.mutedInk,
        )

        AnimatedVisibility(visible = isSelected) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Уровень",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.72f),
                    )
                    Spacer(Modifier.weight(1f))
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.14f))
                            .padding(horizontal = 9.dp, vertical = 5.dp),
                    ) {
                        Text(levelTone(level), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    LevelButton("−") { onLevelChange(maxOf(1, level - 1)) }
                    Row(
                        modifier = Modifier.weight(1f),
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        (1..10).forEach { index ->
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(8.dp)
                                    .clip(CircleShape)
                                    .background(
                                        if (index <= level) {
                                            Color.White.copy(alpha = 0.9f)
                                        } else {
                                            Color.White.copy(alpha = 0.16f)
                                        },
                                    ),
                            )
                        }
                    }
                    LevelButton("+") { onLevelChange(minOf(10, level + 1)) }
                }
            }
        }
    }
}

@Composable
private fun LevelButton(symbol: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(28.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.18f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(symbol, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}

/** Port of `struct AppSingleSportSelectionGrid`. */
@Composable
fun AppSingleSportSelectionGrid(
    title: String,
    sports: List<Sport>,
    selectedSport: Sport,
    levelProvider: (Sport) -> Int?,
    onSelect: (Sport) -> Unit,
) {
    val haptics = rememberAppHaptics()

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            title.uppercase(),
            style = AppText.captionSemibold.copy(letterSpacing = 1.4.sp),
            color = AppTheme.ink.copy(alpha = 0.68f),
        )

        sports.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { sport ->
                    val isSelected = selectedSport == sport
                    val shape = continuousShape(24.dp)
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .height(156.dp)
                            .appShadow(
                                AppTheme.ink.copy(alpha = if (isSelected) 0.14f else 0.05f),
                                radius = if (isSelected) 18.dp else 10.dp,
                                offsetY = if (isSelected) 14.dp else 8.dp,
                                shape = shape,
                            )
                            .clip(shape)
                            .background(
                                if (isSelected) {
                                    Brush.linearGradient(listOf(AppTheme.court, AppTheme.ink))
                                } else {
                                    Brush.verticalGradient(
                                        listOf(
                                            Color.White.copy(alpha = 0.92f),
                                            AppTheme.creamLight.copy(alpha = 0.95f),
                                        ),
                                    )
                                },
                            )
                            .border(1.dp, Color.White.copy(alpha = if (isSelected) 0.16f else 0.74f), shape)
                            .clickable {
                                if (selectedSport != sport) {
                                    onSelect(sport)
                                    haptics.selection()
                                }
                            }
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(34.dp)
                                    .clip(continuousShape(14.dp))
                                    .background(if (isSelected) Color.White.copy(alpha = 0.16f) else Color.White),
                                contentAlignment = Alignment.Center,
                            ) {
                                SportIconView(
                                    sport = sport,
                                    color = if (isSelected) Color.White else AppTheme.court,
                                    size = 18.dp,
                                )
                            }
                            Text(
                                sport.title,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isSelected) Color.White else AppTheme.ink,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }

                        val level = levelProvider(sport)
                        if (level != null) {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                    val filled = ceil(level / 2.0).toInt()
                                    (1..5).forEach { index ->
                                        Box(
                                            modifier = Modifier
                                                .weight(1f)
                                                .height(6.dp)
                                                .clip(CircleShape)
                                                .background(
                                                    when {
                                                        index <= filled && isSelected -> Color.White
                                                        index <= filled -> AppTheme.court
                                                        isSelected -> Color.White.copy(alpha = 0.18f)
                                                        else -> AppTheme.ink.copy(alpha = 0.12f)
                                                    },
                                                ),
                                        )
                                    }
                                }
                                Text(
                                    levelTone(level),
                                    style = AppText.caption2Semibold,
                                    color = if (isSelected) Color.White.copy(alpha = 0.82f) else AppTheme.mutedInk,
                                    maxLines = 1,
                                )
                            }
                        } else {
                            Text(
                                "Выбрать спорт",
                                style = AppText.captionSemibold,
                                color = if (isSelected) Color.White.copy(alpha = 0.82f) else AppTheme.mutedInk,
                            )
                        }

                        if (isSelected) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(
                                    Icons.Filled.CheckCircle,
                                    null,
                                    tint = Color.White,
                                    modifier = Modifier.size(15.dp),
                                )
                                Text("Выбрано", style = AppText.captionBold, color = Color.White)
                            }
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** Port of `struct AppAvailabilityWeekEditor`. */
@Composable
fun AppAvailabilityWeekEditor(
    availabilityByDay: Map<String, List<String>>,
    onChange: (Map<String, List<String>>) -> Unit,
    /** `DetailedAvailabilityEditor` prefixes the onboarding copy of this editor. */
    caption: String? = null,
) {
    val haptics = rememberAppHaptics()
    var activeDay by remember { mutableStateOf(DayOfWeek.MONDAY) }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (caption != null) {
            Text(caption, style = AppText.caption, color = AppTheme.mutedInk)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DayOfWeek.entries.forEach { day ->
                val ranges = availabilityByDay[day.wire].orEmpty()
                val isActive = activeDay == day
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clip(continuousShape(18.dp))
                        .background(if (isActive) AppTheme.ink else AppTheme.cream)
                        .clickable {
                            activeDay = day
                            haptics.selection()
                        }
                        .padding(vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        day.shortTitle,
                        style = AppText.subheadlineSemibold,
                        color = if (isActive) Color.White else AppTheme.ink,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        TimeRange.entries.forEach { range ->
                            Box(
                                modifier = Modifier
                                    .size(5.dp)
                                    .clip(CircleShape)
                                    .background(
                                        when {
                                            ranges.contains(range.wire) && isActive -> Color.White
                                            ranges.contains(range.wire) -> AppTheme.court
                                            isActive -> Color.White.copy(alpha = 0.24f)
                                            else -> AppTheme.ink.copy(alpha = 0.12f)
                                        },
                                    ),
                            )
                        }
                    }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(activeDay.title, style = AppText.headline, color = AppTheme.ink)
                Spacer(Modifier.weight(1f))
                if (availabilityByDay[activeDay.wire].orEmpty().isNotEmpty()) {
                    Text(
                        "Очистить",
                        style = AppText.captionSemibold,
                        color = AppTheme.clay,
                        modifier = Modifier.clickable {
                            onChange(availabilityByDay + (activeDay.wire to emptyList()))
                            haptics.selection()
                        },
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TimeRange.entries.forEach { range ->
                    AppAvailabilityWindowCard(
                        range = range,
                        isSelected = availabilityByDay[activeDay.wire].orEmpty().contains(range.wire),
                        modifier = Modifier.weight(1f),
                    ) {
                        val current = availabilityByDay[activeDay.wire].orEmpty()
                        val next = if (current.contains(range.wire)) {
                            current.filterNot { it == range.wire }
                        } else {
                            (current + range.wire).distinct()
                        }
                        onChange(availabilityByDay + (activeDay.wire to next))
                        haptics.selection()
                    }
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            fun applyPreset(days: List<DayOfWeek>, ranges: List<TimeRange>) {
                val raw = ranges.map { it.wire }
                onChange(availabilityByDay + days.associate { it.wire to raw })
                haptics.selection()
            }

            PresetButton(L10n.string("Weekday mornings", "Будни утром")) {
                applyPreset(
                    listOf(
                        DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
                        DayOfWeek.THURSDAY, DayOfWeek.FRIDAY,
                    ),
                    listOf(TimeRange.MORNING),
                )
            }
            PresetButton(L10n.string("Weekday evenings", "Будни вечером")) {
                applyPreset(
                    listOf(
                        DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
                        DayOfWeek.THURSDAY, DayOfWeek.FRIDAY,
                    ),
                    listOf(TimeRange.EVENING),
                )
            }
            PresetButton(L10n.string("Weekends", "Выходные")) {
                applyPreset(listOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY), TimeRange.entries.toList())
            }
        }
    }
}

@Composable
private fun PresetButton(title: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(AppTheme.cream)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        // SwiftUI sizes these to their text; Compose would wrap the longest label.
        Text(
            title,
            style = AppText.captionSemibold,
            color = AppTheme.ink,
            maxLines = 1,
            softWrap = false,
        )
    }
}

/** Port of `struct AppAvailabilityWindowCard`. */
@Composable
fun AppAvailabilityWindowCard(
    range: TimeRange,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = continuousShape(18.dp)

    val activeText = when (range) {
        TimeRange.MORNING -> Color(red = 0.54f, green = 0.29f, blue = 0.13f)
        TimeRange.DAY -> Color(red = 0.54f, green = 0.35f, blue = 0f)
        TimeRange.EVENING -> Color(red = 0.2f, green = 0.3f, blue = 0.48f)
    }
    val textColor = if (isSelected) activeText else activeText.copy(alpha = 0.8f)

    val background = when (range) {
        TimeRange.MORNING -> if (isSelected) {
            listOf(Color(red = 1f, green = 0.95f, blue = 0.84f), Color(red = 1f, green = 0.86f, blue = 0.7f))
        } else {
            listOf(Color(red = 1f, green = 0.98f, blue = 0.92f), Color(red = 1f, green = 0.93f, blue = 0.84f))
        }
        TimeRange.DAY -> if (isSelected) {
            listOf(Color(red = 1f, green = 0.97f, blue = 0.8f), Color(red = 1f, green = 0.91f, blue = 0.57f))
        } else {
            listOf(Color(red = 1f, green = 0.98f, blue = 0.89f), Color(red = 1f, green = 0.95f, blue = 0.78f))
        }
        TimeRange.EVENING -> if (isSelected) {
            listOf(Color(red = 0.89f, green = 0.92f, blue = 1f), Color(red = 0.79f, green = 0.84f, blue = 1f))
        } else {
            listOf(Color(red = 0.96f, green = 0.97f, blue = 1f), Color(red = 0.91f, green = 0.93f, blue = 1f))
        }
    }

    val icon = when (range) {
        TimeRange.MORNING -> Icons.Filled.WbTwilight
        TimeRange.DAY -> Icons.Filled.LightMode
        TimeRange.EVENING -> Icons.Filled.Bedtime
    }

    Column(
        modifier = modifier
            .appShadow(
                activeText.copy(alpha = if (isSelected) 0.15f else 0.06f),
                radius = if (isSelected) 16.dp else 8.dp,
                offsetY = if (isSelected) 12.dp else 6.dp,
                shape = shape,
            )
            .clip(shape)
            .background(Brush.verticalGradient(background))
            .border(1.dp, Color.White.copy(alpha = if (isSelected) 0.2f else 0.82f), shape)
            .clickable(onClick = onClick)
            .padding(vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.76f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = textColor, modifier = Modifier.size(18.dp))
        }
        Text(range.title, style = AppText.captionBold, color = textColor)
    }
}
