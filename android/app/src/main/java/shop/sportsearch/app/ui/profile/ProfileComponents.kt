package shop.sportsearch.app.ui.profile

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.PlayerMediaItem
import shop.sportsearch.app.core.PlayerMediaKind
import shop.sportsearch.app.core.ProfileScreenMode
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.UserProfile
import shop.sportsearch.app.core.displayName
import shop.sportsearch.app.core.shortTitle
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Ports of the small building blocks at the bottom of ProfileView.swift. */

@Composable
fun ProfileDarkPanel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = continuousShape(20.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .appShadow(Color.Black.copy(alpha = 0.28f), radius = 18.dp, offsetY = 12.dp, shape = shape)
            .clip(shape)
            .background(
                Brush.linearGradient(listOf(Color.White.copy(alpha = 0.08f), Color.White.copy(alpha = 0.035f))),
            )
            .border(1.dp, Color.White.copy(alpha = 0.1f), shape)
            .padding(18.dp),
        content = content,
    )
}

@Composable
fun ProfileMenuGroup(content: @Composable ColumnScope.() -> Unit) {
    ProfileDarkPanel { content() }
}

@Composable
fun ProfileMenuRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    subtitle: String?,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(42.dp)
                .clip(continuousShape(12.dp))
                .background(tint.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = AppText.subheadlineSemibold, color = Color.White)
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = AppText.caption,
                    color = Color.White.copy(alpha = 0.54f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Icon(
            Icons.Filled.ChevronRight,
            null,
            tint = Color.White.copy(alpha = 0.42f),
            modifier = Modifier.size(14.dp),
        )
    }
}

@Composable
fun ProfileActionRow(icon: ImageVector, title: String, onClick: () -> Unit) {
    ProfileMenuRow(icon, Color.White.copy(alpha = 0.72f), title, null, onClick = onClick)
}

@Composable
fun ProfileHeaderButton(icon: ImageVector, tint: Color, onClick: () -> Unit) {
    val shape = continuousShape(14.dp)
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun ProfileCapsule(text: String, tint: Color) {
    Text(
        text,
        style = AppText.captionSemibold,
        color = if (tint == AppTheme.court) Color(0xFF4CAF50) else Color.White,
        modifier = Modifier
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.18f))
            .padding(horizontal = 10.dp, vertical = 7.dp),
    )
}

@Composable
fun ProfileSportChip(sport: Sport, level: Int?) {
    val levelText = level?.let { "$it-${minOf(10, maxOf(1, it + 1))}" } ?: ""
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.08f))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SportIconView(
            sport = sport,
            color = if (sport == Sport.TENNIS) Color(0xFFFFEB3B) else AppTheme.court,
            size = 15.dp,
        )
        Text(
            "${sport.shortTitle} $levelText".trim(),
            style = AppText.captionSemibold,
            color = Color.White,
            maxLines = 1,
        )
    }
}

@Composable
fun ProfileSubscreenHeader(title: String, onBack: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier.size(40.dp).clickable(onClick = onBack),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack,
                null,
                tint = Color.White,
                modifier = Modifier.size(21.dp),
            )
        }
        Spacer(Modifier.weight(1f))
        Text(title, style = AppText.headline, color = Color.White)
        Spacer(Modifier.weight(1f))
        Spacer(Modifier.size(40.dp))
    }
}

@Composable
fun ProfileInfoLine(title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = AppText.subheadline, color = Color.White.copy(alpha = 0.56f))
        Spacer(Modifier.weight(1f))
        Text(value, style = AppText.subheadline, color = Color.White)
    }
}

@Composable
fun ProfileSmallPublicCard(profile: UserProfile) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.1f), shape)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RemoteAvatarView(name = profile.displayName, path = profile.avatarUrl, size = 70.dp)
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(profile.displayName, style = AppText.title3Bold, color = Color.White)
            val cityFallback = L10n.string("City not selected", "Город не выбран")
            Text(
                profile.age?.let {
                    L10n.string(
                        "$it years old · ${profile.city ?: cityFallback}",
                        "$it лет · ${profile.city ?: cityFallback}",
                    )
                } ?: (profile.city ?: cityFallback),
                style = AppText.subheadline,
                color = Color.White.copy(alpha = 0.6f),
            )
            Text(
                profile.preferredSports.take(2).joinToString(" · ") { it.title },
                style = AppText.captionSemibold,
                color = Color.White.copy(alpha = 0.72f),
            )
        }
    }
}

