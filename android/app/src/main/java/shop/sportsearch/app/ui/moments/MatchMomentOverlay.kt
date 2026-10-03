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
import androidx.compose.ui.graphics.drawscope.scale
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

private const val FINAL_FRAME = 10.0

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
    val rally = remember(moment.sport) { MatchMomentRally.of(moment.sport) }
    val beats = rally?.beats ?: MatchMomentBeats.meet.copy(
        rest = matchMomentRest(moment.sport),
        gentle = matchMomentLandsGently(moment.sport),
    )
    var settled by remember(moment.id) { mutableStateOf(reduceMotion) }
    var time by remember(moment.id) {
        mutableStateOf(if (reduceMotion) FINAL_FRAME else 0.0)
    }
    val accent = when (moment.sport) {
        Sport.YOGA -> AppTheme.mint
        Sport.SUPBOARD -> MatchMomentPalette.water
        else -> MatchMomentProjectile.of(moment.sport)?.accent ?: MatchMomentPalette.ball
    }
    val settle = beats.landing + matchMomentRest(moment.sport)

    LaunchedEffect(moment.id) {
        if (reduceMotion) {
            haptics.success()
            return@LaunchedEffect
        }
        val start = withFrameNanos { it }
        val pending = beats.contacts.toMutableList()
        var landingCue = false
        while (!settled) {
            val elapsed = (withFrameNanos { it } - start) / 1_000_000_000.0
            time = elapsed
            // Each contact lands in the hand as hard as it does on screen.
            while (pending.isNotEmpty() && elapsed >= pending.first().time) {
                when (pending.removeAt(0).feel) {
                    MatchMomentFeel.LIGHT, MatchMomentFeel.SOFT -> haptics.impactLight()
                    MatchMomentFeel.MEDIUM -> haptics.impactMedium()
                    MatchMomentFeel.RIGID -> haptics.impactHeavy()
                }
            }
            if (!landingCue && elapsed >= beats.landing) {
                if (matchMomentLandsGently(moment.sport)) haptics.success() else haptics.impactHeavy()
                landingCue = true
            }
            if (elapsed >= settle) {
                time = FINAL_FRAME
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
                        if (time < beats.landing) haptics.success()
                        time = FINAL_FRAME
                        settled = true
                    }
                }
            },
    ) {
        val density = LocalDensity.current
        val stage = remember(maxWidth, maxHeight, rally) {
            MatchMomentStage(maxWidth, maxHeight, rally?.ground?.aspect ?: MatchMomentGround.TENNIS.aspect)
        }
        val landingPx = with(density) {
            Offset(stage.centerX.toPx(), (stage.centerY + stage.landingY).toPx())
        }
        val landed = time - beats.landing
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
                val progress = (time - (beats.landing + delay)) / 0.75
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

        if (rally != null) {
            MatchMomentGroundView(rally = rally, time = time, stage = stage, converge = beats.converge)
        }

        MatchMomentPlayerCard(
            name = moment.viewerName,
            caption = L10n.string("You", "Ты"),
            imagePath = moment.viewerImagePath,
            tint = listOf(AppTheme.court, Color(0xFF1A4D3B)),
            side = -1,
            time = time,
            stage = stage,
            beats = beats,
        )
        MatchMomentPlayerCard(
            name = moment.playerName,
            caption = moment.playerName,
            imagePath = moment.playerImagePath,
            tint = listOf(AppTheme.clay, Color(0xFF854026)),
            side = 1,
            time = time,
            stage = stage,
            beats = beats,
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

        if (rally == null) {
            MatchMomentSportBadge(sport = moment.sport, time = time, stage = stage, landing = beats.landing)
        } else {
            MatchMomentProjectileView(rally = rally, time = time, stage = stage)
        }

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
                modifier = Modifier.matchMomentReveal(time, beats.copy),
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                matchMomentTitle(moment.sport),
                style = AppText.titleBold,
                color = Color.White,
                textAlign = TextAlign.Center,
                modifier = Modifier.matchMomentReveal(time, beats.copy + 0.08),
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                matchMomentSubtitle(moment.sport),
                style = AppText.subheadlineSemibold,
                color = Color.White.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
                modifier = Modifier.matchMomentReveal(time, beats.copy + 0.16),
            )
            Spacer(modifier = Modifier.weight(1f))
            MatchMomentPrimaryButton(
                text = matchMomentAction(moment.sport),
                enabled = time >= beats.actions,
                onClick = onPlanGame,
                modifier = Modifier.matchMomentReveal(time, beats.actions),
            )
            Spacer(modifier = Modifier.height(6.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .matchMomentReveal(time, beats.actions + 0.08)
                    .clickable(enabled = time >= beats.actions, onClick = onKeepBrowsing),
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

/** Port of `MatchMomentStage`. Units are dp relative to the stage centre, as on iOS. */
private class MatchMomentStage(
    width: Dp,
    height: Dp,
    groundAspect: Float,
) : MatchMomentStageGeometry {
    val centerX: Dp
    val centerY: Dp
    val copyTop: Dp
    val offstageX: Dp
    override val courtWidth: Float
    override val courtHeight: Float
    override val baselineX: Float

    init {
        courtWidth = min(width.value - 24f, 380f)
        courtHeight = courtWidth / groundAspect
        // Centre the settled picture (seal, court, copy) in the space above the actions;
        // the highest lob still needs headroom on short screens.
        val settledAboveCenter = 96f
        val settledHeight = settledAboveCenter + courtHeight / 2 + 40 + 110
        val y = maxOf(230f, (height.value - 120 - settledHeight) / 2 + settledAboveCenter)
        centerX = (width.value / 2).dp
        centerY = y.dp
        copyTop = (y + courtHeight / 2 + 40).dp
        baselineX = courtWidth / 2 - CARD_WIDTH_UNITS / 2 - 4
        offstageX = (width.value / 2 + CARD_WIDTH_UNITS).dp
    }

    val landingY: Dp get() = landing.y.dp
    val baselineXDp: Dp get() = baselineX.dp

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
    beats: MatchMomentBeats,
) {
    val entrance = if (side < 0) 0.05 else 0.12
    val entered = MatchMomentCurve.spring(time - entrance, response = 0.55, damping = 0.74)
    val met = MatchMomentCurve.spring(time - beats.converge, response = 0.5, damping = 0.66)
    val offstage = stage.offstageX.value * side
    val baseline = stage.baselineX * side
    val meet = stage.meetX.value * side
    var x = offstage + (baseline - offstage) * entered
    x += (meet - x) * met
    var rotation = side * (14 + (4 - 14) * entered)
    rotation += (side * stage.settledTilt - rotation) * met

    // A hit (or the two cards colliding) lunges the card at the centre and squeezes it,
    // then springs back; the same hits flash it white.
    val hits = beats.hits(side)
    val swing = hits.sumOf { MatchMomentCurve.bump(time - it) }
    val flash = hits.sumOf { hit ->
        val since = time - hit
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
private fun MatchMomentSportBadge(sport: Sport, time: Double, stage: MatchMomentStage, landing: Double) {
    val gentle = matchMomentLandsGently(sport)
    val pop = if (gentle) {
        MatchMomentCurve.easeOut((time - landing) / 0.6)
    } else {
        MatchMomentCurve.spring(time - landing, response = 0.42, damping = 0.55)
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

/**
 * The court, its markings and the net, drawn in as the scene opens and stepping back
 * once the players leave their places for the centre. Port of `ground(_:at:stage:style:)`.
 *
 * SwiftUI trims the markings path as it draws; here they fade in over the same window —
 * Compose has no cheap trim across a path of many contours.
 */
@Composable
private fun MatchMomentGroundView(
    rally: MatchMomentRally,
    time: Double,
    stage: MatchMomentStage,
    converge: Double,
) {
    val drawn = MatchMomentCurve.easeInOut((time - 0.1) / 0.7).toFloat()
    val stretched = MatchMomentCurve.easeInOut((time - 0.25) / 0.35).toFloat()
    val recede = (1 - 0.5 * MatchMomentCurve.easeInOut((time - converge) / 0.4)).toFloat()
    if (drawn <= 0.001f) return

    Canvas(modifier = Modifier.fillMaxSize()) {
        val center = Offset(stage.centerX.toPx(), stage.centerY.toPx())
        val width = stage.courtWidth.dp.toPx()
        val height = stage.courtHeight.dp.toPx()
        val rect = androidx.compose.ui.geometry.Rect(
            center.x - width / 2, center.y - height / 2,
            center.x + width / 2, center.y + height / 2,
        )

        drawRoundRect(
            color = rally.ground.surface.copy(alpha = 0.26f * drawn * recede),
            topLeft = Offset(rect.left, rect.top),
            size = Size(rect.width, rect.height),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(6.dp.toPx()),
        )
        drawPath(
            path = matchMomentGroundLines(rally.ground, rect),
            color = Color.White.copy(alpha = rally.ground.lineOpacity * drawn * recede),
            style = Stroke(width = rally.ground.lineWidth.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round),
        )

        rally.ground.netWidth?.let { netWidth ->
            val netHeight = (height + 28.dp.toPx()) * stretched
            drawRoundRect(
                color = Color.White.copy(alpha = 0.45f * recede),
                topLeft = Offset(center.x - netWidth.dp.toPx() / 2, center.y - (height + 28.dp.toPx()) / 2),
                size = Size(netWidth.dp.toPx(), netHeight),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(netWidth.dp.toPx() / 2),
            )
        }
    }
}

/** The ball, shuttle or cork mid-rally, with the ghosts of where it just was. */
@Composable
private fun MatchMomentProjectileView(
    rally: MatchMomentRally,
    time: Double,
    stage: MatchMomentStage,
) {
    val flight = MatchMomentFlight.state(time, stage, rally) ?: return

    Canvas(modifier = Modifier.fillMaxSize()) {
        val center = Offset(stage.centerX.toPx(), stage.centerY.toPx())
        fun place(offset: Offset) = Offset(center.x + offset.x.dp.toPx(), center.y + offset.y.dp.toPx())

        if (flight.isInFlight) {
            for (index in 1..4) {
                val ghost = MatchMomentFlight.state(time - 0.022 * index, stage, rally) ?: continue
                if (!ghost.isInFlight) continue
                drawCircle(
                    color = rally.projectile.accent.copy(alpha = (0.26 * (1 - index / 5.0)).toFloat()),
                    radius = rally.projectile.flightSize.dp.toPx() * ghost.depth * (1 - 0.1f * index) / 2,
                    center = place(ghost.position),
                )
            }
        }

        val position = place(flight.position)
        rotate(flight.rotation, position) {
            scale(flight.squashX, flight.squashY, position) {
                drawProjectile(rally.projectile, position, flight.size.dp.toPx())
            }
        }
    }
}
