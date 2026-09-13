package shop.sportsearch.app.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import shop.sportsearch.app.ui.theme.AppRadius
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct PrimaryActionButtonStyle`. */
@Composable
fun PrimaryActionButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = AppTheme.ink,
    enabled: Boolean = true,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.985f else 1f, tween(180), label = "primaryScale")
    val shape = continuousShape(AppRadius.button)
    val haptics = rememberAppHaptics()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .scale(scale)
            .appShadow(
                color = tint.copy(alpha = if (pressed) 0.12f else 0.20f),
                radius = if (pressed) 10.dp else 18.dp,
                offsetY = if (pressed) 6.dp else 12.dp,
                shape = shape,
            )
            .clip(shape)
            .background(if (enabled) tint else tint.copy(alpha = 0.38f))
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                enabled = enabled,
            ) {
                haptics.impactLight()
                onClick()
            }
            .defaultMinSize(minHeight = 52.dp)
            .padding(horizontal = 18.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = AppText.subheadlineSemibold, color = Color.White, textAlign = TextAlign.Center)
    }
}

/** Port of `struct SecondaryActionButtonStyle`. */
@Composable
fun SecondaryActionButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = AppTheme.ink,
    enabled: Boolean = true,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.985f else 1f, tween(180), label = "secondaryScale")
    val shape = continuousShape(AppRadius.button)
    val haptics = rememberAppHaptics()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .scale(scale)
            .appShadow(
                color = AppTheme.ink.copy(alpha = if (pressed) 0.04f else 0.08f),
                radius = if (pressed) 10.dp else 16.dp,
                offsetY = if (pressed) 6.dp else 10.dp,
                shape = shape,
            )
            .clip(shape)
            .background(Color.White.copy(alpha = 0.76f))
            .border(1.dp, Color.White.copy(alpha = 0.7f), shape)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                enabled = enabled,
            ) {
                haptics.selection()
                onClick()
            }
            .defaultMinSize(minHeight = 52.dp)
            .padding(horizontal = 18.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = AppText.subheadlineSemibold, color = tint, textAlign = TextAlign.Center)
    }
}

/**
 * Port of `struct FieldShell`. The uppercase, letter-spaced caption above the
 * field and the cream inset well below it are what make the forms read as the
 * same app on both platforms.
 */
@Composable
fun FieldShell(
    modifier: Modifier = Modifier,
    title: String? = null,
    caption: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = continuousShape(AppRadius.field)
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (!title.isNullOrEmpty()) {
            Text(
                text = title.uppercase(),
                style = AppText.captionSemibold.copy(letterSpacing = 1.4.sp),
                color = AppTheme.ink.copy(alpha = 0.68f),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .appShadow(AppTheme.ink.copy(alpha = 0.06f), radius = 14.dp, offsetY = 8.dp, shape = shape)
                .clip(shape)
                .background(AppTheme.creamLight)
                .border(1.dp, AppTheme.court.copy(alpha = 0.16f), shape)
                .defaultMinSize(minHeight = 50.dp)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.Center,
            content = content,
        )

        if (!caption.isNullOrEmpty()) {
            Text(caption, style = AppText.caption, color = AppTheme.mutedInk)
        }
    }
}

/** Port of `struct AppSegmentedChoice`. */
@Composable
fun <T> AppSegmentedChoice(
    title: String,
    items: List<T>,
    selection: T,
    titleProvider: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = rememberAppHaptics()
    val shape = continuousShape(20.dp)

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title.uppercase(),
            style = AppText.captionSemibold.copy(letterSpacing = 1.4.sp),
            color = AppTheme.ink.copy(alpha = 0.68f),
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items.forEach { item ->
                val isSelected = item == selection
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .defaultMinSize(minHeight = 48.dp)
                        .clip(shape)
                        .background(if (isSelected) AppTheme.ink else Color.White.copy(alpha = 0.78f))
                        .border(1.dp, Color.White.copy(alpha = if (isSelected) 0.08f else 0.82f), shape)
                        .clickable {
                            haptics.selection()
                            onSelect(item)
                        }
                        .padding(horizontal = 8.dp, vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = titleProvider(item),
                        style = AppText.subheadlineSemibold,
                        color = if (isSelected) Color.White else AppTheme.ink,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}
