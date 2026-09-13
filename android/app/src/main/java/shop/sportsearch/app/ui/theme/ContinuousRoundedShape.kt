package shop.sportsearch.app.ui.theme

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import kotlin.math.min

/**
 * `RoundedRectangle(cornerRadius: r, style: .continuous)` from SwiftUI.
 *
 * Compose's [androidx.compose.foundation.shape.RoundedCornerShape] draws a
 * circular arc; Apple's continuous style draws a squircle whose curvature ramps
 * in over roughly 1.53x the radius along each edge. Using a circular corner
 * against the iOS build is visibly different at the 22-32dp radii this app uses,
 * so the corner is reproduced with the same cubic segments Core Animation emits.
 */
class ContinuousRoundedCornerShape(private val radius: Dp) : Shape {

    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val requested = with(density) { radius.toPx() }
        // Apple clamps the squircle back to a circular corner once the radius
        // no longer fits the extended curve; clamping the radius keeps the path
        // well formed at the same point.
        val r = min(requested, min(size.width, size.height) / (2f * EDGE))
        if (r <= 0f) {
            return Outline.Rectangle(androidx.compose.ui.geometry.Rect(0f, 0f, size.width, size.height))
        }

        val w = size.width
        val h = size.height
        val path = Path().apply {
            // top edge -> top-right corner
            moveTo(EDGE * r, 0f)
            lineTo(w - EDGE * r, 0f)
            cubicTo(w - C1 * r, 0f, w - C2 * r, 0f, w - C3 * r, C4 * r)
            cubicTo(w - C5 * r, C6 * r, w - C6 * r, C5 * r, w - C4 * r, C3 * r)
            cubicTo(w, C2 * r, w, C1 * r, w, EDGE * r)

            // right edge -> bottom-right corner
            lineTo(w, h - EDGE * r)
            cubicTo(w, h - C1 * r, w, h - C2 * r, w - C4 * r, h - C3 * r)
            cubicTo(w - C6 * r, h - C5 * r, w - C5 * r, h - C6 * r, w - C3 * r, h - C4 * r)
            cubicTo(w - C2 * r, h, w - C1 * r, h, w - EDGE * r, h)

            // bottom edge -> bottom-left corner
            lineTo(EDGE * r, h)
            cubicTo(C1 * r, h, C2 * r, h, C3 * r, h - C4 * r)
            cubicTo(C5 * r, h - C6 * r, C6 * r, h - C5 * r, C4 * r, h - C3 * r)
            cubicTo(0f, h - C2 * r, 0f, h - C1 * r, 0f, h - EDGE * r)

            // left edge -> top-left corner
            lineTo(0f, EDGE * r)
            cubicTo(0f, C1 * r, 0f, C2 * r, C4 * r, C3 * r)
            cubicTo(C6 * r, C5 * r, C5 * r, C6 * r, C3 * r, C4 * r)
            cubicTo(C2 * r, 0f, C1 * r, 0f, EDGE * r, 0f)

            close()
        }
        return Outline.Generic(path)
    }

    override fun equals(other: Any?): Boolean =
        other is ContinuousRoundedCornerShape && other.radius == radius

    override fun hashCode(): Int = radius.hashCode()

    private companion object {
        // Control-point ratios of the iOS continuous corner, as multiples of the radius.
        const val EDGE = 1.52866483f
        const val C1 = 1.08849323f
        const val C2 = 0.86840689f
        const val C3 = 0.63149379f
        const val C4 = 0.07491139f
        const val C5 = 0.37282383f
        const val C6 = 0.16905899f
    }
}

/** Shorthand matching the SwiftUI call sites. */
fun continuousShape(radius: Dp) = ContinuousRoundedCornerShape(radius)
