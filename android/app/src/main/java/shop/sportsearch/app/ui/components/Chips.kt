package shop.sportsearch.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import kotlin.math.ceil

private val Capsule = RoundedCornerShape(percent = 50)

/** Port of `struct PillLabel`. */
@Composable
fun PillLabel(
    text: String,
    modifier: Modifier = Modifier,
    tint: Color = AppTheme.clay,
) {
    Text(
        text = text,
        style = AppText.captionSemibold,
        color = tint,
        modifier = modifier
            .background(tint.copy(alpha = 0.12f), Capsule)
            .padding(horizontal = 10.dp, vertical = 8.dp),
    )
}

/** Port of `struct AppInlineChip`. */
@Composable
fun AppInlineChip(
    text: String,
    tint: Color,
    foreground: Color,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        style = AppText.captionSemibold,
        color = foreground,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        textAlign = TextAlign.Center,
        modifier = modifier
            .background(tint, Capsule)
            .padding(horizontal = 10.dp, vertical = 8.dp),
    )
}

/** Port of `struct SportLevelMiniChip`. */
@Composable
fun SportLevelMiniChip(
    sport: Sport,
    level: Int?,
    modifier: Modifier = Modifier,
) {
    val resolvedLevel = (level ?: 5).coerceIn(1, 10)
    val tone = when (resolvedLevel) {
        1, 2 -> "Новичок"
        3, 4 -> "База"
        5, 6 -> "Уверенный"
        7, 8 -> "Сильный"
        else -> "Турнирный"
    }
    val filledBars = ceil(resolvedLevel / 2.0).toInt()

    Row(
        modifier = modifier
            .background(AppTheme.cream, Capsule)
            .border(1.dp, Color.White.copy(alpha = 0.75f), Capsule)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(sport.title, style = AppText.captionBold, color = AppTheme.ink)

        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            (1..5).forEach { index ->
                Box(
                    modifier = Modifier
                        .size(width = 8.dp, height = 5.dp)
                        .background(
                            if (index <= filledBars) AppTheme.court else AppTheme.ink.copy(alpha = 0.14f),
                            CircleShape,
                        ),
                )
            }
        }

        Text(tone, style = AppText.caption2Semibold, color = AppTheme.ink.copy(alpha = 0.62f))
    }
}
