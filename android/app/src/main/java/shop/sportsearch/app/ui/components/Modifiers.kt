package shop.sportsearch.app.ui.components

import android.graphics.BlurMaskFilter
import android.os.Build
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * SwiftUI's `.shadow(color:radius:x:y:)`.
 *
 * Compose's own `Modifier.shadow` takes a Material elevation and derives both
 * blur and colour from it, which cannot reproduce the wide, tinted, low-opacity
 * shadows this design uses (e.g. `ink.opacity(0.08), radius: 18, y: 10`). This
 * draws the shape behind the content with a Gaussian blur instead, matching the
 * SwiftUI parameters directly.
 *
 * The Paint and its BlurMaskFilter depend only on the colour and radius, so they
 * are built once per node rather than on every frame: this modifier sits on
 * cards, buttons and the tab bar, all of which redraw throughout an animation.
 */
fun Modifier.appShadow(
    color: Color,
    radius: Dp,
    offsetX: Dp = 0.dp,
    offsetY: Dp = 0.dp,
    shape: Shape,
): Modifier = composed {
    val density = LocalDensity.current
    val paint = remember(color, radius, density) {
        val blurPx = with(density) { radius.toPx() }
        Paint().also { paint ->
            if (blurPx > 0f && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // SwiftUI's radius is a Gaussian sigma; BlurMaskFilter takes the same.
                paint.color = color
                paint.asFrameworkPaint().maskFilter = BlurMaskFilter(blurPx, BlurMaskFilter.Blur.NORMAL)
            } else {
                // API 26-27 cannot blur on a hardware canvas, so the shadow is
                // approximated with a softer solid pass instead of vanishing.
                paint.color = color.copy(alpha = color.alpha * 0.5f)
            }
        }
    }

    drawBehind {
        if (color.alpha == 0f || size.width <= 0f || size.height <= 0f) return@drawBehind

        val outline: Outline = shape.createOutline(Size(size.width, size.height), layoutDirection, this)

        drawIntoCanvas { canvas ->
            canvas.save()
            canvas.translate(offsetX.toPx(), offsetY.toPx())
            canvas.drawOutline(outline, paint)
            canvas.restore()
        }
    }
}
