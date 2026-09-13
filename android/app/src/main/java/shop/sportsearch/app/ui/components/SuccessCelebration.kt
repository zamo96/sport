package shop.sportsearch.app.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.ui.theme.AppRadius
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

private data class CelebrationParticle(
    val color: Color,
    val endX: Dp,
    val endY: Dp,
    val rotation: Float,
    val width: Dp,
    val height: Dp,
)

/** Exact particle table from `SuccessCelebrationOverlay` in UIComponents.swift. */
private val particles = listOf(
    CelebrationParticle(Color(0xFF2ED978), (-132).dp, (-196).dp, -38f, 9.dp, 18.dp),
    CelebrationParticle(Color(0xFFFFD13B), (-74).dp, (-224).dp, 24f, 10.dp, 16.dp),
    CelebrationParticle(Color(0xFF4F8CFF), 92.dp, (-214).dp, 54f, 8.dp, 17.dp),
    CelebrationParticle(Color(0xFFFF5E5E), 138.dp, (-172).dp, -28f, 11.dp, 15.dp),
    CelebrationParticle(Color(0xFFAE6BFF), (-156).dp, (-86).dp, 72f, 8.dp, 14.dp),
    CelebrationParticle(Color(0xFF29C7C7), 168.dp, (-96).dp, -64f, 9.dp, 16.dp),
    CelebrationParticle(Color(0xFFFF9C2E), (-108).dp, 18.dp, 34f, 10.dp, 15.dp),
    CelebrationParticle(Color(0xFF42BD6B), 122.dp, 24.dp, -44f, 8.dp, 16.dp),
)

/**
 * Port of `struct SuccessCelebrationOverlay`: confetti flying out from behind a
 * dark card with a court-green medallion. Shown when an urgent search is published.
 */
@Composable
fun SuccessCelebrationOverlay(
    title: String,
    subtitle: String,
    icon: String,
    modifier: Modifier = Modifier,
) {
    var launched by remember { mutableStateOf(false) }
    var cardVisible by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        cardVisible = true
        launched = true
    }

    val progress by animateFloatAsState(
        targetValue = if (launched) 1f else 0f,
        animationSpec = tween(1250),
        label = "celebrationLaunch",
    )
    val cardScale by animateFloatAsState(
        targetValue = if (cardVisible) 1f else 0.86f,
        animationSpec = tween(340),
        label = "celebrationCard",
    )
    val cardAlpha by animateFloatAsState(
        targetValue = if (cardVisible) 1f else 0f,
        animationSpec = tween(340),
        label = "celebrationAlpha",
    )

    val cardShape = continuousShape(AppRadius.overlay)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.24f)),
        contentAlignment = Alignment.Center,
    ) {
        particles.forEach { particle ->
            Box(
                modifier = Modifier
                    .offset(
                        x = particle.endX * progress,
                        y = (-18).dp + (particle.endY + 18.dp) * progress,
                    )
                    .rotate(particle.rotation * progress)
                    .scale(0.2f + 0.8f * progress)
                    .size(width = particle.width, height = particle.height)
                    .graphicsLayer { alpha = 1f - progress }
                    .background(particle.color, RoundedCornerShape(4.dp)),
            )
        }

        Column(
            modifier = Modifier
                .scale(cardScale)
                .graphicsLayer { alpha = cardAlpha }
                .clip(cardShape)
                .background(Color(0xFF0D211A).copy(alpha = 0.94f))
                .border(1.dp, Color.White.copy(alpha = 0.12f), cardShape)
                .padding(horizontal = 26.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .appShadow(AppTheme.court.copy(alpha = 0.36f), 26.dp, offsetY = 16.dp, shape = CircleShape)
                        .size(96.dp)
                        .background(AppTheme.court, CircleShape),
                )
                Box(
                    Modifier
                        .size((82 + 46 * progress).dp)
                        .border(10.dp, Color.White.copy(alpha = 0.34f * (1f - progress)), CircleShape),
                )
                Text(
                    icon,
                    fontSize = 46.sp,
                    modifier = Modifier
                        .rotate(-12f * progress)
                        .offset(y = (4 - 9 * progress).dp),
                )
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    title,
                    fontSize = 21.sp,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
                Text(
                    subtitle,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.72f),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
