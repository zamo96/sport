package shop.sportsearch.app.ui.discover

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct InlineToast`. */
@Composable
fun InlineToast(message: String) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .appShadow(AppTheme.ink.copy(alpha = 0.18f), 18.dp, 0.dp, 12.dp, shape)
            .clip(shape)
            .background(AppTheme.ink.copy(alpha = 0.92f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
        Text(
            message,
            style = AppText.subheadlineSemibold,
            color = Color.White,
            modifier = Modifier.weight(1f),
        )
    }
}

/** Port of `struct MatchSuccessToast`. */
@Composable
fun MatchSuccessToast(message: String) {
    val shape = continuousShape(20.dp)
    val transition = rememberInfiniteTransition(label = "matchToast")
    val bounce by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(460), RepeatMode.Reverse),
        label = "bounce",
    )

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .appShadow(Color.Black.copy(alpha = 0.24f), 18.dp, 0.dp, 12.dp, shape)
            .clip(shape)
            .background(
                Brush.linearGradient(listOf(Color(0xFF122C1F), Color(0xFF1A4D33))),
            )
            .border(1.2.dp, Color(0xFF5EC78F).copy(alpha = 0.8f), shape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(42.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(
                modifier = Modifier
                    .size(26.dp)
                    .graphicsLayer {
                        translationY = (bounce * 8f - 4f) * density
                        rotationZ = bounce * 24f - 12f
                    },
            ) { drawTennisBall() }
        }

        Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
            Text(
                L10n.string("New match", "Новый мэтч").uppercase(),
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 1.4.sp,
                color = Color(0xFFC2F7CC),
            )
            Text(
                message,
                style = AppText.subheadlineSemibold,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * `struct TennisBallIcon` - a lime circle with two trimmed elliptical seams.
 *
 * The seams are `Ellipse().trim(from: 0.2, to: 0.8)`, i.e. the middle 60% of the
 * ellipse's outline; PathMeasure gives the same sub-path here.
 */
private fun DrawScope.drawTennisBall() {
    val d = size.minDimension
    val radius = d / 2f
    drawCircle(Color(0xFFD6FA57), radius = radius)
    drawCircle(Color.White.copy(alpha = 0.92f), radius = radius, style = Stroke(width = 1.4f * d / 26f))

    // The stripes are laid out for a 26pt icon on iOS; scale everything from there.
    val scale = d / 26f
    listOf(-6f, 6f).forEach { offsetX ->
        drawBallStripe(offsetX * scale, 18f * scale, 28f * scale, 2.1f * scale)
    }
}

private fun DrawScope.drawBallStripe(offsetX: Float, width: Float, height: Float, strokeWidth: Float) {
    val oval = Path().apply {
        addOval(
            Rect(
                offset = Offset(center.x - width / 2f + offsetX, center.y - height / 2f),
                size = Size(width, height),
            ),
        )
    }
    val measure = PathMeasure().apply { setPath(oval, false) }
    val trimmed = Path()
    measure.getSegment(measure.length * 0.2f, measure.length * 0.8f, trimmed, true)
    drawPath(
        trimmed,
        Color.White.copy(alpha = 0.95f),
        style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
    )
}
