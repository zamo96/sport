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
import androidx.compose.ui.graphics.graphicsLayer
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
import kotlin.math.sin
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
    val style = remember(moment.sport) { MatchMomentStyle(moment.sport) }
    val rally = style.rally
    val beats = style.beats
    var settled by remember(moment.id) { mutableStateOf(reduceMotion) }
    var time by remember(moment.id) {
        mutableStateOf(if (reduceMotion) FINAL_FRAME else 0.0)
    }
    val accent = style.accent
    val settle = beats.settle

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
                if (beats.gentle) haptics.success() else haptics.impactHeavy()
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
        val stage = remember(maxWidth, maxHeight, style) {
            MatchMomentStage(maxWidth, maxHeight, style.ground?.aspect ?: MatchMomentGround.TENNIS.aspect)
        }
        val landingUnits = style.landingPoint(stage)
        val landingPx = with(density) {
            Offset(
                stage.centerX.toPx() + landingUnits.x.dp.toPx(),
                stage.centerY.toPx() + landingUnits.y.dp.toPx(),
            )
        }
        val landed = time - beats.landing
        val particles = style.particles

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

            // The waves out of the landing point; on the water they lie flat.
            style.rings.forEach { ring ->
                val progress = (time - ring.start) / ring.duration
                if (progress in 0.0..1.0) {
                    val radius = 24.dp.toPx() + ring.radius.dp.toPx() * MatchMomentCurve.easeOut(progress).toFloat()
                    drawOval(
                        color = accent.copy(alpha = (ring.strength * (1 - progress)).toFloat()),
                        topLeft = Offset(landingPx.x - radius, landingPx.y - radius * ring.flatten),
                        size = Size(2 * radius, 2 * radius * ring.flatten),
                        style = Stroke(width = (0.5 + 3 * (1 - progress)).dp.toPx()),
                    )
                }
            }
        }

        style.ground?.let { ground ->
            MatchMomentGroundView(ground = ground, style = style, time = time, stage = stage)
        }

        if (style.scene == MatchMomentScene.SPRINT) {
            MatchMomentFinishTape(time = time, stage = stage, beats = beats)
            MatchMomentSpeedLines(side = -1, time = time, stage = stage, style = style)
            MatchMomentSpeedLines(side = 1, time = time, stage = stage, style = style)
        }

        MatchMomentPlayerCard(
            name = moment.viewerName,
            caption = L10n.string("You", "Ты"),
            imagePath = moment.viewerImagePath,
            tint = listOf(AppTheme.court, Color(0xFF1A4D3B)),
            side = -1,
            time = time,
            stage = stage,
            style = style,
        )
        MatchMomentPlayerCard(
            name = moment.playerName,
            caption = moment.playerName,
            imagePath = moment.playerImagePath,
            tint = listOf(AppTheme.clay, Color(0xFF854026)),
            side = 1,
            time = time,
            stage = stage,
            style = style,
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

        when (style.scene) {
            MatchMomentScene.RALLY -> MatchMomentProjectileView(rally = rally!!, time = time, stage = stage)
            MatchMomentScene.GLOVES -> {
                MatchMomentGloveView(side = -1, time = time, stage = stage, style = style)
                MatchMomentGloveView(side = 1, time = time, stage = stage, style = style)
            }
            MatchMomentScene.LIFT -> MatchMomentBarbellView(time = time, stage = stage, beats = beats)
            else -> MatchMomentSportBadge(
                sport = moment.sport,
                time = time,
                stage = stage,
                landing = beats.landing,
                gentle = beats.gentle,
            )
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
    style: MatchMomentStyle,
) {
    val beats = style.beats
    val pose = matchMomentPose(side, time, stage, style)
    val x = pose.x
    val rotation = pose.rotation

    // A hit (or the two cards colliding) lunges the card at the centre and squeezes it,
    // then springs back; the same hits flash it white.
    val hits = beats.hits(side)
    val swing = hits.sumOf { MatchMomentCurve.bump(time - it) }
    val flash = hits.sumOf { hit ->
        val since = time - hit
        if (since < 0) 0.0 else 0.35 * exp(-14 * since)
    }

    // Lifters sink and drive under the bar; on the mat the cards breathe.
    val stature: Float
    val girth: Float
    when (style.scene) {
        MatchMomentScene.LIFT -> {
            val squat = MatchMomentLift.squat(time, beats)
            stature = MatchMomentLift.stature(squat)
            girth = (1 + 0.03 * squat).toFloat()
        }
        MatchMomentScene.BREATHE -> {
            val calm = min(time, beats.settle)
            val fade = if (calm < beats.landing) 1.0 else exp(-2 * (calm - beats.landing))
            val breath = (1 + 0.025 * sin(2 * Math.PI * (calm - 0.35) / 1.6) * fade).toFloat()
            stature = breath
            girth = breath
        }
        else -> {
            stature = 1f
            girth = 1f
        }
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
private fun MatchMomentSportBadge(
    sport: Sport,
    time: Double,
    stage: MatchMomentStage,
    landing: Double,
    gentle: Boolean,
) {
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
 * The ground under the cards — court, track, ring, gym floor, mat or water — drawn in as
 * the scene opens and stepping back once the players leave for the centre.
 * Port of `ground(_:at:stage:style:)`.
 *
 * SwiftUI trims the markings path as it draws; here they fade in over the same window —
 * Compose has no cheap trim across a path of many contours.
 */
@Composable
private fun MatchMomentGroundView(
    ground: MatchMomentGround,
    style: MatchMomentStyle,
    time: Double,
    stage: MatchMomentStage,
) {
    val drawn = MatchMomentCurve.easeInOut((time - 0.1) / 0.7).toFloat()
    val stretched = MatchMomentCurve.easeInOut((time - 0.25) / 0.35).toFloat()
    val recede = (1 - 0.5 * MatchMomentCurve.easeInOut((time - style.groundRecedes) / 0.4)).toFloat()
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
            color = ground.surface.copy(alpha = 0.26f * drawn * recede),
            topLeft = Offset(rect.left, rect.top),
            size = Size(rect.width, rect.height),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(6.dp.toPx()),
        )
        val lines = if (style.scene == MatchMomentScene.RALLY) {
            matchMomentGroundLines(ground, rect)
        } else {
            matchMomentSceneGroundLines(ground, rect)
        }
        drawPath(
            path = lines,
            color = Color.White.copy(alpha = ground.lineOpacity * drawn * recede),
            style = Stroke(width = ground.lineWidth.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round),
        )

        ground.netWidth?.let { netWidth ->
            val netHeight = (height + 28.dp.toPx()) * stretched
            drawRoundRect(
                color = Color.White.copy(alpha = 0.45f * recede),
                topLeft = Offset(center.x - netWidth.dp.toPx() / 2, center.y - (height + 28.dp.toPx()) / 2),
                size = Size(netWidth.dp.toPx(), netHeight),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(netWidth.dp.toPx() / 2),
            )
        }

        when (ground) {
            // The water keeps moving until the timeline rests, then holds still.
            MatchMomentGround.WATER -> drawPath(
                path = matchMomentWaves(rect, min(time, style.beats.settle)),
                color = Color.White.copy(alpha = 0.3f * drawn * recede),
                style = Stroke(width = 1.5.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round),
            )
            // Corner posts: red and blue for the two corners, neutral white for the others.
            MatchMomentGround.RING -> listOf(
                Offset(rect.left, rect.top) to Color(0xFFDB3D33),
                Offset(rect.right, rect.top) to Color.White,
                Offset(rect.left, rect.bottom) to Color.White,
                Offset(rect.right, rect.bottom) to Color(0xFF336BDB),
            ).forEach { (corner, color) ->
                drawCircle(color.copy(alpha = 0.9f * drawn * recede), 6.dp.toPx(), corner)
            }
            // The squash front wall above the floor: its face, the out line and the tin.
            MatchMomentGround.SQUASH -> {
                val faceY = center.y + stage.wallY.dp.toPx() - 16.dp.toPx()
                val faceWidth = rect.width * stretched
                drawRect(
                    color = Color.White.copy(alpha = 0.1f * recede),
                    topLeft = Offset(center.x - faceWidth / 2, faceY - 16.dp.toPx()),
                    size = Size(faceWidth, 32.dp.toPx()),
                )
                listOf(faceY - 16.dp.toPx() to 2.dp.toPx(), faceY + 13.dp.toPx() to 3.dp.toPx()).forEach { (y, h) ->
                    drawRect(
                        color = AppTheme.clay.copy(alpha = 0.8f * recede),
                        topLeft = Offset(center.x - faceWidth / 2, y),
                        size = Size(faceWidth, h),
                    )
                }
            }
            else -> Unit
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

/** Where a card is, in stage units. Port of `pose(of:at:stage:style:)`. */
private data class MatchMomentPose(val x: Float, val y: Float, val rotation: Double)

private fun matchMomentPose(
    side: Int,
    time: Double,
    stage: MatchMomentStage,
    style: MatchMomentStyle,
): MatchMomentPose {
    val beats = style.beats
    val offstage = stage.offstageX.value * side
    val meet = style.meetX * side
    val settledTilt = side * style.settledTilt
    val entrance = if (side < 0) 0.05 else 0.12

    when (style.scene) {
        // Unhurried and without overshoot, straight to each other.
        MatchMomentScene.BREATHE -> {
            val drift = MatchMomentCurve.spring(time - entrance * 2, response = 1.4, damping = 0.9)
            return MatchMomentPose(
                x = (offstage + (meet - offstage) * drift).toFloat(),
                y = 0f,
                rotation = side * 12 + (settledTilt - side * 12) * drift,
            )
        }
        // Bobbing and rolling out of step with each other, calming once they touch; the
        // phase stops with the timeline so the final frame matches the last one.
        MatchMomentScene.FLOAT -> {
            val drift = MatchMomentCurve.spring(time - entrance, response = 1.0, damping = 0.82)
            val calm = min(time, beats.settle)
            val swell = if (calm < beats.landing) 1.0 else exp(-3 * (calm - beats.landing))
            val phase = 2 * Math.PI * calm / 1.7 + if (side < 0) 0.0 else 1.9
            return MatchMomentPose(
                x = (offstage + (meet - offstage) * drift).toFloat(),
                y = (5 * sin(phase) * swell).toFloat(),
                rotation = side * 10 + (settledTilt - side * 10) * drift + 3 * sin(phase + 0.8) * swell,
            )
        }
        // Straight in from off-screen, accelerating, bobbing each stride, leaning in.
        MatchMomentScene.SPRINT -> {
            val run = MatchMomentCurve.clamp((time - beats.converge) / (beats.landing - beats.converge))
            val finished = MatchMomentCurve.spring(time - beats.landing, response = 0.45, damping = 0.7)
            val stride = if (time < beats.landing) -8 * abs(sin(run * Math.PI * 5)) else 0.0
            val lean = -side * 10.0
            return MatchMomentPose(
                x = (offstage + (meet - offstage) * run * run).toFloat(),
                y = stride.toFloat(),
                rotation = lean + (settledTilt - lean) * finished,
            )
        }
        else -> Unit
    }

    val entered = MatchMomentCurve.spring(time - entrance, response = 0.55, damping = 0.74)
    val met = MatchMomentCurve.spring(time - beats.converge, response = 0.5, damping = 0.66)
    val baseline = stage.baselineX * side
    var x = offstage + (baseline - offstage) * entered
    x += (meet - x) * met
    var rotation = side * (14 + (4 - 14) * entered)
    rotation += (settledTilt - rotation) * met
    return MatchMomentPose(x.toFloat(), 0f, rotation)
}

/**
 * Stretched across the finish line like the net; the cards break it, and each half snaps
 * back to its post with a wobble. Port of `finishTape`.
 */
@Composable
private fun MatchMomentFinishTape(time: Double, stage: MatchMomentStage, beats: MatchMomentBeats) {
    val half = stage.courtHeight / 2 + 18
    val stretched = MatchMomentCurve.easeInOut((time - 0.25) / 0.35).toFloat()
    val broken = time - beats.landing
    val snap = if (broken < 0) 0.0 else MatchMomentCurve.spring(broken, response = 0.5, damping = 0.45)
    val wobble = if (broken < 0) 0.0 else 18 * exp(-5 * broken) * sin(20 * broken)
    val length = half * stretched
    val shrink = maxOf(0.14f, (1 - 0.86 * snap).toFloat())

    Canvas(modifier = Modifier.fillMaxSize()) {
        val center = Offset(stage.centerX.toPx(), stage.centerY.toPx())
        listOf(-1f, 1f).forEach { end ->
            drawCircle(
                color = Color.White.copy(alpha = 0.7f),
                radius = 4.5.dp.toPx(),
                center = Offset(center.x, center.y + (end * half).dp.toPx()),
            )
            rotate(
                degrees = (-wobble * end).toFloat(),
                pivot = Offset(center.x, center.y + (end * half).dp.toPx()),
            ) {
                val tapeLength = (length * shrink).dp.toPx()
                drawRoundRect(
                    color = MatchMomentPalette.ball,
                    topLeft = Offset(
                        center.x - 2.dp.toPx(),
                        center.y + (end * half).dp.toPx() - if (end < 0) 0f else tapeLength,
                    ),
                    size = Size(4.dp.toPx(), tapeLength),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
                )
            }
        }
    }
}

/** The air a sprinter drags behind them. Port of `speedLines`. */
@Composable
private fun MatchMomentSpeedLines(
    side: Int,
    time: Double,
    stage: MatchMomentStage,
    style: MatchMomentStyle,
) {
    val beats = style.beats
    val run = MatchMomentCurve.clamp((time - beats.converge) / (beats.landing - beats.converge))
    val strength = if (time < beats.landing) run else maxOf(0.0, 1 - (time - beats.landing) / 0.25)
    if (strength <= 0.001) return
    val pose = matchMomentPose(side, time, stage, style)
    val behind = side * (CARD_WIDTH_UNITS / 2 + 22)

    Canvas(modifier = Modifier.fillMaxSize()) {
        val center = Offset(stage.centerX.toPx(), stage.centerY.toPx())
        listOf(-38f, 4f, 42f).forEachIndexed { index, row ->
            val length = 30f + 14f * index
            val x = pose.x + behind + side * length / 2
            drawRoundRect(
                color = Color.White.copy(alpha = (0.4 * strength).toFloat()),
                topLeft = Offset(
                    center.x + (x - length / 2).dp.toPx(),
                    center.y + (pose.y + row).dp.toPx() - 1.5.dp.toPx(),
                ),
                size = Size(length.dp.toPx(), 3.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.5.dp.toPx()),
            )
        }
    }
}

/**
 * Each glove stays on its own boxer's side of the centre: they touch, not cross.
 * Port of `glove(of:at:stage:style:)`.
 */
@Composable
private fun MatchMomentGloveView(
    side: Int,
    time: Double,
    stage: MatchMomentStage,
    style: MatchMomentStyle,
) {
    val landing = style.beats.landing
    val contact = style.landingPoint(stage)
    val pose = matchMomentPose(side, time, stage, style)
    val appear = MatchMomentCurve.easeOut((time - (landing - 0.5)) / 0.2)
    if (appear <= 0.001) return

    val heldX = pose.x - side * 40
    val heldY = contact.y + 8
    val strikeX = side * 17f
    val restX = side * 23f
    val point: Offset
    if (time >= landing) {
        val recoil = MatchMomentCurve.spring(time - landing, response = 0.35, damping = 0.55).toFloat()
        point = Offset(strikeX + (restX - strikeX) * recoil, contact.y)
    } else {
        val punch = MatchMomentCurve.anticipate((time - (landing - 0.24)) / 0.24).toFloat()
        point = Offset(heldX + (strikeX - heldX) * punch, heldY + (contact.y - heldY) * punch)
    }
    val impact = (1 + 0.12 * MatchMomentCurve.bump(time - landing)).toFloat()
    val color = if (side < 0) Color(0xFFDB3D33) else Color(0xFF336BDB)

    Canvas(modifier = Modifier.fillMaxSize()) {
        val center = Offset(
            stage.centerX.toPx() + point.x.dp.toPx(),
            stage.centerY.toPx() + point.y.dp.toPx(),
        )
        scale(side * impact, impact, center) {
            // The wrist wrap, the mitt and the thumb.
            drawRoundRect(
                color = Color.White.copy(alpha = 0.92f * appear.toFloat()),
                topLeft = Offset(center.x - 17.dp.toPx() - 6.5.dp.toPx(), center.y - 12.dp.toPx()),
                size = Size(13.dp.toPx(), 24.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(5.dp.toPx()),
            )
            drawRoundRect(
                color = color.copy(alpha = appear.toFloat()),
                topLeft = Offset(center.x + 3.dp.toPx() - 19.dp.toPx(), center.y - 16.dp.toPx()),
                size = Size(38.dp.toPx(), 32.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(15.dp.toPx()),
            )
            drawRoundRect(
                color = color.copy(alpha = appear.toFloat()),
                topLeft = Offset(center.x + 1.dp.toPx() - 8.5.dp.toPx(), center.y - 12.dp.toPx() - 5.dp.toPx()),
                size = Size(17.dp.toPx(), 10.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(5.dp.toPx()),
            )
        }
    }
}

/** The bar dropping onto the cards, riding the squat and going overhead. Port of `barbell`. */
@Composable
private fun MatchMomentBarbellView(time: Double, stage: MatchMomentStage, beats: MatchMomentBeats) {
    val caught = beats.contacts[0].time
    val dropStart = caught - 0.3
    val appear = MatchMomentCurve.clamp((time - dropStart) / 0.08).toFloat()
    if (appear <= 0.001f) return

    val squat = MatchMomentLift.squat(time, beats)
    val press = MatchMomentLift.press(time, beats)
    val y = if (time < caught) {
        val fall = MatchMomentCurve.clamp((time - dropStart) / 0.3)
        val shoulders = MatchMomentLift.barY(0.0, 0.0)
        (-300 + (shoulders + 300) * (fall * fall)).toFloat()
    } else {
        MatchMomentLift.barY(squat, press)
    }
    val bend = (7 * (MatchMomentCurve.bump(time - caught) + 0.7 * MatchMomentCurve.bump(time - beats.landing))).toFloat()

    Canvas(modifier = Modifier.fillMaxSize()) {
        val center = Offset(stage.centerX.toPx(), stage.centerY.toPx() + y.dp.toPx())
        drawRoundRect(
            color = Color(0xFFB4B4B4).copy(alpha = appear),
            topLeft = Offset(center.x - 146.dp.toPx(), center.y - 3.dp.toPx()),
            size = Size(292.dp.toPx(), 6.dp.toPx()),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()),
        )
        listOf(-1f, 1f).forEach { side ->
            drawRoundRect(
                color = MatchMomentPalette.ball.copy(alpha = appear),
                topLeft = Offset(center.x + (side * 133 - 7).dp.toPx(), center.y + (bend - 29).dp.toPx()),
                size = Size(14.dp.toPx(), 58.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(4.dp.toPx()),
            )
            drawRoundRect(
                color = AppTheme.clay.copy(alpha = appear),
                topLeft = Offset(center.x + (side * 121 - 5).dp.toPx(), center.y + (bend * 0.8f - 21).dp.toPx()),
                size = Size(10.dp.toPx(), 42.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()),
            )
            drawRoundRect(
                color = Color(0xFFCCCCCC).copy(alpha = appear),
                topLeft = Offset(center.x + (side * 112 - 3).dp.toPx(), center.y + (bend * 0.6f - 8).dp.toPx()),
                size = Size(6.dp.toPx(), 16.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
            )
        }
    }
}
