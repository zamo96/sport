package shop.sportsearch.app.ui.moments

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Route
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.MatchGameRequest
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.formattedHourMinute
import shop.sportsearch.app.core.formattedWeekdayDayMonthLong
import shop.sportsearch.app.core.parseServerInstant
import shop.sportsearch.app.core.upcomingAvatarUrl
import shop.sportsearch.app.core.upcomingDisplayName
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.time.Instant
import java.util.UUID
import kotlin.math.exp
import kotlin.math.min

/** The agreed game as the viewer sees it: the other side's name and photo, where, when. */
data class GameConfirmation(
    val id: String = UUID.randomUUID().toString(),
    val sport: Sport,
    val date: Instant?,
    val durationMinutes: Int?,
    /** Court name, or the route for a run. */
    val place: String?,
    val partnerName: String,
    val partnerImagePath: String?,
) {
    companion object {
        /** Port of `presentGameConfirmation(for:)` in AppModel.swift. */
        fun of(request: MatchGameRequest, currentUserId: String?): GameConfirmation {
            val route = request.runningRoute?.trim()
            return GameConfirmation(
                sport = request.sport,
                date = parseServerInstant(request.proposedDatetime),
                durationMinutes = request.durationMinutes,
                place = request.proposedCourt?.name ?: route?.takeIf { it.isNotEmpty() },
                partnerName = request.upcomingDisplayName(currentUserId),
                partnerImagePath = request.upcomingAvatarUrl(currentUserId),
            )
        }
    }
}

private object GameConfirmedBeat {
    const val DROP = 0.08
    /** The drop spring is ~95% down by now. */
    const val TICKET_LANDS = 0.43
    const val LAUNCH = 0.74
    const val IMPACT = 1.12
    const val COPY = IMPACT + 0.06
    const val ACTIONS = IMPACT + 0.26
    const val FINAL_FRAME = 10.0
}

/**
 * Full-screen moment when a game is agreed: the game drops in as a ticket, and the
 * sport's ball, shuttle or ball flies in and slams the "confirmed" stamp onto it; sports
 * without one get the stamp slammed down on its own.
 *
 * Port of `GameConfirmedOverlay.swift`. Driven by elapsed time rather than by animation
 * state, so the whole scene can be skipped to its last frame with a tap.
 */
