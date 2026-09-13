package shop.sportsearch.app.ui.auth

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import shop.sportsearch.app.R
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import kotlin.math.abs

/** Port of `private enum OnboardingStepPalette`. */
object OnboardingStepPalette {
    val lime = Color(0xFF8CEB40)        // rgb(0.55, 0.92, 0.25)
    val limeSoft = Color(0xFF6BC738)    // rgb(0.42, 0.78, 0.22)
    val panel = Color(0xFF0F1417)       // rgb(0.06, 0.08, 0.09)
    val panelRaised = Color(0xFF141A1C)  // rgb(0.08, 0.10, 0.11)
    val stroke = Color.White.copy(alpha = 0.12f)
}

/** The intro screen's near-black gradient plus its three blurred colour blobs. */
@Composable
fun OnboardingIntroBackground(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    listOf(Color(0xFF05080D), Color(0xFF0A0D12), Color(0xFF05080A)),
                ),
            ),
    ) {
        Blob(AppTheme.court.copy(alpha = 0.18f), 320.dp, (-110).dp, 110.dp)
        Blob(AppTheme.clay.copy(alpha = 0.18f), 300.dp, 140.dp, (-10).dp)
        Blob(Color.White.copy(alpha = 0.06f), 220.dp, 20.dp, (-220).dp)
    }
}

@Composable
private fun androidx.compose.foundation.layout.BoxScope.Blob(color: Color, diameter: Dp, x: Dp, y: Dp) {
    Box(
        Modifier
            .align(Alignment.Center)
            .offset(x = x, y = y)
            .size(diameter * 1.7f)
            .background(
                Brush.radialGradient(0f to color, 0.3f to color, 1f to Color.Transparent),
                CircleShape,
            ),
    )
}

/** Port of `private struct OnboardingTypewriterLine`. */
@Composable
fun OnboardingTypewriterLine(fontSize: Float = 34f, modifier: Modifier = Modifier) {
    val phrases = listOf(
        L10n.string("tennis", "в теннис"),
        L10n.string("football", "в футбол"),
        L10n.string("padel", "в падел"),
        L10n.string("a workout", "в зал"),
    )

    var displayedPhrase by remember { mutableStateOf("") }
    var cursorVisible by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        var index = 0
        while (true) {
            val phrase = phrases[index]
            for (count in 0..phrase.length) {
                displayedPhrase = phrase.take(count)
                delay(56)
            }
            delay(1200)
            for (count in phrase.length downTo 0) {
                displayedPhrase = phrase.take(count)
                delay(28)
            }
            index = (index + 1) % phrases.size
        }
    }

    LaunchedEffect(Unit) {
        while (true) {
            delay(480)
            cursorVisible = !cursorVisible
        }
    }

    Row(
        modifier = modifier.height((fontSize + 10).dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = L10n.string("Play", "для игры"),
            fontSize = fontSize.sp,
            fontWeight = FontWeight.Black,
            color = Color.White,
            maxLines = 1,
        )
        Text(
            text = displayedPhrase.ifEmpty { " " },
            fontSize = fontSize.sp,
            fontWeight = FontWeight.Black,
            maxLines = 1,
            style = androidx.compose.ui.text.TextStyle(
                brush = Brush.horizontalGradient(
                    listOf(Color(0xFFE0F7D1), OnboardingStepPalette.lime, Color(0xFF4CD680)),
                ),
            ),
        )
        Box(
            Modifier
                .size(width = 3.dp, height = (fontSize * 0.82f).dp)
                .background(
                    Color.White.copy(alpha = if (cursorVisible) 0.9f else 0.2f),
                    RoundedCornerShape(2.dp),
                ),
        )
    }
}

private data class OnboardingPreviewCardData(
    val name: String,
    val sport: String,
    val level: String,
    val metaLeft: String,
    val metaRight: String,
    val imageRes: Int,
)

