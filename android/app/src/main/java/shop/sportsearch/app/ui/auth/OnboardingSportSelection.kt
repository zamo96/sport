package shop.sportsearch.app.ui.auth

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreHoriz
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.components.AutoSizeText
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `localizedOnboardingSportTitle(_:)`. */
fun localizedOnboardingSportTitle(sport: Sport): String {
    val english = when (sport) {
        Sport.TENNIS -> "Tennis"
        Sport.PADEL -> "Padel"
        Sport.RUNNING -> "Running"
        Sport.SUPBOARD -> "SUP boarding"
        Sport.SQUASH -> "Squash"
        Sport.BADMINTON -> "Badminton"
        Sport.TABLE_TENNIS -> "Table tennis"
        Sport.VOLLEYBALL -> "Volleyball"
        Sport.FITNESS -> "Fitness"
        Sport.BOXING -> "Boxing"
        Sport.YOGA -> "Yoga"
        Sport.FOOTBALL -> "Football"
    }
    return L10n.string(english, sport.title)
}

/** `OnboardingSportTile.levelTone` / `OnboardingLevelPickerSheet.levelTone(_:)`. */
fun onboardingLevelTone(level: Int): String = when (level) {
    in 1..2 -> L10n.string("Beginner", "Новичок")
    in 3..4 -> L10n.string("Basic", "База")
    in 5..6 -> L10n.string("Confident", "Уверенный")
    in 7..8 -> L10n.string("Advanced", "Сильный")
    else -> L10n.string("Competitive", "Турнирный")
}

/** `OnboardingLevelPickerSheet.levelHint(_:)`. */
private fun onboardingLevelHint(level: Int): String = when (level) {
    in 1..2 -> L10n.string("just starting", "только начинаю")
    in 3..4 -> L10n.string("play occasionally", "играю иногда")
    in 5..6 -> L10n.string("solid fundamentals", "стабильная база")
    in 7..8 -> L10n.string("strong pace", "хороший темп")
    else -> L10n.string("competitive", "соревновательный")
}

/** Port of `private struct OnboardingStepProgress`. */
@Composable
fun OnboardingStepProgress(current: Int, total: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        (1..total).forEach { index ->
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(7.dp)
                    .clip(RoundedCornerShape(percent = 50))
                    .background(
                        if (index <= current) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.15f),
                    ),
            )
        }
    }
}

/** `OnboardingSportSelectionGrid.primarySports`. */
private val primarySports = listOf(Sport.TENNIS, Sport.PADEL, Sport.FOOTBALL, Sport.FITNESS, Sport.BADMINTON)

/** Port of `private struct OnboardingSportSelectionGrid`. */
@Composable
fun OnboardingSportSelectionGrid(
    sports: List<Sport>,
    levels: Map<String, Int>,
    cardHeight: Dp,
    onToggle: (Sport) -> Unit,
    onSelectLevel: (Sport) -> Unit,
) {
    val haptics = rememberAppHaptics()
    var showsAllSports by remember { mutableStateOf(false) }

    val extraSports = Sport.entries.filterNot { primarySports.contains(it) }
    val tiles = primarySports + listOf(null) + if (showsAllSports) extraSports else emptyList()

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        tiles.chunked(3).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                row.forEach { sport ->
                    if (sport == null) {
                        MoreSportsTile(showsAllSports, cardHeight, Modifier.weight(1f)) {
                            haptics.selection()
                            showsAllSports = !showsAllSports
                        }
                    } else {
                        OnboardingSportTile(
                            sport = sport,
                            isSelected = sports.contains(sport),
                            level = levels[sport.wire] ?: 5,
                            height = cardHeight,
                            modifier = Modifier.weight(1f),
                            onToggle = {
                                haptics.selection()
                                onToggle(sport)
                            },
                            onLevelTap = { onSelectLevel(sport) },
                        )
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** Port of `private struct OnboardingSportTile`. */
@Composable
private fun OnboardingSportTile(
    sport: Sport,
    isSelected: Boolean,
    level: Int,
    height: Dp,
    modifier: Modifier = Modifier,
    onToggle: () -> Unit,
    onLevelTap: () -> Unit,
) {
    val isCompact = height < 90.dp
    val shape = continuousShape(22.dp)

    Column(
        modifier = modifier
            .heightIn(min = height)
            .appShadow(
                if (isSelected) OnboardingStepPalette.lime.copy(alpha = 0.16f) else Color.Black.copy(alpha = 0.26f),
                18.dp,
                0.dp,
                10.dp,
                shape,
            )
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        Color.White.copy(alpha = if (isSelected) 0.12f else 0.08f),
                        OnboardingStepPalette.panelRaised.copy(alpha = 0.95f),
                    ),
                ),
            )
            .border(
                if (isSelected) 1.6.dp else 1.dp,
                if (isSelected) OnboardingStepPalette.lime else OnboardingStepPalette.stroke,
                shape,
            )
            .clickable(onClick = onToggle)
            .padding(horizontal = 7.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (isCompact) 5.dp else 6.dp),
    ) {
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            SportIconView(
                sport = sport,
                color = if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.88f),
                size = if (isCompact) 30.dp else 34.dp,
            )
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(7.dp, (-4).dp)
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(OnboardingStepPalette.lime),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.Check,
                        contentDescription = null,
                        tint = Color.Black.copy(alpha = 0.82f),
                        modifier = Modifier.size(12.dp),
                    )
                }
            }
        }

        AutoSizeText(
            text = localizedOnboardingSportTitle(sport),
            fontSize = (if (isCompact) 12 else 13).sp,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White,
            maxLines = 1,
            minScale = 0.75f,
            textAlign = TextAlign.Center,
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(percent = 50))
                .background(
                    if (isSelected) {
                        OnboardingStepPalette.lime.copy(alpha = 0.14f)
                    } else {
                        Color.White.copy(alpha = 0.10f)
                    },
                )
                .clickable(onClick = onLevelTap)
                .padding(horizontal = 6.dp, vertical = if (isCompact) 6.dp else 7.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AutoSizeText(
                text = if (isSelected) {
                    onboardingLevelTone(level)
                } else {
                    L10n.string("Choose level", "Выбери уровень")
                },
                fontSize = (if (isCompact) 10 else 11).sp,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.82f),
                maxLines = 1,
                minScale = 0.62f,
            )
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.82f),
                modifier = Modifier.size(8.dp),
            )
        }
    }
}

