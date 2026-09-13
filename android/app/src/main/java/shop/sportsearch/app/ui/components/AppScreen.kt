package shop.sportsearch.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.ui.theme.AppRadius
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `struct AppScreen`: the cream gradient page plus the two blurred
 * accent blobs that sit behind every screen.
 */
@Composable
fun AppScreen(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(AppTheme.pageBackground),
    ) {
        // SwiftUI blurs a solid circle by 40pt; a radial fade reproduces the
        // same soft blob and, unlike Modifier.blur, works below API 31.
        BlurredBlob(
            color = AppTheme.clay.copy(alpha = 0.18f),
            diameter = 280.dp,
            offsetX = 110.dp,
            offsetY = (-260).dp,
        )
        BlurredBlob(
            color = AppTheme.court.copy(alpha = 0.14f),
            diameter = 220.dp,
            offsetX = (-120).dp,
            offsetY = 260.dp,
        )

        content()
    }
}

@Composable
private fun BoxScope.BlurredBlob(
    color: Color,
    diameter: androidx.compose.ui.unit.Dp,
    offsetX: androidx.compose.ui.unit.Dp,
    offsetY: androidx.compose.ui.unit.Dp,
) {
    Box(
        modifier = Modifier
            .align(Alignment.Center)
            .offset(x = offsetX, y = offsetY)
            .size(diameter * 1.6f)
            .background(
                brush = Brush.radialGradient(
                    0.0f to color,
                    0.34f to color,
                    1.0f to Color.Transparent,
                ),
                shape = CircleShape,
            ),
    )
}

/** Port of `struct SectionCard`. */
@Composable
fun SectionCard(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = continuousShape(AppRadius.card)
    Column(
        modifier = modifier
            .appShadow(AppTheme.ink.copy(alpha = 0.08f), radius = 18.dp, offsetY = 10.dp, shape = shape)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.86f))
            .border(1.dp, AppTheme.line, shape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = AppText.headline, color = AppTheme.ink)
            if (!subtitle.isNullOrEmpty()) {
                Text(subtitle, style = AppText.subheadline, color = AppTheme.ink.copy(alpha = 0.62f))
            }
        }
        content()
    }
}

/** Port of `struct EmptyStateView`. */
@Composable
fun EmptyStateView(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit,
) {
    val shape = continuousShape(AppRadius.card)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.78f))
            .border(1.dp, AppTheme.line, shape)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        icon()
        Text(title, style = AppText.title3Semibold, color = AppTheme.ink, textAlign = TextAlign.Center)
        Text(
            subtitle,
            style = AppText.subheadline,
            color = AppTheme.ink.copy(alpha = 0.62f),
            textAlign = TextAlign.Center,
        )
    }
}

/** Port of `struct LoadingOverlay`. */
@Composable
fun LoadingOverlay(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.08f)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .clip(continuousShape(22.dp))
                .background(Color.White.copy(alpha = 0.72f))
                .padding(18.dp),
        ) {
            CircularProgressIndicator(color = AppTheme.clay, strokeWidth = 3.dp)
        }
    }
}
