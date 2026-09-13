package shop.sportsearch.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import shop.sportsearch.app.BuildConfig
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `func resolveAppRemoteURL`. Media paths from the API are relative to
 * the backend host unless they already carry a scheme.
 */
fun resolveAppRemoteUrl(path: String?): String? {
    val trimmed = path?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    if (trimmed.contains("://")) return trimmed
    val base = "${BuildConfig.API_SCHEME}://${BuildConfig.API_BASE_URL}"
    return "$base/${trimmed.removePrefix("/")}"
}

/**
 * Port of `struct RemoteAvatarView`, including the initials placeholder and the
 * `size * 0.34` continuous corner radius.
 */
@Composable
fun RemoteAvatarView(
    name: String,
    path: String?,
    modifier: Modifier = Modifier,
    size: Dp = 76.dp,
) {
    val shape = continuousShape(size * 0.34f)
    val url = resolveAppRemoteUrl(path)

    Box(
        modifier = modifier
            .size(size)
            .clip(shape),
        contentAlignment = Alignment.Center,
    ) {
        if (url != null) {
            SubcomposeAsyncImage(
                model = url,
                contentDescription = name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(size),
                loading = { AvatarInitials(name, size) },
                error = { AvatarInitials(name, size) },
            )
        } else {
            AvatarInitials(name, size)
        }
    }
}

@Composable
private fun AvatarInitials(name: String, size: Dp) {
    val initials = name.split(" ")
        .filter { it.isNotBlank() }
        .take(2)
        .joinToString("") { it.take(1).uppercase() }
        .ifEmpty { "TS" }

    Box(
        modifier = Modifier
            .size(size)
            .background(Brush.linearGradient(listOf(AppTheme.mint, AppTheme.softWhite))),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = initials,
            fontSize = (size.value * 0.3f).sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.court,
            style = AppText.body,
        )
    }
}