@Composable
fun GameConfirmedOverlay(confirmation: GameConfirmation, onDone: () -> Unit) {
    val haptics = rememberAppHaptics()
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    var settled by remember(confirmation.id) { mutableStateOf(reduceMotion) }
    var time by remember(confirmation.id) {
        mutableStateOf(if (reduceMotion) GameConfirmedBeat.FINAL_FRAME else 0.0)
    }
    val projectile = remember(confirmation.sport) { MatchMomentProjectile.of(confirmation.sport) }
    val accent = projectile?.accent ?: when (confirmation.sport) {
        Sport.YOGA -> AppTheme.mint
        Sport.SUPBOARD -> MatchMomentPalette.water
        else -> MatchMomentPalette.ball
    }
    val settle = GameConfirmedBeat.IMPACT + matchMomentRest(confirmation.sport)

    LaunchedEffect(confirmation.id) {
        if (reduceMotion) {
            haptics.success()
            return@LaunchedEffect
        }
        val start = withFrameNanos { it }
        var ticketCue = false
        var launchCue = false
        var impactCue = false
        while (!settled) {
            val elapsed = (withFrameNanos { it } - start) / 1_000_000_000.0
            time = elapsed
            if (!ticketCue && elapsed >= GameConfirmedBeat.TICKET_LANDS) {
                haptics.impactLight()
                ticketCue = true
            }
            if (!launchCue && projectile != null && elapsed >= GameConfirmedBeat.LAUNCH) {
                haptics.selection()
                launchCue = true
            }
            if (!impactCue && elapsed >= GameConfirmedBeat.IMPACT) {
                if (matchMomentLandsGently(confirmation.sport)) haptics.success() else haptics.impactHeavy()
                impactCue = true
            }
            if (elapsed >= settle) {
                time = GameConfirmedBeat.FINAL_FRAME
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
            .pointerInput(confirmation.id) {
                detectTapToSkip {
                    if (!settled) {
                        if (time < GameConfirmedBeat.IMPACT) haptics.success()
                        time = GameConfirmedBeat.FINAL_FRAME
                        settled = true
                    }
                }
            },
    ) {
        val density = LocalDensity.current
        val layout = remember(maxWidth, maxHeight) {
            GameConfirmedLayout(width = maxWidth, height = maxHeight)
        }
        val stampPx = with(density) { Offset(layout.stampX.toPx(), layout.stampY.toPx()) }
        val particles = remember(confirmation.sport) { MatchMomentParticle.forSport(confirmation.sport) }
        val landed = time - GameConfirmedBeat.IMPACT

        // Glow under everything: the flash of the stamp landing, dying away.
        Canvas(modifier = Modifier.fillMaxSize()) {
            if (landed >= 0) {
                val strength = 0.1 + 0.26 * exp(-4 * landed)
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(accent.copy(alpha = strength.toFloat()), Color.Transparent),
                        center = stampPx,
                        radius = with(density) { 220.dp.toPx() },
                    ),
                    radius = with(density) { 220.dp.toPx() },
                    center = stampPx,
                )
            }
        }

        GameConfirmedTicket(
            confirmation = confirmation,
            time = time,
            layout = layout,
        )

        // Rings and confetti over the ticket.
        Canvas(modifier = Modifier.fillMaxSize()) {
            repeat(2) { index ->
                val progress = (landed - 0.1 * index) / 0.75
                if (progress in 0.0..1.0) {
                    drawCircle(
                        color = accent.copy(alpha = (0.55 * (1 - progress)).toFloat()),
                        radius = with(density) { (30 + 130 * MatchMomentCurve.easeOut(progress)).dp.toPx() },
                        center = stampPx,
                        style = Stroke(width = with(density) { (0.5 + 3 * (1 - progress)).dp.toPx() }),
                    )
                }
            }

            particles.forEach { particle ->
                val age = landed - particle.delay
                if (age >= 0 && age < particle.lifetime) {
                    val offset = particle.offset(age, stampPx)
                    val w = with(density) { particle.width.dp.toPx() }
                    val h = with(density) { particle.height.dp.toPx() }
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
                                cornerRadius = androidx.compose.ui.geometry.CornerRadius(
                                    with(density) { 2.dp.toPx() },
                                ),
                            )
                        }
                    }
                }
            }
        }

        GameConfirmedStamp(time = time, hasProjectile = projectile != null, layout = layout)

        if (projectile != null) {
            GameConfirmedFlight(kind = projectile, time = time, layout = layout)
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .padding(bottom = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(layout.copyTop))
            Text(
                matchMomentConfirmedTitle(confirmation.sport),
                style = AppText.titleBold,
                color = Color.White,
                textAlign = TextAlign.Center,
                modifier = Modifier.matchMomentReveal(time, GameConfirmedBeat.COPY),
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                L10n.string(
                    "You'll find it under Upcoming games on Home.",
                    "Всё будет в «Ближайших играх» на главной.",
                ),
                style = AppText.subheadlineSemibold,
                color = Color.White.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
                modifier = Modifier.matchMomentReveal(time, GameConfirmedBeat.COPY + 0.08),
            )
            Spacer(modifier = Modifier.weight(1f))
            MatchMomentPrimaryButton(
                text = L10n.string("Great", "Отлично"),
                enabled = time >= GameConfirmedBeat.ACTIONS,
                onClick = onDone,
                modifier = Modifier.matchMomentReveal(time, GameConfirmedBeat.ACTIONS),
            )
        }
    }
}

private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.detectTapToSkip(onTap: () -> Unit) {
    detectTapGestures { onTap() }
}

/** Port of `GameConfirmedLayout`. */
private class GameConfirmedLayout(width: Dp, height: Dp) {
    val ticketWidth: Dp = min(width.value - 56f, 330f).dp
    val ticketHeight: Dp = 214.dp
    val centerX: Dp
    val centerY: Dp
    val copyTop: Dp
    val launchX: Dp = (-40).dp
    val launchY: Dp
    val stampX: Dp
    val stampY: Dp

    init {
        // Ticket, gap and copy (≈ 350 dp) centred in the space above the button.
        val settledHeight = ticketHeight.value + 44 + 92
        val top = maxOf(70f, (height.value - 110 - settledHeight) / 2)
        centerX = (width.value / 2).dp
        centerY = (top + ticketHeight.value / 2).dp
        copyTop = (centerY.value + ticketHeight.value / 2 + 44).dp
        launchY = (centerY.value + ticketHeight.value / 2 + 240).dp
        // Straddling the ticket's top edge like a sticker, so it covers none of the
        // lines even for a long sport name.
        stampX = (centerX.value + ticketWidth.value / 2 - 70).dp
        stampY = (centerY.value - ticketHeight.value / 2 - 12).dp
    }
}

