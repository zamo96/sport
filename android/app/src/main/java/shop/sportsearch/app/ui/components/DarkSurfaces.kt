package shop.sportsearch.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * The dark surfaces the tab screens are built from. Discover, Matches, Searches
 * and Courts all run on black with these panels; the values come from
 * MatchesView.swift (`matchesInboxList`, `matchesHeader`, `matchesFilterRail`).
 */

/** `matchesHeader`: 42pt white title over a 14pt muted subtitle. */
@Composable
fun DarkScreenHeader(title: String, subtitle: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, fontSize = 42.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text(subtitle, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.62f))
    }
}

/** Section heading used above every dark list: 18pt bold plus a count pill. */
@Composable
fun DarkSectionHeader(
    title: String,
    count: Int? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White)
        if (count != null && count > 0) {
            Text(
                count.toString(),
                style = AppText.captionBold,
                color = AppTheme.court,
                modifier = Modifier
                    .background(AppTheme.court.copy(alpha = 0.18f), RoundedCornerShape(percent = 50))
                    .padding(horizontal = 9.dp, vertical = 5.dp),
            )
        }
    }
}

/** `matchesInboxList` container: a barely-there white gradient on black. */
@Composable
fun DarkListContainer(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(Color.White.copy(alpha = 0.075f), Color.White.copy(alpha = 0.035f)),
                ),
            )
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape),
        content = content,
    )
}

@Composable
fun DarkDivider(startIndent: androidx.compose.ui.unit.Dp = 92.dp) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = startIndent)
            .height(1.dp)
            .background(Color.White.copy(alpha = 0.08f)),
    )
}

/** A single dark card, used where a list has one item per panel. */
@Composable
fun DarkCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(Color.White.copy(alpha = 0.075f), Color.White.copy(alpha = 0.035f)),
                ),
            )
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        content = content,
    )
}

/** `matchesFilterRail`: a horizontally scrolling row of selectable pills. */
@Composable
fun <T> DarkFilterRail(
    items: List<T>,
    selected: T?,
    titleOf: (T) -> String,
    countOf: (T) -> Int? = { null },
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = rememberAppHaptics()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items.forEach { item ->
            val isSelected = item == selected
            val shape = continuousShape(22.dp)
            Row(
                modifier = Modifier
                    .clip(shape)
                    .background(if (isSelected) Color.White else Color.White.copy(alpha = 0.08f))
                    .border(1.dp, Color.White.copy(alpha = if (isSelected) 0.0f else 0.10f), shape)
                    .clickable {
                        haptics.selection()
                        onSelect(item)
                    }
                    .padding(horizontal = 14.dp, vertical = 11.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    titleOf(item),
                    style = AppText.subheadlineSemibold,
                    color = if (isSelected) AppTheme.ink else Color.White.copy(alpha = 0.86f),
                )
                countOf(item)?.takeIf { it > 0 }?.let { count ->
                    Text(
                        count.toString(),
                        style = AppText.caption2Semibold,
                        color = if (isSelected) AppTheme.court else Color.White.copy(alpha = 0.6f),
                    )
                }
            }
        }
    }
}

/** Empty state on the dark screens, matching `EmptyStateView` but inverted. */
@Composable
fun DarkEmptyState(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
) {
    DarkCard(modifier = modifier) {
        Text(title, style = AppText.title3Semibold, color = Color.White)
        Text(subtitle, style = AppText.subheadline, color = Color.White.copy(alpha = 0.6f))
    }
}
