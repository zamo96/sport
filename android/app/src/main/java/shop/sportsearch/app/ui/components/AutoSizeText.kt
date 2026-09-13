package shop.sportsearch.app.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.isUnspecified
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.ui.theme.appFontFamily

/**
 * SwiftUI's `.minimumScaleFactor(_:)` paired with `.lineLimit(_:)`.
 *
 * Compose has no equivalent before `TextAutoSize` (Compose 1.8), so this shrinks
 * the font in place: it draws once, and if the result overflowed it steps the
 * size down by 6% and redraws, never going below `minScale` of the requested
 * size. Two or three extra layout passes at most, and only for text that would
 * otherwise be truncated.
 */
@Composable
fun AutoSizeText(
    text: String,
    fontSize: TextUnit,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = appFontFamily,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
    maxLines: Int = Int.MAX_VALUE,
    minScale: Float = 0.8f,
    style: TextStyle = LocalTextStyle.current,
) {
    var scale by remember(text, fontSize, maxLines) { mutableFloatStateOf(1f) }

    Text(
        text = text,
        modifier = modifier,
        color = color,
        fontSize = fontSize * scale,
        fontWeight = fontWeight,
        fontFamily = fontFamily,
        textAlign = textAlign,
        lineHeight = if (lineHeight.isUnspecified) lineHeight else lineHeight * scale,
        maxLines = maxLines,
        softWrap = true,
        style = style,
        onTextLayout = { result ->
            if ((result.didOverflowWidth || result.didOverflowHeight) && scale > minScale) {
                scale = maxOf(scale - 0.06f, minScale)
            }
        },
    )
}

/**
 * SwiftUI's `.onTapGesture` — a hit target with no Material ripple, which the
 * iOS design never draws.
 */
fun Modifier.noRippleClickable(
    enabled: Boolean = true,
    onClick: () -> Unit,
): Modifier = composed {
    val interactionSource = remember { MutableInteractionSource() }
    clickable(
        interactionSource = interactionSource,
        indication = null,
        enabled = enabled,
        onClick = onClick,
    )
}