/** Port of `private struct MoreSportsTile`. */
@Composable
private fun MoreSportsTile(
    isExpanded: Boolean,
    height: Dp,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val isCompact = height < 90.dp
    val shape = continuousShape(22.dp)

    Column(
        modifier = modifier
            .heightIn(min = height)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(Color.White.copy(alpha = 0.08f), OnboardingStepPalette.panelRaised.copy(alpha = 0.95f)),
                ),
            )
            .border(1.dp, OnboardingStepPalette.stroke, shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 7.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (isCompact) 5.dp else 6.dp),
    ) {
        Box(
            modifier = Modifier
                .size(if (isCompact) 36.dp else 40.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (isExpanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.MoreHoriz,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(if (isCompact) 17.dp else 19.dp),
            )
        }

        Text(
            if (isExpanded) L10n.string("Hide", "Скрыть") else L10n.string("More", "Ещё виды"),
            fontFamily = appFontFamily,
            fontSize = (if (isCompact) 12 else 13).sp,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White,
        )

        AutoSizeText(
            text = if (isExpanded) L10n.string("Collapse", "Свернуть") else L10n.string("Open", "Открыть"),
            fontSize = (if (isCompact) 8 else 9).sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.62f),
            maxLines = 1,
            minScale = 0.72f,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(percent = 50))
                .background(Color.White.copy(alpha = 0.08f))
                .padding(horizontal = 5.dp, vertical = if (isCompact) 5.dp else 6.dp),
        )
    }
}

/** Port of `private struct OnboardingLevelPickerSheet`. */
@Composable
fun OnboardingLevelPickerSheet(level: Int, onSelect: (Int) -> Unit) {
    val haptics = rememberAppHaptics()

    Box(modifier = Modifier.fillMaxSize().background(OnboardingStepPalette.panel)) {
        OnboardingIntroBackground(Modifier.fillMaxSize())

        Column(
            modifier = Modifier
                .fillMaxSize()
                // iOS shows this as a detented sheet that never reaches the top;
                // here it is a full-screen destination, so it owns the inset.
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            (1..10).chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { value ->
                        val isSelected = value == level
                        val shape = continuousShape(18.dp)
                        Row(
                            modifier = Modifier
                                .weight(1f)
                                .clip(shape)
                                .background(Color.White.copy(alpha = if (isSelected) 0.12f else 0.07f))
                                .border(
                                    1.dp,
                                    if (isSelected) {
                                        OnboardingStepPalette.lime.copy(alpha = 0.85f)
                                    } else {
                                        Color.White.copy(alpha = 0.10f)
                                    },
                                    shape,
                                )
                                .clickable {
                                    haptics.selection()
                                    onSelect(value)
                                }
                                .padding(horizontal = 12.dp, vertical = 9.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                "$value",
                                modifier = Modifier
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(
                                        if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.10f),
                                    )
                                    .padding(top = 5.dp),
                                fontFamily = appFontFamily,
                                fontSize = 19.sp,
                                fontWeight = FontWeight.ExtraBold,
                                color = if (isSelected) Color.Black.copy(alpha = 0.86f) else Color.White,
                                textAlign = TextAlign.Center,
                            )

                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(
                                    onboardingLevelTone(value),
                                    fontFamily = appFontFamily,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.ExtraBold,
                                    color = Color.White,
                                )
                                Text(
                                    onboardingLevelHint(value),
                                    fontFamily = appFontFamily,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color.White.copy(alpha = 0.54f),
                                    maxLines = 1,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
