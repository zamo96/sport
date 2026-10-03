package shop.sportsearch.app.ui.moments

import android.provider.Settings
import androidx.compose.foundation.Canvas
import coil.compose.SubcomposeAsyncImage
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.util.UUID
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.min

/** A mutual like, as the viewer sees it. Port of `AppModel.MatchMoment`. */
data class MatchMoment(
    val id: String = UUID.randomUUID().toString(),
    val matchId: String,
    val sport: Sport,
    val viewerName: String,
    val viewerImagePath: String?,
    val playerName: String,
    val playerImagePath: String?,
)

/**
 * Beats of the neutral scene (`MatchMomentBeats.meet`): both cards come in from their
 * sides, meet in the middle, and the sport's badge lands between them.
 */
private object MatchMomentBeat {
    const val CONVERGE = 0.3
    const val LANDING = 0.6
    const val COPY = LANDING - 0.11
    const val ACTIONS = LANDING + 0.17
    const val FINAL_FRAME = 10.0
}

private val CARD_WIDTH = 116.dp
private val CARD_HEIGHT = 148.dp

/**
 * Full-screen moment for a mutual like. Port of `MatchMomentOverlay.swift` in its neutral
 * scene: every frame is a pure function of elapsed time, so a tap jumps straight to the
 * final frame and the per-frame work stays inside this view.
 *
 * The sport-specific scenes — the rally over a net, the sprint, the gloves, the barbell,
 * the mat and the water — are not here yet; every sport plays the neutral meet for now.
 */