/** The agreed game as a ticket, dropping in from above with a little swing. */
@Composable
private fun GameConfirmedTicket(
    confirmation: GameConfirmation,
    time: Double,
    layout: GameConfirmedLayout,
) {
    val drop = MatchMomentCurve.spring(time - GameConfirmedBeat.DROP, response = 0.6, damping = 0.7)
    val jolt = MatchMomentCurve.bump(time - GameConfirmedBeat.IMPACT)
    val fallFrom = layout.centerY.value + layout.ticketHeight.value
    val y = layout.centerY.value - fallFrom * (1 - drop) + 8 * jolt

    Box(
        modifier = Modifier
            .offset(
                x = layout.centerX - layout.ticketWidth / 2,
                y = (y - layout.ticketHeight.value / 2).dp,
            )
            .width(layout.ticketWidth)
            .height(layout.ticketHeight)
            .scale((1 - 0.03 * jolt).toFloat())
            .rotate((-9 + 7 * drop - 2 * jolt).toFloat())
            .clip(GameConfirmedTicketShape)
            .background(AppTheme.creamLight),
    ) {
        Column(modifier = Modifier.padding(20.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.matchMomentReveal(time, 0.42),
            ) {
                Box(
                    modifier = Modifier.size(28.dp).clip(CircleShape).background(AppTheme.court),
                    contentAlignment = Alignment.Center,
                ) {
                    SportIconView(sport = confirmation.sport, color = Color.White, size = 16.dp)
                }
                Text(
                    confirmation.header(),
                    style = AppText.caption2Semibold,
                    color = AppTheme.ink.copy(alpha = 0.6f),
                    maxLines = 1,
                )
            }
            Spacer(modifier = Modifier.height(14.dp))
            Text(
                confirmation.dayLine(),
                style = AppText.headlineBold,
                color = AppTheme.ink,
                maxLines = 1,
                modifier = Modifier.matchMomentReveal(time, 0.48),
            )
            confirmation.timeLine()?.let { line ->
                Text(
                    line,
                    style = AppText.largeTitleBlack,
                    color = AppTheme.ink,
                    maxLines = 1,
                    modifier = Modifier.matchMomentReveal(time, 0.54),
                )
            }
        }

        // The perforation, and past it where and with whom.
        Canvas(modifier = Modifier.fillMaxSize()) {
            val y = TICKET_PERFORATION.toPx()
            val dash = androidx.compose.ui.graphics.PathEffect.dashPathEffect(
                floatArrayOf(6.dp.toPx(), 6.dp.toPx()),
            )
            drawLine(
                color = AppTheme.ink.copy(alpha = 0.18f),
                start = Offset(18.dp.toPx(), y),
                end = Offset(size.width - 18.dp.toPx(), y),
                strokeWidth = 1.5.dp.toPx(),
                pathEffect = dash,
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(horizontal = 20.dp, vertical = 16.dp)
                .matchMomentReveal(time, 0.6),
        ) {
            RemoteAvatarView(
                name = confirmation.partnerName,
                path = confirmation.partnerImagePath,
                size = 34.dp,
            )
            Column {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        if (confirmation.sport == Sport.RUNNING) Icons.Filled.Route else Icons.Filled.Place,
                        contentDescription = null,
                        tint = AppTheme.ink.copy(alpha = 0.6f),
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        confirmation.placeLine(),
                        style = AppText.subheadlineSemibold,
                        color = AppTheme.ink.copy(alpha = 0.75f),
                        maxLines = 1,
                    )
                }
                Text(
                    confirmation.partnerName,
                    style = AppText.subheadlineSemibold,
                    color = AppTheme.ink,
                    maxLines = 1,
                )
            }
        }
    }
}

private val TICKET_PERFORATION = 152.dp

/** A rounded ticket with a half-circle notch bitten out of each side at the perforation. */
private object GameConfirmedTicketShape : Shape {
    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val corner = with(density) { 22.dp.toPx() }
        val notch = with(density) { 11.dp.toPx() }
        val y = with(density) { TICKET_PERFORATION.toPx() }
        val path = Path().apply {
            moveTo(corner, 0f)
            lineTo(size.width - corner, 0f)
            quadraticBezierTo(size.width, 0f, size.width, corner)
            lineTo(size.width, y - notch)
            arcTo(
                rect = androidx.compose.ui.geometry.Rect(
                    left = size.width - notch,
                    top = y - notch,
                    right = size.width + notch,
                    bottom = y + notch,
                ),
                startAngleDegrees = -90f,
                sweepAngleDegrees = -180f,
                forceMoveTo = false,
            )
            lineTo(size.width, size.height - corner)
            quadraticBezierTo(size.width, size.height, size.width - corner, size.height)
            lineTo(corner, size.height)
            quadraticBezierTo(0f, size.height, 0f, size.height - corner)
            lineTo(0f, y + notch)
            arcTo(
                rect = androidx.compose.ui.geometry.Rect(
                    left = -notch,
                    top = y - notch,
                    right = notch,
                    bottom = y + notch,
                ),
                startAngleDegrees = 90f,
                sweepAngleDegrees = -180f,
                forceMoveTo = false,
            )
            lineTo(0f, corner)
            quadraticBezierTo(0f, 0f, corner, 0f)
            close()
        }
        return Outline.Generic(path)
    }
}

