package shop.sportsearch.app.ui.courts

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.DiscoverUser
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.displayName
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.continuousShape

/** The centers screen accent, `Color(red: 48/255, green: 214/255, blue: 147/255)`. */
val CourtAccent = Color(0xFF30D693)

/** `darkStroke` in CourtsView.swift. */
val DarkStroke = Color.White.copy(alpha = 0.1f)

/** Port of `struct CourtImageTile`. */
@Composable
fun CourtImageTile(court: Court, size: Dp) {
    val shape = continuousShape(18.dp)
    Box(
        modifier = Modifier.size(size).clip(shape).background(Color.White.copy(alpha = 0.06f)),
        contentAlignment = Alignment.Center,
    ) {
        val url = resolveAppRemoteUrl(court.primaryPhotoUrl)
        if (url != null) {
            AsyncImage(
                model = url,
                contentDescription = court.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(size),
            )
        } else {
            SportIconView(
                sport = court.supportedSports.firstOrNull() ?: Sport.TENNIS,
                color = CourtAccent,
                size = 28.dp,
            )
        }
    }
}

/** Port of `struct CourtAmenityPill`. */
@Composable
fun CourtAmenityPill(title: String) {
    Text(
        title,
        style = AppText.caption2Semibold,
        color = Color.White.copy(alpha = 0.72f),
        maxLines = 1,
        modifier = Modifier
            .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(percent = 50))
            .padding(horizontal = 9.dp, vertical = 5.dp),
    )
}

/** Port of `struct CourtInfoPill`. */
@Composable
fun CourtInfoPill(icon: ImageVector, title: String) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.07f))
            .padding(horizontal = 11.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(13.dp))
        Text(title, style = AppText.caption2Semibold, color = Color.White.copy(alpha = 0.78f), maxLines = 1)
    }
}

/** Port of `struct CompactCourtAction`. */
@Composable
fun CompactCourtAction(title: String, icon: ImageVector, isEnabled: Boolean, onClick: () -> Unit) {
    val shape = continuousShape(16.dp)
    Column(
        modifier = Modifier
            .clip(shape)
            .background(Color.White.copy(alpha = if (isEnabled) 0.08f else 0.035f))
            .border(1.dp, DarkStroke, shape)
            .clickable(enabled = isEnabled, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(
            icon,
            null,
            tint = if (isEnabled) CourtAccent else Color.White.copy(alpha = 0.28f),
            modifier = Modifier.size(17.dp),
        )
        Text(
            title,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isEnabled) Color.White.copy(alpha = 0.86f) else Color.White.copy(alpha = 0.3f),
            maxLines = 1,
        )
    }
}

/** Port of `struct CourtActiveSearchAvatars` - overlapping avatars plus a "+N" bubble. */
@Composable
fun CourtActiveSearchAvatars(users: List<DiscoverUser>, overflowCount: Int, size: Dp) {
    if (users.isEmpty() && overflowCount <= 0) return

    Row(horizontalArrangement = Arrangement.spacedBy((-size / 3))) {
        users.take(4).forEach { user ->
            RemoteAvatarView(
                name = user.displayName,
                path = user.avatarUrl,
                size = size,
                modifier = Modifier.border(2.dp, Color.Black, CircleShape),
            )
        }

        if (overflowCount > 0) {
            Box(
                modifier = Modifier
                    .size(size)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.14f))
                    .border(2.dp, Color.Black, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "+$overflowCount",
                    fontSize = (size.value * 0.34f).sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.82f),
                )
            }
        }
    }
}

/** Port of `struct TennisBallsLoader` - three balls bouncing out of phase. */
@Composable
fun TennisBallsLoader(title: String) {
    val transition = rememberInfiniteTransition(label = "balls")

    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            repeat(3) { index ->
                val offsetY by transition.animateFloat(
                    initialValue = 0f,
                    targetValue = -14f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(520, delayMillis = index * 140),
                        repeatMode = RepeatMode.Reverse,
                    ),
                    label = "ball$index",
                )
                Box(
                    modifier = Modifier
                        .offset(y = offsetY.dp)
                        .size(16.dp)
                        .clip(CircleShape)
                        .background(CourtAccent),
                )
            }
        }

        Text(title, style = AppText.subheadlineSemibold, color = Color.White.copy(alpha = 0.72f))
    }
}