@Composable
fun MatchMomentOverlay(
    moment: MatchMoment,
    onPlanGame: () -> Unit,
    onKeepBrowsing: () -> Unit,
) {
    val haptics = rememberAppHaptics()
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    var settled by remember(moment.id) { mutableStateOf(reduceMotion) }
    var time by remember(moment.id) {
        mutableStateOf(if (reduceMotion) MatchMomentBeat.FINAL_FRAME else 0.0)
    }
    val accent = when (moment.sport) {
        Sport.YOGA -> AppTheme.mint
        Sport.SUPBOARD -> MatchMomentPalette.water
        else -> MatchMomentProjectile.of(moment.sport)?.accent ?: MatchMomentPalette.ball
    }
    val settle = MatchMomentBeat.LANDING + matchMomentRest(moment.sport)

    LaunchedEffect(moment.id) {
        if (reduceMotion) {
            haptics.success()
            return@LaunchedEffect
        }
        val start = withFrameNanos { it }
        var landingCue = false
        while (!settled) {
            val elapsed = (withFrameNanos { it } - start) / 1_000_000_000.0
            time = elapsed
            if (!landingCue && elapsed >= MatchMomentBeat.LANDING) {
                if (matchMomentLandsGently(moment.sport)) haptics.success() else haptics.impactHeavy()
                landingCue = true
            }
            if (elapsed >= settle) {
                time = MatchMomentBeat.FINAL_FRAME
                settled = true
            }
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(listOf(Color(0xFF081712), Color(0xFF0F3024))),
                alpha = MatchMomentCurve.easeOut(time / 0.28).toFloat(),
            )
            .pointerInput(moment.id) {
                detectTapGestures {
                    if (!settled) {
                        if (time < MatchMomentBeat.LANDING) haptics.success()
                        time = MatchMomentBeat.FINAL_FRAME
                        settled = true
                    }
                }
            },
    ) {
        val density = LocalDensity.current
        val stage = remember(maxWidth, maxHeight) { MatchMomentStage(maxWidth, maxHeight) }
        val landingPx = with(density) {
            Offset(stage.centerX.toPx(), (stage.centerY + stage.landingY).toPx())
        }
        val landed = time - MatchMomentBeat.LANDING
        val particles = remember(moment.sport) { MatchMomentParticle.forSport(moment.sport) }

        // The flash of the meeting, dying away under the cards.
        Canvas(modifier = Modifier.fillMaxSize()) {
            if (landed >= 0) {
                val strength = 0.1 + 0.26 * exp(-4 * landed)
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(accent.copy(alpha = strength.toFloat()), Color.Transparent),
                        center = landingPx,
                        radius = 220.dp.toPx(),
                    ),
                    radius = 220.dp.toPx(),
                    center = landingPx,
                )
            }

            // `rings`, default case: two waves out of the meeting point.
            listOf(0.0, 0.1).forEach { delay ->
                val progress = (time - (MatchMomentBeat.LANDING + delay)) / 0.75
                if (progress in 0.0..1.0) {
                    val radius = 24.dp.toPx() + 150.dp.toPx() * MatchMomentCurve.easeOut(progress).toFloat()
                    drawCircle(
                        color = accent.copy(alpha = (0.6 * (1 - progress)).toFloat()),
                        radius = radius,
                        center = landingPx,
                        style = Stroke(width = (0.5 + 3 * (1 - progress)).dp.toPx()),
                    )
                }
            }
        }

        MatchMomentPlayerCard(
            name = moment.viewerName,
            caption = L10n.string("You", "Ты"),
            imagePath = moment.viewerImagePath,
            tint = listOf(AppTheme.court, Color(0xFF1A4D3B)),
            side = -1,
            time = time,
            stage = stage,
        )
        MatchMomentPlayerCard(
            name = moment.playerName,
            caption = moment.playerName,
            imagePath = moment.playerImagePath,
            tint = listOf(AppTheme.clay, Color(0xFF854026)),
            side = 1,
            time = time,
            stage = stage,
        )

        Canvas(modifier = Modifier.fillMaxSize()) {
            particles.forEach { particle ->
                val age = landed - particle.delay
                if (age >= 0 && age < particle.lifetime) {
                    val offset = particle.offset(age, landingPx)
                    val w = particle.width.dp.toPx()
                    val h = particle.height.dp.toPx()
                    rotate((particle.spin * age).toFloat(), offset) {
                        if (particle.isRound) {
                            drawCircle(
                                color = particle.color.copy(alpha = particle.opacity(age).toFloat()),
                                radius = w / 2,
                                center = offset,
                            )
                        } else {
                            drawRoundRect(
                                color = particle.color.copy(alpha = particle.opacity(age).toFloat()),
                                topLeft = Offset(offset.x - w / 2, offset.y - h / 2),
                                size = Size(w, h),
                                cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
                            )
                        }
                    }
                }
            }
        }

        MatchMomentSportBadge(sport = moment.sport, time = time, stage = stage)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .padding(bottom = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(stage.copyTop))
            Text(
                L10n.string("New match", "Новый мэтч").uppercase(),
                style = AppText.captionBold,
                color = Color(0xFFC2F7CC),
                modifier = Modifier.matchMomentReveal(time, MatchMomentBeat.COPY),
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                matchMomentTitle(moment.sport),
                style = AppText.titleBold,
                color = Color.White,
                textAlign = TextAlign.Center,
                modifier = Modifier.matchMomentReveal(time, MatchMomentBeat.COPY + 0.08),
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                matchMomentSubtitle(moment.sport),
                style = AppText.subheadlineSemibold,
                color = Color.White.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
                modifier = Modifier.matchMomentReveal(time, MatchMomentBeat.COPY + 0.16),
            )
            Spacer(modifier = Modifier.weight(1f))
            MatchMomentPrimaryButton(
                text = matchMomentAction(moment.sport),
                enabled = time >= MatchMomentBeat.ACTIONS,
                onClick = onPlanGame,
                modifier = Modifier.matchMomentReveal(time, MatchMomentBeat.ACTIONS),
            )
            Spacer(modifier = Modifier.height(6.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .matchMomentReveal(time, MatchMomentBeat.ACTIONS + 0.08)
                    .clickable(enabled = time >= MatchMomentBeat.ACTIONS, onClick = onKeepBrowsing),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    L10n.string("Keep browsing", "Смотреть дальше"),
                    style = AppText.subheadlineSemibold,
                    color = Color.White.copy(alpha = 0.78f),
                )
            }
        }
    }
}

/** Port of `MatchMomentStage` for the neutral scene, which draws no ground. */
private class MatchMomentStage(width: Dp, height: Dp) {
    val centerX: Dp = (width.value / 2).dp
    val centerY: Dp
    val copyTop: Dp
    val baselineX: Dp
    val offstageX: Dp

    init {
        val courtWidth = min(width.value - 24f, 380f)
        val courtHeight = courtWidth / 1.6f
        // Centre the settled picture in the space above the actions.
        val settledAboveCenter = 96f
        val settledHeight = settledAboveCenter + courtHeight / 2 + 40 + 110
        val y = maxOf(230f, (height.value - 120 - settledHeight) / 2 + settledAboveCenter)
        centerY = y.dp
        copyTop = (y + courtHeight / 2 + 40).dp
        baselineX = (courtWidth / 2 - CARD_WIDTH.value / 2 - 4).dp
        offstageX = (width.value / 2 + CARD_WIDTH.value).dp
    }

