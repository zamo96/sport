package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import kotlin.math.abs
import kotlin.math.min

/** Port of `accentColor` in SwipeCard. */
val DiscoverUser.cardAccentColor: Color
    get() = when (preferredSports.firstOrNull()) {
        null -> AppTheme.court
        Sport.TENNIS, Sport.PADEL -> AppTheme.court
        Sport.SQUASH, Sport.BOXING -> AppTheme.clay
        Sport.BADMINTON, Sport.FITNESS, Sport.SUPBOARD -> Color(0xFF3D85E0)  // rgb(0.24, 0.52, 0.88)
        Sport.VOLLEYBALL, Sport.FOOTBALL, Sport.RUNNING -> Color(0xFFC79C2E) // rgb(0.78, 0.61, 0.18)
        Sport.TABLE_TENNIS -> Color(0xFF29A1B8)                              // rgb(0.16, 0.63, 0.72)
        Sport.YOGA -> Color(0xFF8F5CBD)                                      // rgb(0.56, 0.36, 0.74)
    }

/**
 * Port of `struct SwipeCard` in DiscoverView.swift: the story bars, the hero
 * photo with its dark gradient, the identity block, the "why you match" panel
 * and the two decision buttons.
 */
@Composable
fun SwipeCard(
    user: DiscoverUser,
    index: Int,
    dragOffsetX: Float,
    decision: SwipeAction?,
    storyIndex: Int,
    storyProgress: Float,
    modifier: Modifier = Modifier,
    onOpen: () -> Unit = {},
    onDislike: () -> Unit = {},
    onLike: () -> Unit = {},
) {
    val isTop = index == 0
    val swipeStrength = min(abs(dragOffsetX) / 170f, 1f)
    val leftProgress = min(maxOf(-dragOffsetX, 0f) / 170f, 1f)
    val rightProgress = min(maxOf(dragOffsetX, 0f) / 170f, 1f)
    val accent = user.cardAccentColor
    val outerShape = continuousShape(34.dp)
    val innerShape = continuousShape(30.dp)

    Box(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer {
                if (isTop) {
                    translationX = dragOffsetX
                    rotationZ = dragOffsetX / 22f
                }
            }
            .appShadow(
                color = AppTheme.ink.copy(alpha = if (isTop) 0.18f else 0.08f),
                radius = 24.dp,
                offsetY = 14.dp,
                shape = outerShape,
            )
            .clip(outerShape)
            .background(Color.Black.copy(alpha = 0.76f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), outerShape)
            .padding(12.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clip(innerShape)
                .border(1.dp, Color.White.copy(alpha = 0.14f), innerShape),
        ) {
            // cardBackground: hero photo + accent wash + bottom-darkening gradient
            CardBackground(user = user, accent = accent)

            // decisionOverlay
            if (decision != null && swipeStrength > 0f) {
                val tint = if (decision == SwipeAction.LIKE) Color.Green else Color.Red
                Box(
                    Modifier
                        .matchParentSize()
                        .background(
                            Brush.linearGradient(
                                listOf(
                                    tint.copy(alpha = 0.28f * swipeStrength),
                                    Color.Transparent,
                                    tint.copy(alpha = 0.12f * swipeStrength),
                                ),
                            ),
                        ),
                )
            }

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(18.dp)
                    .graphicsLayer {
                        translationX = dragOffsetX * 0.045f
                        translationY = -min(abs(dragOffsetX) * 0.02f, 8f)
                    },
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                StoryProgressBars(
                    count = user.playerCardMediaItems.size.coerceIn(1, 6),
                    activeIndex = storyIndex,
                    progress = storyProgress,
                )

                Spacer(Modifier.weight(1f))

                PlayerIdentityBlock(user = user, onOpen = onOpen)

                PlayerFitPanel(user = user, onOpen = onOpen)

                if (isTop) {
                    SwipeActionHints(user = user, onDislike = onDislike, onLike = onLike)
                }
            }

            // decisionBadge (top-leading)
            decision?.let {
                GlassDecision(
                    text = if (it == SwipeAction.LIKE) {
                        L10n.string("Ready to play", "Можно сыграть")
                    } else {
                        L10n.string("Skip", "Пропустить")
                    },
                    tint = if (it == SwipeAction.LIKE) Color(0xFFD4FFE0) else Color.White,
                    modifier = Modifier.align(Alignment.TopStart).padding(16.dp),
                )
            }

            // bottomDecisionText
            val centerText = when {
                leftProgress > 0.05f -> L10n.string("Skip", "Пропустить")
                rightProgress > 0.05f -> L10n.string("Available to play", "Можно сыграть")
                else -> null
            }
            centerText?.let {
                val opacity = maxOf(leftProgress, rightProgress)
                Text(
                    it,
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.9f * opacity),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 18.dp)
                        .graphicsLayer {
                            scaleX = 0.92f + opacity * 0.08f
                            scaleY = 0.92f + opacity * 0.08f
                        },
                )
            }
        }
    }
}