@Composable
fun ProfileEditorHero(title: String, subtitle: String, icon: ImageVector, tint: Color) {
    val shape = continuousShape(26.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(listOf(tint.copy(alpha = 0.18f), Color.White.copy(alpha = 0.055f))),
            )
            .border(1.dp, tint.copy(alpha = 0.22f), shape)
            .padding(18.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(58.dp)
                .clip(continuousShape(18.dp))
                .background(tint.copy(alpha = 0.16f))
                .border(1.dp, tint.copy(alpha = 0.28f), continuousShape(18.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(26.dp))
        }

        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                title,
                fontSize = 28.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                subtitle,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.62f),
            )
        }
    }
}

data class ProfileMetricItem(val title: String, val value: String, val icon: ImageVector)

@Composable
fun ProfileEditorMetricStrip(items: List<ProfileMetricItem>) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { item ->
            val shape = continuousShape(18.dp)
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clip(shape)
                    .background(Color.White.copy(alpha = 0.07f))
                    .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(item.icon, null, tint = Color(0xFF4CAF50), modifier = Modifier.size(15.dp))
                Text(
                    item.value,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    item.title.uppercase(),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp,
                    color = Color.White.copy(alpha = 0.48f),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
fun ProfileEmbeddedLightCard(title: String, subtitle: String, content: @Composable ColumnScope.() -> Unit) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.92f))
            .border(1.dp, Color.White.copy(alpha = 0.72f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = AppText.headline, color = AppTheme.ink)
            Text(subtitle, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.62f))
        }
        content()
    }
}

/** Port of `struct ToggleCard` - a light card with a hand-drawn switch. */
@Composable
fun ToggleCard(title: String, subtitle: String, isOn: Boolean, onToggle: (Boolean) -> Unit) {
    val haptics = rememberAppHaptics()
    val shape = continuousShape(22.dp)
    val knobAlignment by animateFloatAsState(
        if (isOn) 1f else 0f,
        spring(dampingRatio = 0.82f),
        label = "toggleKnob",
    )

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.78f))
            .border(1.dp, Color.White.copy(alpha = 0.72f), shape)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = AppText.subheadlineSemibold, color = AppTheme.ink)
            Text(subtitle, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.62f))
        }

        Box(
            modifier = Modifier
                .width(54.dp)
                .height(32.dp)
                .clip(continuousShape(18.dp))
                .background(if (isOn) AppTheme.court else AppTheme.cream)
                .clickable {
                    haptics.selection()
                    onToggle(!isOn)
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(
                modifier = Modifier
                    .padding(horizontal = 4.dp)
                    .align(if (knobAlignment > 0.5f) Alignment.CenterEnd else Alignment.CenterStart)
                    .size(24.dp)
                    .clip(CircleShape)
                    .background(Color.White),
            )
        }
    }
}

/** Port of `struct ProfileScreenModePicker`. */
@Composable
fun ProfileScreenModePicker(selection: ProfileScreenMode, onSelect: (ProfileScreenMode) -> Unit) {
    val haptics = rememberAppHaptics()
    val shape = continuousShape(18.dp)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.07f))
            .border(1.dp, Color.White.copy(alpha = 0.09f), shape)
            .padding(5.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ProfileScreenMode.entries.forEach { mode ->
            val isSelected = selection == mode
            Column(
                modifier = Modifier
                    .weight(1f)
                    .height(50.dp)
                    .clip(continuousShape(14.dp))
                    .background(if (isSelected) AppTheme.mint else Color.Transparent)
                    .clickable {
                        haptics.selection()
                        onSelect(mode)
                    }
                    .padding(horizontal = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    if (mode == ProfileScreenMode.EDITING) Icons.Filled.Check else Icons.Filled.Info,
                    null,
                    tint = if (isSelected) Color.Black else Color.White.copy(alpha = 0.68f),
                    modifier = Modifier.size(13.dp),
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    mode.title,
                    style = AppText.captionSemibold,
                    color = if (isSelected) Color.Black else Color.White.copy(alpha = 0.68f),
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                )
            }
        }
    }
}