/** Port of `private struct OnboardingMotionHero` + `OnboardingLoopingCards`. */
@Composable
fun OnboardingMotionHero(height: Dp, modifier: Modifier = Modifier) {
    val cards = listOf(
        OnboardingPreviewCardData("Максим, 27", L10n.string("Tennis", "Теннис"), L10n.string("Recreational", "Любитель"), L10n.string("Within 5 km", "До 5 км"), L10n.string("Today, 18:30", "Сегодня, 18:30"), R.drawable.hero_tennis),
        OnboardingPreviewCardData("Елена, 26", L10n.string("Volleyball", "Волейбол"), L10n.string("Intermediate", "Средний"), L10n.string("Within 4 km", "До 4 км"), L10n.string("Today, 19:30", "Сегодня, 19:30"), R.drawable.onboarding_player_volleyball_woman),
        OnboardingPreviewCardData("Дмитрий, 29", L10n.string("Football", "Футбол"), L10n.string("Intermediate", "Средний"), L10n.string("Within 3 km", "До 3 км"), L10n.string("Today, 19:00", "Сегодня, 19:00"), R.drawable.hero_football),
        OnboardingPreviewCardData("Мария, 25", L10n.string("Squash", "Сквош"), L10n.string("Recreational", "Любитель"), L10n.string("Within 3 km", "До 3 км"), L10n.string("Tomorrow, 18:00", "Завтра, 18:00"), R.drawable.onboarding_player_squash_woman),
        OnboardingPreviewCardData("Антон, 31", L10n.string("Fitness", "Зал"), L10n.string("Confident", "Уверенный"), L10n.string("Within 4 km", "До 4 км"), L10n.string("Tomorrow, 7:10", "Завтра, 7:10"), R.drawable.hero_fitness),
        OnboardingPreviewCardData("София, 29", L10n.string("Padel", "Падел"), L10n.string("Intermediate", "Средний"), L10n.string("Within 5 km", "До 5 км"), L10n.string("Tomorrow, 20:00", "Завтра, 20:00"), R.drawable.onboarding_player_padel_woman),
        OnboardingPreviewCardData("Никита, 28", L10n.string("Padel", "Падел"), L10n.string("Recreational", "Любитель"), L10n.string("Within 6 km", "До 6 км"), L10n.string("Today, 20:00", "Сегодня, 20:00"), R.drawable.hero_padel),
    )

    var currentPage by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        while (true) {
            delay(4000)
            currentPage = (currentPage + 1) % cards.size
        }
    }

    Box(modifier = modifier.height(height), contentAlignment = Alignment.BottomCenter) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize().padding(bottom = 16.dp)) {
            val cardHeight = maxOf(236.dp, maxHeight - 4.dp)
            val cardWidth = minOf(maxWidth * 0.82f, cardHeight * 0.84f)
            val unit = cardWidth + 10.dp

            (-1..1).forEach { slot ->
                val index = ((currentPage + slot) % cards.size + cards.size) % cards.size
                val isActive = slot == 0
                val relative = slot.toFloat()

                Box(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .offset(x = unit * relative, y = if (isActive) 0.dp else 8.dp)
                        .graphicsLayer {
                            scaleX = if (isActive) 1f else 0.88f
                            scaleY = if (isActive) 1f else 0.88f
                            alpha = if (isActive) 1f else 0.24f
                            rotationY = -relative * 12f
                            cameraDistance = 12f * density
                        }
                        .appShadow(
                            color = Color.Black.copy(alpha = if (isActive) 0.40f else 0.16f),
                            radius = if (isActive) 30.dp else 14.dp,
                            offsetX = (relative * -8).dp,
                            offsetY = if (isActive) 26.dp else 18.dp,
                            shape = continuousShape(28.dp),
                        ),
                ) {
                    OnboardingPreviewCard(cards[index], cardWidth, cardHeight)
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            cards.indices.forEach { index ->
                val active = index == currentPage
                val width by animateFloatAsState(if (active) 24f else 12f, label = "dot$index")
                Box(
                    Modifier
                        .size(width = width.dp, height = 6.dp)
                        .background(
                            if (active) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.20f),
                            RoundedCornerShape(percent = 50),
                        ),
                )
            }
        }
    }
}

@Composable
private fun OnboardingPreviewCard(card: OnboardingPreviewCardData, width: Dp, height: Dp) {
    val cardShape = continuousShape(28.dp)
    Box(
        modifier = Modifier
            .size(width = width, height = height)
            .clip(cardShape)
            .background(Color.Black.copy(alpha = 0.22f))
            .border(1.2.dp, Color.White.copy(alpha = 0.28f), cardShape),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Image(
            painter = painterResource(card.imageRes),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )

        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.02f),
                            Color.Black.copy(alpha = 0.18f),
                            Color.Black.copy(alpha = 0.74f),
                        ),
                    ),
                ),
        )

        val panelShape = continuousShape(26.dp)
        Column(
            modifier = Modifier
                .padding(12.dp)
                .fillMaxWidth()
                .clip(panelShape)
                .background(Color.Black.copy(alpha = 0.42f))
                .border(1.dp, Color.White.copy(alpha = 0.12f), panelShape)
                .padding(horizontal = 14.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    card.name,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Icon(
                    Icons.Filled.Verified,
                    contentDescription = null,
                    tint = OnboardingStepPalette.lime,
                    modifier = Modifier.size(16.dp),
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PreviewChip(card.sport, OnboardingStepPalette.lime.copy(alpha = 0.42f), highlighted = true)
                PreviewChip(card.level, Color.White.copy(alpha = 0.12f), highlighted = false)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                MetaChip(Icons.Filled.LocationOn, card.metaLeft)
                MetaChip(Icons.Filled.AccessTime, card.metaRight)
            }
        }
    }
}