@Composable
private fun BoxScope.CardBackground(user: DiscoverUser, accent: Color) {
    Box(modifier = Modifier.matchParentSize()) {
        val heroUrl = resolveAppRemoteUrl(user.profileHeroImagePath)
        if (heroUrl != null) {
            AsyncImage(
                model = heroUrl,
                contentDescription = user.displayName,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
        } else {
            // fallbackBackground
            Box(
                Modifier
                    .matchParentSize()
                    .background(Brush.linearGradient(listOf(accent, AppTheme.ink))),
            )
        }

        // SwipeCardAmbientLayer, reduced to its two static blobs. The SwiftUI
        // version animates them off a TimelineView; that runs every frame and is
        // deliberately left out of the first Android pass.
        Box(
            Modifier
                .matchParentSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(accent.copy(alpha = 0.28f), Color.Transparent),
                        center = Offset(80f, 120f),
                        radius = 420f,
                    ),
                ),
        )

        Box(
            Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.12f),
                            Color.Black.copy(alpha = 0.35f),
                            Color.Black.copy(alpha = 0.90f),
                        ),
                    ),
                ),
        )
    }
}

@Composable
private fun StoryProgressBars(count: Int, activeIndex: Int, progress: Float) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        repeat(count) { index ->
            val fill = when {
                index < activeIndex -> 1f
                index == activeIndex -> progress
                else -> 0f
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(5.dp)
                    .clip(RoundedCornerShape(percent = 50))
                    .background(Color.White.copy(alpha = 0.32f)),
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(fill)
                        .height(5.dp)
                        .background(Color.White, RoundedCornerShape(percent = 50)),
                )
            }
        }
    }
}