/**
 * Thrown sports: the stamp appears where the ball hits and springs down to size.
 * Others: it comes down from above the ticket and slams onto it.
 */
@Composable
private fun GameConfirmedStamp(time: Double, hasProjectile: Boolean, layout: GameConfirmedLayout) {
    val since = time - GameConfirmedBeat.IMPACT
    val scale: Double
    val opacity: Double
    if (hasProjectile) {
        scale = if (since < 0) 1.3 else 1.3 - 0.3 * MatchMomentCurve.spring(since, response = 0.3, damping = 0.6)
        opacity = MatchMomentCurve.clamp(since / 0.05)
    } else if (since < 0) {
        val slam = MatchMomentCurve.clamp((time - (GameConfirmedBeat.IMPACT - 0.16)) / 0.16)
        scale = 1.9 - 0.9 * slam * slam
        opacity = MatchMomentCurve.clamp(slam * 3)
    } else {
        scale = 1 - 0.06 * MatchMomentCurve.bump(since)
        opacity = 1.0
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .offset(x = layout.stampX - 70.dp, y = layout.stampY - 18.dp)
            .alpha(opacity.toFloat())
            .scale(scale.toFloat())
            .rotate(-12f)
            .clip(continuousShape(10.dp))
            .background(AppTheme.mint.copy(alpha = 0.92f))
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Icon(
            Icons.Filled.CheckCircle,
            contentDescription = null,
            tint = AppTheme.court,
            modifier = Modifier.size(14.dp),
        )
        Text(
            L10n.string("Confirmed", "Подтверждено").uppercase(),
            style = AppText.caption2Semibold,
            color = AppTheme.court,
        )
    }
}

/** The sport's ball arcs in from below and hits the stamp spot. */
@Composable
private fun GameConfirmedFlight(
    kind: MatchMomentProjectile,
    time: Double,
    layout: GameConfirmedLayout,
) {
    val start = GameConfirmedBeat.LAUNCH
    val end = GameConfirmedBeat.IMPACT
    if (time < start || time >= end + 0.05) return

    Canvas(modifier = Modifier.fillMaxSize()) {
        val u = min((time - start) / (end - start), 1.0)
        val arc = 4 * u * (1 - u)
        val from = Offset(layout.launchX.toPx(), layout.launchY.toPx())
        val to = Offset(layout.stampX.toPx(), layout.stampY.toPx())
        val position = Offset(
            from.x + (to.x - from.x) * u.toFloat(),
            from.y + (to.y - from.y) * u.toFloat() - 180.dp.toPx() * arc.toFloat(),
        )
        val dx = (to.x - from.x).toDouble()
        val dy = (to.y - from.y).toDouble() - 180.dp.toPx() * (4 - 8 * u)
        val rotation = if (kind.isShuttle) {
            Math.toDegrees(kotlin.math.atan2(dy, dx)).toFloat()
        } else {
            (time * 720).toFloat()
        }
        val alpha = 1 - MatchMomentCurve.clamp((time - end) / 0.05)

        rotate(rotation, position) {
            drawProjectileWithAlpha(kind, position, kind.flightSize.dp.toPx() * (1 + 0.25f * arc.toFloat()), alpha.toFloat())
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawProjectileWithAlpha(
    kind: MatchMomentProjectile,
    center: Offset,
    size: Float,
    alpha: Float,
) {
    if (alpha >= 1f) {
        drawProjectile(kind, center, size)
    } else {
        drawContext.canvas.saveLayer(
            androidx.compose.ui.geometry.Rect(
                center.x - size, center.y - size, center.x + size, center.y + size,
            ),
            androidx.compose.ui.graphics.Paint().apply { this.alpha = alpha },
        )
        drawProjectile(kind, center, size)
        drawContext.canvas.restore()
    }
}

private fun GameConfirmation.header(): String {
    val minutes = durationMinutes ?: return sport.title
    return sport.title + " · " + L10n.string("$minutes min", "$minutes мин")
}

private fun GameConfirmation.dayLine(): String =
    date?.formattedWeekdayDayMonthLong() ?: L10n.string("Time to be agreed", "Время уточняется")

private fun GameConfirmation.timeLine(): String? {
    val start = date ?: return null
    val end = start.plusSeconds(((durationMinutes ?: 90) * 60).toLong())
    return "${start.formattedHourMinute()} – ${end.formattedHourMinute()}"
}

private fun GameConfirmation.placeLine(): String = place
    ?: if (sport == Sport.RUNNING) {
        L10n.string("Route to be agreed", "Маршрут уточняется")
    } else {
        L10n.string("Place to be agreed", "Место уточняется")
    }
