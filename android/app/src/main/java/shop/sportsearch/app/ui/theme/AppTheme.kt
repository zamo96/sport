package shop.sportsearch.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 1:1 port of `enum AppTheme` in ios/TennisSearchIOS/Views/UIComponents.swift.
 * Every value here is the same RGB the SwiftUI app uses, so the two clients
 * render the same palette.
 */
object AppTheme {
    val ink = Color(0xFF11261D)          // rgb(17, 38, 29)
    val cream = Color(0xFFF4EFE6)        // rgb(244, 239, 230)
    val creamLight = Color(0xFFFFF9F1)   // rgb(255, 249, 241)
    val mint = Color(0xFFE5F3EC)         // rgb(229, 243, 236)
    val clay = Color(0xFFC96D42)         // rgb(201, 109, 66)
    val court = Color(0xFF2F7A65)        // rgb(47, 122, 101)

    val line = Color.White.copy(alpha = 0.62f)
    val mutedInk = ink.copy(alpha = 0.62f)
    val softWhite = Color.White.copy(alpha = 0.88f)

    /** LinearGradient(colors: [creamLight, cream, mint], .top -> .bottom) */
    val pageBackground = Brush.verticalGradient(listOf(creamLight, cream, mint))

    /** Selected tint of the bottom bar: Color(red: 0.28, green: 0.55, blue: 0.98) */
    val tabAccent = Color(0xFF478CFA)

    /** Bottom bar selection pill: Color(red: 0.15, green: 0.15, blue: 0.16) */
    val tabIndicator = Color(0xFF262629)

    /** MenuTabLoadingOverlay ball gradient. */
    val loadingBall = Brush.linearGradient(
        listOf(Color(0xFFD4F541), Color(0xFF30D693)),
    )
}

/**
 * SwiftUI semantic font sizes, expressed in sp. SwiftUI points and Android dp
 * are the same physical size, so the numbers carry over unchanged.
 *
 * The iOS build renders in SF Pro, which is the Apple system face rather than a
 * brand font - the app bundles no typeface of its own. The Android counterpart
 * of that choice is the platform face, so this stays [FontFamily.Default]:
 * bundling something else (Inter, say) would differ from iOS, not match it.
 * Swap here if the product ever adopts a real brand font on both clients.
 */
val appFontFamily: FontFamily = FontFamily.Default

object AppFont {
    val caption2 = 11.sp
    val caption = 12.sp
    val footnote = 13.sp
    val subheadline = 15.sp
    val callout = 16.sp
    val body = 17.sp
    val headline = 17.sp
    val title3 = 20.sp
    val title2 = 22.sp
    val title = 28.sp
    val largeTitle = 34.sp
}

private fun style(
    size: androidx.compose.ui.unit.TextUnit,
    weight: FontWeight,
    lineHeightRatio: Float = 1.28f,
) = TextStyle(
    fontFamily = appFontFamily,
    fontSize = size,
    fontWeight = weight,
    lineHeight = size * lineHeightRatio,
)

/** Compose equivalents of the SwiftUI text roles this app actually uses. */
object AppText {
    val caption2 = style(AppFont.caption2, FontWeight.Normal)
    val caption2Semibold = style(AppFont.caption2, FontWeight.SemiBold)
    val caption = style(AppFont.caption, FontWeight.Normal)
    val captionSemibold = style(AppFont.caption, FontWeight.SemiBold)
    val captionBold = style(AppFont.caption, FontWeight.Bold)
    val footnote = style(AppFont.footnote, FontWeight.Normal)
    val subheadline = style(AppFont.subheadline, FontWeight.Normal)
    val subheadlineSemibold = style(AppFont.subheadline, FontWeight.SemiBold)
    val callout = style(AppFont.callout, FontWeight.Normal)
    val body = style(AppFont.body, FontWeight.Normal)
    val headline = style(AppFont.headline, FontWeight.SemiBold)
    val headlineBold = style(AppFont.headline, FontWeight.Bold)
    val title3 = style(AppFont.title3, FontWeight.Normal, 1.24f)
    val title3Semibold = style(AppFont.title3, FontWeight.SemiBold, 1.24f)
    val title3Bold = style(AppFont.title3, FontWeight.Bold, 1.24f)
    val title2Bold = style(AppFont.title2, FontWeight.Bold, 1.22f)
    val titleBold = style(AppFont.title, FontWeight.Bold, 1.18f)
    val largeTitleBlack = style(AppFont.largeTitle, FontWeight.Black, 1.14f)
}

private val appColorScheme = lightColorScheme(
    primary = AppTheme.court,
    onPrimary = Color.White,
    secondary = AppTheme.clay,
    onSecondary = Color.White,
    background = AppTheme.creamLight,
    onBackground = AppTheme.ink,
    surface = Color.White,
    onSurface = AppTheme.ink,
    surfaceVariant = AppTheme.cream,
    onSurfaceVariant = AppTheme.mutedInk,
    outline = AppTheme.court.copy(alpha = 0.16f),
    error = Color(0xFFD1493F),
)

private val appTypography = Typography(
    bodyLarge = AppText.body,
    bodyMedium = AppText.subheadline,
    bodySmall = AppText.footnote,
    titleLarge = AppText.title3Semibold,
    titleMedium = AppText.headline,
    titleSmall = AppText.subheadlineSemibold,
    labelLarge = AppText.subheadlineSemibold,
    labelMedium = AppText.captionSemibold,
    labelSmall = AppText.caption2Semibold,
)

/**
 * The iOS app is locked to the light appearance (`.environment(\.colorScheme, .light)`
 * on every field, cream page background everywhere), so the Android port does the
 * same and ignores the system dark theme rather than inventing a second palette.
 */
@Composable
fun SportSearchTheme(
    @Suppress("UNUSED_PARAMETER") darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = appColorScheme,
        typography = appTypography,
        content = content,
    )
}

/** Corner radii used across the SwiftUI views, kept in one place. */
object AppRadius {
    val field = 22.dp
    val button = 24.dp
    val card = 28.dp
    val sheet = 30.dp
    val overlay = 32.dp
}