@Composable
private fun PlayerIdentityBlock(user: DiscoverUser, onOpen: () -> Unit) {
    val primarySport = user.preferredSports.firstOrNull()
    val level = primarySport?.let { user.sportLevels[it.wire] } ?: user.tennisLevel
    val levelText = level?.let { L10n.string("level $it", "уровень $it") }
        ?: L10n.string("level not specified", "уровень не указан")
    val locationText = user.districtDisplayNames.firstOrNull()
        ?: user.city
        ?: L10n.string("City not specified", "Город не указан")

    Column(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                user.age?.let { "${user.displayName}, $it" } ?: user.displayName,
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Icon(Icons.Filled.Verified, contentDescription = null, tint = AppTheme.mint, modifier = Modifier.size(20.dp))
        }

        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                primarySport?.title ?: L10n.string("Sport not specified", "Спорт не указан"),
                style = AppText.subheadlineSemibold,
                color = if (primarySport != null) AppTheme.mint else Color.White.copy(alpha = 0.82f),
            )
            Text("·", style = AppText.subheadlineSemibold, color = Color.White.copy(alpha = 0.82f))
            Text(levelText, style = AppText.subheadlineSemibold, color = Color.White.copy(alpha = 0.82f))
            Text("·", style = AppText.subheadlineSemibold, color = Color.White.copy(alpha = 0.82f))
            Text(
                locationText,
                style = AppText.subheadlineSemibold,
                color = Color.White.copy(alpha = 0.82f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun PlayerFitPanel(user: DiscoverUser, onOpen: () -> Unit) {
    val shape = continuousShape(22.dp)
    val primarySport = user.preferredSports.firstOrNull()
    val level = primarySport?.let { user.sportLevels[it.wire] } ?: user.tennisLevel

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.Black.copy(alpha = 0.32f))
            .border(1.dp, Color.White.copy(alpha = 0.1f), shape)
            .clickable(onClick = onOpen)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp),
    ) {
        Text(
            L10n.string("Why you are a good match", "Почему вы подходите"),
            style = AppText.subheadlineSemibold.copy(fontWeight = FontWeight.Bold),
            color = Color.White,
        )

        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            FitMetric(
                icon = Icons.Filled.SportsTennis,
                title = L10n.string("Sport", "Спорт"),
                value = primarySport?.title ?: L10n.string("Any", "Любой"),
                modifier = Modifier.weight(1f),
            )
            MetricDivider()
            FitMetric(
                icon = Icons.Filled.BarChart,
                title = L10n.string("Level", "Уровень"),
                value = level?.toString() ?: "—",
                modifier = Modifier.weight(1f),
            )
            MetricDivider()
            FitMetric(
                icon = Icons.Filled.Place,
                title = L10n.string("District", "Район"),
                value = user.nearby?.let { listOfNotNull(user.city, it.distanceLabel).joinToString(" · ") }
                    ?: user.districtDisplayNames.firstOrNull()
                    ?: user.distanceLabel,
                modifier = Modifier.weight(1f),
            )
        }

        Text(
            user.bio?.trim()?.takeIf { it.isNotEmpty() }
                ?: L10n.string(
                    "Ready to quickly arrange and play without extra steps.",
                    "Готов быстро договориться и выйти на игру без лишних шагов.",
                ),
            style = AppText.subheadline,
            color = Color.White.copy(alpha = 0.78f),
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun MetricDivider() {
    Box(Modifier.width(1.dp).height(52.dp).background(Color.White.copy(alpha = 0.08f)))
}

@Composable
private fun FitMetric(icon: ImageVector, title: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, contentDescription = null, tint = AppTheme.mint, modifier = Modifier.size(17.dp))
        Text(title, style = AppText.caption2Semibold, color = Color.White.copy(alpha = 0.52f))
        Text(
            value,
            style = AppText.captionSemibold,
            color = Color.White.copy(alpha = 0.84f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun SwipeActionHints(user: DiscoverUser, onDislike: () -> Unit, onLike: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Bottom,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(7.dp),
            modifier = Modifier.clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onDislike,
            ),
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
            }
            Text(
                L10n.string("Skip", "Пропустить"),
                style = AppText.captionSemibold,
                color = Color.White.copy(alpha = 0.7f),
            )
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(7.dp),
            modifier = Modifier.clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onLike,
            ),
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(AppTheme.court),
                contentAlignment = Alignment.Center,
            ) {
                SportIconView(
                    sport = user.preferredSports.firstOrNull() ?: Sport.TENNIS,
                    color = Color.White,
                    size = 34.dp,
                )
            }
            Text(
                L10n.string("Invite to play", "Позвать на игру"),
                style = AppText.captionSemibold,
                color = Color.White.copy(alpha = 0.78f),
            )
        }
    }
}

/** Port of `GlassDecision`. */
@Composable
private fun GlassDecision(text: String, tint: Color, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(percent = 50)
    Text(
        text,
        style = AppText.captionBold,
        color = tint,
        modifier = modifier
            .clip(shape)
            .background(Color.Black.copy(alpha = 0.32f))
            .border(1.dp, tint.copy(alpha = 0.4f), shape)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}
