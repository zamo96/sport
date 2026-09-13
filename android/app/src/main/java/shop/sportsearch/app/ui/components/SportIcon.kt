package shop.sportsearch.app.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.SelfImprovement
import androidx.compose.material.icons.filled.SportsMma
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.SportsVolleyball
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.theme.AppTheme
import kotlin.math.max

/**
 * Port of `struct SportIconView`.
 *
 * Table tennis, padel and badminton are hand-drawn on iOS because SF Symbols
 * has nothing close; those three paths are reproduced here verbatim. The rest
 * map their SF Symbol onto the nearest Material icon.
 */
@Composable
fun SportIconView(
    sport: Sport,
    modifier: Modifier = Modifier,
    color: Color = AppTheme.court,
    size: Dp = 24.dp,
) {
    Box(modifier = modifier.size(size)) {
        when (sport) {
            Sport.TABLE_TENNIS -> Canvas(Modifier.size(size)) { drawTableTennis(color) }
            Sport.PADEL -> Canvas(Modifier.size(size)) { drawPadel(color) }
            Sport.BADMINTON -> Canvas(Modifier.size(size)) { drawBadminton(color) }
            else -> Icon(
                imageVector = sport.materialIcon,
                contentDescription = sport.title,
                tint = color,
                modifier = Modifier.size(size),
            )
        }
    }
}

/** Android stand-ins for `Sport.appSystemIconName`. */
val Sport.materialIcon: ImageVector
    get() = when (this) {
        // "figure.table.tennis" / "tennis.racket" - drawn by hand above, this is only a fallback.
        Sport.TABLE_TENNIS, Sport.PADEL, Sport.BADMINTON -> Icons.Filled.SportsTennis
        Sport.TENNIS -> Icons.Filled.SportsTennis          // tennis.racket
        Sport.SQUASH -> Icons.Filled.SportsTennis          // figure.racquetball
        Sport.VOLLEYBALL -> Icons.Filled.SportsVolleyball  // volleyball
        Sport.FITNESS -> Icons.Filled.FitnessCenter        // dumbbell
        Sport.BOXING -> Icons.Filled.SportsMma             // figure.boxing
        Sport.YOGA -> Icons.Filled.SelfImprovement         // figure.mind.and.body
        Sport.FOOTBALL -> Icons.Filled.SportsSoccer        // soccerball
        Sport.RUNNING -> Icons.AutoMirrored.Filled.DirectionsRun        // figure.run
        Sport.SUPBOARD -> Icons.Filled.Waves               // water.waves
    }

// MARK: - Hand-drawn icons

private fun DrawScope.drawTableTennis(color: Color) {
    val s = size.minDimension
    val center = Offset(size.width / 2f, size.height / 2f)

    tableTennisRacket(color, s, center, rotation = -34f, dx = -0.14f, dy = 0.02f)
    tableTennisRacket(color, s, center, rotation = 34f, dx = 0.14f, dy = 0.02f)

    drawCircle(
        color = color,
        radius = s * 0.13f / 2f,
        center = center + Offset(s * 0.34f, -s * 0.23f),
    )
}

private fun DrawScope.tableTennisRacket(
    color: Color,
    s: Float,
    center: Offset,
    rotation: Float,
    dx: Float,
    dy: Float,
) {
    val pivot = center + Offset(s * dx, s * dy)
    rotate(rotation, pivot) {
        val strokeWidth = max(1.4f * density, s * 0.075f)
        drawCircle(
            color = color,
            radius = (s * 0.35f - strokeWidth) / 2f,
            center = pivot + Offset(0f, -s * 0.11f),
            style = Stroke(width = strokeWidth),
        )
        val handleWidth = s * 0.08f
        val handleHeight = s * 0.30f
        val handleCenter = pivot + Offset(0f, s * 0.14f)
        drawRoundRect(
            color = color,
            topLeft = Offset(handleCenter.x - handleWidth / 2f, handleCenter.y - handleHeight / 2f),
            size = Size(handleWidth, handleHeight),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(handleWidth / 2f),
        )
    }
}

private fun DrawScope.drawPadel(color: Color) {
    val s = size.minDimension
    val center = Offset(size.width / 2f, size.height / 2f)

    rotate(28f, center) {
        val strokeWidth = max(1.5f * density, s * 0.075f)
        val headWidth = s * 0.44f
        val headHeight = s * 0.56f
        val headCenter = center + Offset(0f, -s * 0.10f)
        drawRoundRect(
            color = color,
            topLeft = Offset(headCenter.x - headWidth / 2f, headCenter.y - headHeight / 2f),
            size = Size(headWidth, headHeight),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(s * 0.17f),
            style = Stroke(width = strokeWidth),
        )

        val holeX = floatArrayOf(-0.09f, 0.06f, -0.02f, 0.12f, -0.12f, 0.02f)
        val holeY = floatArrayOf(-0.21f, -0.18f, -0.08f, -0.03f, 0.03f, 0.09f)
        for (index in 0 until 6) {
            drawCircle(
                color = color.copy(alpha = 0.88f),
                radius = s * 0.052f / 2f,
                center = center + Offset(holeX[index] * s, holeY[index] * s),
            )
        }

        val handleWidth = s * 0.09f
        val handleHeight = s * 0.34f
        val handleCenter = center + Offset(0f, s * 0.24f)
        drawRoundRect(
            color = color,
            topLeft = Offset(handleCenter.x - handleWidth / 2f, handleCenter.y - handleHeight / 2f),
            size = Size(handleWidth, handleHeight),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(handleWidth / 2f),
        )
    }

    drawCircle(
        color = color.copy(alpha = 0.92f),
        radius = s * 0.13f / 2f,
        center = center + Offset(-s * 0.34f, -s * 0.22f),
    )
}

private fun DrawScope.drawBadminton(color: Color) {
    val width = size.width
    val height = size.height
    val lineWidth = max(1.3f * density, width * 0.065f)
    val corkRect = Rect(
        offset = Offset(width * 0.37f, height * 0.66f),
        size = Size(width * 0.28f, height * 0.18f),
    )

    val base = Offset(width * 0.50f, height * 0.66f)
    val feathers = Path().apply {
        moveTo(width * 0.16f, height * 0.14f)
        lineTo(base.x, base.y)
        lineTo(width * 0.84f, height * 0.14f)
        moveTo(width * 0.30f, height * 0.18f)
        lineTo(base.x, base.y)
        moveTo(width * 0.50f, height * 0.10f)
        lineTo(base.x, base.y)
        moveTo(width * 0.70f, height * 0.18f)
        lineTo(base.x, base.y)
    }
    drawPath(
        path = feathers,
        color = color,
        style = Stroke(width = lineWidth, cap = StrokeCap.Round, join = StrokeJoin.Round),
    )

    val rim = Path().apply {
        moveTo(width * 0.16f, height * 0.14f)
        quadraticTo(width * 0.50f, height * 0.30f, width * 0.84f, height * 0.14f)
    }
    drawPath(
        path = rim,
        color = color.copy(alpha = 0.68f),
        style = Stroke(width = lineWidth * 0.8f, cap = StrokeCap.Round),
    )

    rotate(-18f, corkRect.center) {
        drawRoundRect(
            color = color,
            topLeft = corkRect.topLeft,
            size = corkRect.size,
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(corkRect.height / 2f),
        )
    }
}