/** Port of `struct ProfileHeroImage`. */
@Composable
fun ProfileHeroImage(name: String, path: String?, height: Dp, modifier: Modifier = Modifier) {
    val shape = continuousShape(22.dp)
    val url = resolveAppRemoteUrl(path)

    Box(
        modifier = modifier.fillMaxWidth().height(height).clip(shape).background(Color.White.copy(alpha = 0.07f)),
        contentAlignment = Alignment.Center,
    ) {
        if (url != null) {
            AsyncImage(
                model = url,
                contentDescription = name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            RemoteAvatarView(name = name, path = null, size = height * 0.42f)
        }
    }
}

/** Port of `struct ProfileMediaTile`. */
@Composable
fun ProfileMediaTile(
    item: PlayerMediaItem,
    canRemove: Boolean,
    isEnabled: Boolean,
    onPreview: (PlayerMediaItem) -> Unit,
    onRemove: (PlayerMediaItem) -> Unit,
) {
    val shape = continuousShape(16.dp)
    Box(
        modifier = Modifier
            .size(width = 92.dp, height = 120.dp)
            .clip(shape)
            .border(1.dp, AppTheme.court.copy(alpha = 0.55f), shape),
    ) {
        val url = resolveAppRemoteUrl(item.path)
        if (url != null && item.kind == PlayerMediaKind.PHOTO) {
            AsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().clickable(enabled = isEnabled) { onPreview(item) },
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.linearGradient(
                            listOf(AppTheme.court.copy(alpha = 0.28f), Color.White.copy(alpha = 0.08f)),
                        ),
                    )
                    .clickable(enabled = isEnabled) { onPreview(item) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (item.kind == PlayerMediaKind.VIDEO) Icons.Filled.PlayCircleFilled else Icons.Filled.PhotoCamera,
                    null,
                    tint = Color.White.copy(alpha = 0.8f),
                    modifier = Modifier.size(26.dp),
                )
            }
        }

        if (canRemove) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.58f))
                    .clickable(enabled = isEnabled) { onRemove(item) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(11.dp))
            }
        }
    }
}

/** Port of `struct ProfileAddMediaTile`. */
@Composable
fun ProfileAddMediaTile(title: String, icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    val shape = continuousShape(16.dp)
    Column(
        modifier = Modifier
            .size(width = 92.dp, height = 120.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.045f))
            .border(1.dp, Color.White.copy(alpha = 0.16f), shape)
            .clickable(enabled = enabled, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, null, tint = Color.White.copy(alpha = 0.86f), modifier = Modifier.size(22.dp))
        Text(
            title,
            style = AppText.captionBold,
            color = Color.White.copy(alpha = 0.86f),
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

/** Port of `struct ProfileMediaAdviceRow`. */
@Composable
fun ProfileMediaAdviceRow() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(16.dp))
            .background(Color.White.copy(alpha = 0.055f))
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Filled.Info, null, tint = AppTheme.court, modifier = Modifier.size(16.dp))
        Text(
            L10n.string(
                "Add well-lit photos and short videos from games or practice.",
                "Добавьте фото в хорошем освещении и короткие видео с игры или тренировки.",
            ),
            style = AppText.captionSemibold,
            color = Color.White.copy(alpha = 0.64f),
        )
    }
}

/** Port of `struct ProfileMediaProgressOverlay`. */
@Composable
fun ProfileMediaProgressOverlay(title: String, subtitle: String) {
    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.48f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .width(280.dp)
                .clip(continuousShape(24.dp))
                .background(Color(0xFF1A1A1A))
                .border(1.dp, Color.White.copy(alpha = 0.16f), continuousShape(24.dp))
                .padding(horizontal = 22.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
            Text(title, style = AppText.headlineBold, color = Color.White)
            Text(
                subtitle,
                style = AppText.captionSemibold,
                color = Color.White.copy(alpha = 0.66f),
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** Port of `struct ProfileSaveSuccessToast`. */
@Composable
fun ProfileSaveSuccessToast(message: String) {
    val shape = continuousShape(20.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .appShadow(Color.Black.copy(alpha = 0.24f), radius = 18.dp, offsetY = 12.dp, shape = shape)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        Color(red = 0.07f, green = 0.17f, blue = 0.12f),
                        Color(red = 0.10f, green = 0.30f, blue = 0.20f),
                    ),
                ),
            )
            .border(1.2.dp, Color(red = 0.37f, green = 0.78f, blue = 0.56f).copy(alpha = 0.8f), shape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(42.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                L10n.string("Saved successfully", "Успешно сохранено").uppercase(),
                style = AppText.captionSemibold.copy(letterSpacing = 1.3.sp),
                color = Color(red = 0.76f, green = 0.97f, blue = 0.80f),
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

/** Port of `struct InlineStatusToast`. */
@Composable
fun InlineStatusToast(message: String) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .appShadow(Color.Black.copy(alpha = 0.25f), radius = 18.dp, offsetY = 12.dp, shape = shape)
            .clip(shape)
            .background(Color.Black.copy(alpha = 0.92f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), shape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.CheckCircle, null, tint = Color.White, modifier = Modifier.size(18.dp))
        Text(message, style = AppText.subheadlineSemibold, color = Color.White)
    }
}
