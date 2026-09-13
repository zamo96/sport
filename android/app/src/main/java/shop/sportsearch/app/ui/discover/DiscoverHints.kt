package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.ui.components.AutoSizeText
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.noRippleClickable
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape

/** `Color(red: 0.52, green: 0.92, blue: 0.38)` — the tutorial "yes" tint. */
private val TutorialLike = Color(0xFF85EB61)

/** `Color(red: 1.0, green: 0.34, blue: 0.38)` — the tutorial "no" tint. */
private val TutorialSkip = Color(0xFFFF5761)

/** `Color(red: 0.58, green: 0.96, blue: 0.36)` — the accent used by the interest hint. */
private val InterestAccent = Color(0xFF94F55C)

/** `LinearGradient` of the "Got it" button, shared by both overlays. */
private val GotItGradient = Brush.horizontalGradient(
    listOf(Color(0xFFADF56B), Color(0xFF7BD64D)),
)

/** Port of `DiscoverSimilarPlayersHintOverlay`. */
@Composable
fun DiscoverSimilarPlayersHintOverlay(onDismiss: () -> Unit) {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val height = maxHeight
        val width = maxWidth
        val isCompact = height < 760.dp
        val maxPanelWidth = minOf(width - 28.dp, 370.dp)
        val actionY = minOf(
            maxOf(height * (if (isCompact) 0.54f else 0.56f), if (isCompact) 380.dp else 440.dp),
            height - 230.dp,
        )
        val instructionY = minOf(actionY + if (isCompact) 70.dp else 78.dp, height - 128.dp)

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.36f))
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.22f),
                            AppTheme.court.copy(alpha = 0.08f),
                            Color.Black.copy(alpha = 0.56f),
                        ),
                    ),
                )
                // `.contentShape(Rectangle())` — the overlay swallows every touch.
                .noRippleClickable {},
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = actionY - 62.dp)
                    .padding(horizontal = if (isCompact) 18.dp else 24.dp),
                verticalAlignment = Alignment.Top,
            ) {
                TutorialSwipeActionCue(
                    title = L10n.string("not a\nfit", "не\nподходит"),
                    icon = Icons.Filled.Close,
                    tint = TutorialSkip,
                    textAlign = TextAlign.Start,
                )

                Spacer(modifier = Modifier.weight(1f))

                TutorialSwipeActionCue(
                    title = L10n.string("want to\nplay", "интересно\nсыграть"),
                    icon = Icons.Filled.Favorite,
                    tint = TutorialLike,
                    textAlign = TextAlign.End,
                )
            }

            AutoSizeText(
                text = L10n.string(
                    "Swipe cards to choose players",
                    "Смахивай карточки, чтобы выбирать игроков",
                ),
                fontSize = (if (isCompact) 17 else 19).sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                textAlign = TextAlign.Center,
                maxLines = 2,
                minScale = 0.82f,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = instructionY)
                    .width(maxPanelWidth),
            )

            Text(
                text = L10n.string("Got it", "Понятно"),
                fontFamily = appFontFamily,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Black.copy(alpha = 0.9f),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 18.dp)
                    .fillMaxWidth()
                    .height(54.dp)
                    .clip(continuousShape(24.dp))
                    .background(GotItGradient)
                    .noRippleClickable(onClick = onDismiss)
                    .padding(top = 15.dp),
            )
        }
    }
}

/** Port of `TutorialSwipeActionCue`. */
@Composable
private fun TutorialSwipeActionCue(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tint: Color,
    textAlign: TextAlign,
) {
    Column(
        modifier = Modifier.width(94.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(70.dp)
                .appShadow(tint.copy(alpha = 0.45f), 14.dp, 0.dp, 6.dp, CircleShape)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        listOf(tint.copy(alpha = 0.9f), tint.copy(alpha = 0.54f)),
                    ),
                )
                .border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(34.dp))
        }

        AutoSizeText(
            text = title,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = tint,
            textAlign = textAlign,
            maxLines = 2,
            minScale = 0.76f,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Port of `TutorialSwipeDecisionZones`. */
@Composable
fun TutorialSwipeDecisionZones() {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val zoneWidth = (maxWidth * 0.5f).coerceIn(170.dp, 212.dp)
        val zoneHeight = (maxHeight * 0.9f).coerceIn(420.dp, 520.dp)

        TutorialZoneCard(TutorialSkip, -3.5f, zoneWidth, zoneHeight, Modifier.align(Alignment.CenterStart))
        TutorialZoneCard(TutorialLike, 3.5f, zoneWidth, zoneHeight, Modifier.align(Alignment.CenterEnd))
    }
}

@Composable
private fun TutorialZoneCard(
    tint: Color,
    rotation: Float,
    zoneWidth: androidx.compose.ui.unit.Dp,
    zoneHeight: androidx.compose.ui.unit.Dp,
    modifier: Modifier,
) {
    val shape = continuousShape(34.dp)
    Box(
        modifier = modifier
            .width(zoneWidth)
            .height(zoneHeight)
            .graphicsLayer { rotationZ = rotation }
            .appShadow(tint.copy(alpha = 0.35f), 16.dp, 0.dp, 8.dp, shape)
            .clip(shape)
            .background(tint.copy(alpha = 0.24f))
            .border(1.6.dp, tint.copy(alpha = 0.86f), shape),
    )
}