@Composable
private fun PreviewChip(text: String, tint: Color, highlighted: Boolean) {
    Row(
        modifier = Modifier
            .background(tint, RoundedCornerShape(percent = 50))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(7.dp)
                .background(if (highlighted) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.68f), CircleShape),
        )
        Text(text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
    }
}

@Composable
private fun MetaChip(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(
        modifier = Modifier
            .background(Color.White.copy(alpha = 0.10f), RoundedCornerShape(percent = 50))
            .padding(horizontal = 10.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.82f), modifier = Modifier.size(12.dp))
        Text(text, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.82f), maxLines = 1)
    }
}

/**
 * Port of `private struct LiquidStartButton`: the wide green pill that expands
 * on appear, pulses, and carries the tennis-ball accent.
 */
@Composable
fun LiquidStartButton(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val haptics = rememberAppHaptics()
    var hasExpanded by remember { mutableStateOf(false) }
    var isPressed by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        delay(160)
        hasExpanded = true
    }

    val transition = rememberInfiniteTransition(label = "startPulse")
    val pulse by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1300), RepeatMode.Reverse),
        label = "pulse",
    )

    val widthFraction by animateFloatAsState(
        targetValue = if (hasExpanded) 1f else 0.08f,
        animationSpec = androidx.compose.animation.core.spring(dampingRatio = 0.82f, stiffness = 220f),
        label = "expand",
    )
    val contentAlpha by animateFloatAsState(if (hasExpanded) 1f else 0f, label = "contentAlpha")
    val shape = continuousShape(31.dp)

    Box(modifier = modifier.fillMaxWidth().height(82.dp), contentAlignment = Alignment.Center) {
        Box(
            modifier = Modifier
                .fillMaxWidth(widthFraction)
                .height(82.dp)
                .scale(if (isPressed) 0.985f else 1f + 0.012f * pulse)
                .appShadow(
                    color = Color(0xFF78DB3D).copy(alpha = 0.22f + 0.12f * pulse),
                    radius = 18.dp,
                    offsetX = (-8).dp,
                    offsetY = 8.dp,
                    shape = shape,
                )
                .appShadow(
                    color = Color(0xFF056B61).copy(alpha = 0.34f),
                    radius = 22.dp,
                    offsetX = 10.dp,
                    offsetY = 14.dp,
                    shape = shape,
                )
                .clip(shape)
                .background(
                    Brush.horizontalGradient(
                        0f to Color(0xFF6BB83B),
                        0.45f to Color(0xFF2EA170),
                        1f to Color(0xFF157A78),
                    ),
                )
                .border(1.dp, Color.White.copy(alpha = 0.24f), shape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) {
                    haptics.success()
                    isPressed = true
                    onClick()
                },
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        Brush.radialGradient(
                            listOf(Color.White.copy(alpha = 0.22f), Color.White.copy(alpha = 0.07f), Color.Transparent),
                            radius = 400f,
                        ),
                    ),
            )

            Image(
                painter = painterResource(R.drawable.onboarding_tennis_ball),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 78.dp)
                    .size(78.dp)
                    .graphicsLayer { alpha = contentAlpha },
            )

            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 23.dp, end = 16.dp)
                    .graphicsLayer { alpha = contentAlpha },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(title, fontSize = 21.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1)
                    Text(
                        subtitle,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Normal,
                        color = Color.White.copy(alpha = 0.82f),
                        maxLines = 1,
                    )
                }

                Box(
                    modifier = Modifier
                        .size(54.dp)
                        .appShadow(Color.Black.copy(alpha = 0.08f), radius = 10.dp, offsetY = 5.dp, shape = CircleShape)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.28f))
                        .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(23.dp),
                    )
                }
            }
        }
    }
}

/** Port of `OTPCodeField`: six boxed digits driven by one hidden text field. */
@Composable
fun OtpCodeField(
    code: String,
    onCodeChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusRequester = remember { androidx.compose.ui.focus.FocusRequester() }

    Box(modifier = modifier) {
        androidx.compose.foundation.text.BasicTextField(
            value = code,
            onValueChange = { value -> onCodeChange(value.filter(Char::isDigit).take(6)) },
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                keyboardType = androidx.compose.ui.text.input.KeyboardType.NumberPassword,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .focusRequester(focusRequester)
                .graphicsLayer { alpha = 0.01f },
            decorationBox = { it() },
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { focusRequester.requestFocus() },
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            repeat(6) { index ->
                val digit = code.getOrNull(index)?.toString().orEmpty()
                val filled = digit.isNotEmpty()
                val shape = continuousShape(16.dp)
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(56.dp)
                        .clip(shape)
                        .background(AppTheme.creamLight)
                        .border(
                            width = if (filled) 1.6.dp else 1.dp,
                            color = if (filled) AppTheme.court.copy(alpha = 0.6f) else AppTheme.court.copy(alpha = 0.16f),
                            shape = shape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(digit, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = AppTheme.ink)
                }
            }
        }
    }
}