    /** The gap between the two cards' top corners once they meet. */
    val landingY: Dp = (-CARD_HEIGHT.value / 2 + 4).dp

    /** Where the cards settle, left and right of the centre. */
    val meetX: Dp = 54.dp
    val settledTilt: Double = 8.0
}

/**
 * One side's card. It enters from off-stage to its baseline, then both come together;
 * the meeting lunges each card at the centre and squeezes it, then it springs back.
 */
@Composable
private fun MatchMomentPlayerCard(
    name: String,
    caption: String,
    imagePath: String?,
    tint: List<Color>,
    side: Int,
    time: Double,
    stage: MatchMomentStage,
) {
    val entrance = if (side < 0) 0.05 else 0.12
    val entered = MatchMomentCurve.spring(time - entrance, response = 0.55, damping = 0.74)
    val met = MatchMomentCurve.spring(time - MatchMomentBeat.CONVERGE, response = 0.5, damping = 0.66)
    val offstage = stage.offstageX.value * side
    val baseline = stage.baselineX.value * side
    val meet = stage.meetX.value * side
    var x = offstage + (baseline - offstage) * entered
    x += (meet - x) * met
    var rotation = side * (14 + (4 - 14) * entered)
    rotation += (side * stage.settledTilt - rotation) * met

    // `cardsTouch`: the neutral scene's single hit is the meeting itself.
    val swing = MatchMomentCurve.bump(time - MatchMomentBeat.LANDING)
    val flash = (time - MatchMomentBeat.LANDING).let { since ->
        if (since < 0) 0.0 else 0.35 * exp(-14 * since)
    }

    Box(
        modifier = Modifier
            .offset(
                x = (stage.centerX.value + x - side * 10 * swing - CARD_WIDTH.value / 2).dp,
                y = (stage.centerY.value - CARD_HEIGHT.value / 2).dp,
            )
            .size(CARD_WIDTH, CARD_HEIGHT)
            .scale((1 - 0.07 * swing).toFloat())
            .rotate((rotation - side * 3 * swing).toFloat())
            .clip(continuousShape(26.dp))
            .background(Brush.linearGradient(tint))
            .border(3.dp, Color.White.copy(alpha = 0.92f), continuousShape(26.dp)),
    ) {
        // The photo fills the card; without one the card is its tint with white initials,
        // as `MatchMomentCard` draws it.
        val url = resolveAppRemoteUrl(imagePath)
        if (url != null) {
            SubcomposeAsyncImage(
                model = url,
                contentDescription = name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                loading = { MatchMomentCardInitials(name) },
                error = { MatchMomentCardInitials(name) },
            )
        } else {
            MatchMomentCardInitials(name)
        }
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f))))
                .padding(horizontal = 10.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(caption, style = AppText.captionBold, color = Color.White, maxLines = 1)
        }
        if (flash > 0.001) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White.copy(alpha = min(flash, 0.5).toFloat())),
            )
        }
    }
}

/** The sport's badge landing in the gap between the cards. Port of `sportBadge`. */
@Composable
private fun MatchMomentSportBadge(sport: Sport, time: Double, stage: MatchMomentStage) {
    val gentle = matchMomentLandsGently(sport)
    val pop = if (gentle) {
        MatchMomentCurve.easeOut((time - MatchMomentBeat.LANDING) / 0.6)
    } else {
        MatchMomentCurve.spring(time - MatchMomentBeat.LANDING, response = 0.42, damping = 0.55)
    }
    if (pop <= 0.001) return

    Box(
        modifier = Modifier
            .offset(
                x = (stage.centerX.value - 25).dp,
                y = (stage.centerY.value + stage.landingY.value - 25 - 22 * (1 - min(pop, 1.0))).dp,
            )
            .size(50.dp)
            .scale(abs(pop).toFloat())
            .clip(CircleShape)
            .background(MatchMomentPalette.ball),
        contentAlignment = Alignment.Center,
    ) {
        SportIconView(sport = sport, color = AppTheme.ink, size = 26.dp)
    }
}

/** Initials in the card's own white, offset up to clear the caption. */
@Composable
private fun MatchMomentCardInitials(name: String) {
    val initials = name.split(" ").take(2).mapNotNull { it.firstOrNull()?.uppercase() }.joinToString("")
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(
            initials,
            style = AppText.largeTitleBlack,
            color = Color.White.copy(alpha = 0.92f),
            modifier = Modifier.offset(y = (-10).dp),
        )
    }
}