/** Port of `DiscoverFirstInterestHintOverlay`. */
@Composable
fun DiscoverFirstInterestHintOverlay(playerName: String?, onDismiss: () -> Unit) {
    val recipient = playerName?.trim()?.takeIf { it.isNotEmpty() }
        ?: L10n.string("the player", "игроку")

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val isCompact = maxHeight < 760.dp
        val panelWidth = minOf(maxWidth - 28.dp, 386.dp)
        val panelShape = continuousShape(34.dp)

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.72f))
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.3f),
                            AppTheme.court.copy(alpha = 0.2f),
                            Color.Black.copy(alpha = 0.82f),
                        ),
                    ),
                )
                .noRippleClickable {},
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .width(panelWidth)
                    .appShadow(Color.Black.copy(alpha = 0.44f), 24.dp, 0.dp, 20.dp, panelShape)
                    .clip(panelShape)
                    .background(Color.Black.copy(alpha = 0.78f))
                    .background(AppTheme.court.copy(alpha = 0.1f))
                    .border(1.dp, TutorialLike.copy(alpha = 0.5f), panelShape)
                    .padding(horizontal = 24.dp, vertical = if (isCompact) 20.dp else 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(if (isCompact) 15.dp else 19.dp),
            ) {
                val badgeSize = if (isCompact) 78.dp else 86.dp
                Box(
                    modifier = Modifier
                        .size(badgeSize)
                        .appShadow(InterestAccent.copy(alpha = 0.34f), 18.dp, 0.dp, 0.dp, CircleShape)
                        .clip(CircleShape)
                        .background(AppTheme.court.copy(alpha = 0.18f))
                        .border(1.5.dp, TutorialLike.copy(alpha = 0.82f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.Send,
                        contentDescription = null,
                        tint = InterestAccent,
                        modifier = Modifier
                            .size(if (isCompact) 29.dp else 32.dp)
                            .graphicsLayer { rotationZ = -10f },
                    )
                }

                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    AutoSizeText(
                        text = L10n.string(
                            "Game interest\nsent",
                            "Спортивный интерес\nотправлен",
                        ),
                        fontSize = (if (isCompact) 23 else 26).sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = Color.White,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        minScale = 0.78f,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Text(
                        text = L10n.string(
                            "We'll let $recipient know you're ready to play. If the interest is mutual, you can chat in Matches.",
                            "Мы покажем $recipient, что ты готов сыграть. Если интерес будет взаимным, вы сможете общаться в «Мэтчи».",
                        ),
                        fontFamily = appFontFamily,
                        fontSize = (if (isCompact) 15 else 16).sp,
                        fontWeight = FontWeight.Medium,
                        lineHeight = (if (isCompact) 18 else 19).sp,
                        color = Color.White.copy(alpha = 0.86f),
                        textAlign = TextAlign.Center,
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    InterestStepView(Icons.Filled.CheckCircle, L10n.string("You chose", "Отметил"), Modifier.weight(1f))
                    InterestArrow()
                    InterestStepView(Icons.AutoMirrored.Filled.Send, L10n.string("Waiting", "Ждем"), Modifier.weight(1f))
                    InterestArrow()
                    InterestStepView(Icons.Filled.Notifications, L10n.string("They'll see", "Увидит"), Modifier.weight(1f))
                }

                val noteShape = continuousShape(22.dp)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(noteShape)
                        .background(AppTheme.court.copy(alpha = 0.22f))
                        .border(1.dp, InterestAccent.copy(alpha = 0.34f), noteShape)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.Message,
                            contentDescription = null,
                            tint = InterestAccent,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = L10n.string("What happens next?", "Что дальше?"),
                            fontFamily = appFontFamily,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }

                    Text(
                        text = L10n.string(
                            "When the interest is mutual, the player will appear under Matches. You can discuss the sport, time, and place there.",
                            "Когда интерес станет взаимным, игрок появится в разделе «Мэтчи». Там можно обсудить спорт, удобное время и место.",
                        ),
                        fontFamily = appFontFamily,
                        fontSize = (if (isCompact) 14 else 15).sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.82f),
                    )
                }

                Text(
                    text = L10n.string("Got it", "Понятно"),
                    fontFamily = appFontFamily,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.Black.copy(alpha = 0.9f),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(54.dp)
                        .clip(continuousShape(24.dp))
                        .background(GotItGradient)
                        .noRippleClickable(onClick = onDismiss)
                        .padding(top = 15.dp),
                )
            }
        }
    }
}

/** Port of `InterestStepView`. */
@Composable
private fun InterestStepView(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
                .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = InterestAccent, modifier = Modifier.size(21.dp))
        }

        AutoSizeText(
            text = title,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            textAlign = TextAlign.Center,
            maxLines = 1,
            minScale = 0.82f,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Port of `InterestArrow`. */
@Composable
private fun InterestArrow() {
    Box(
        modifier = Modifier.width(18.dp).height(54.dp),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.AutoMirrored.Filled.ArrowForward,
            contentDescription = null,
            tint = InterestAccent,
            modifier = Modifier.size(18.dp),
        )
    }
}
