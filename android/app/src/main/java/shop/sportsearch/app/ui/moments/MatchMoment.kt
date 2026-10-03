package shop.sportsearch.app.ui.moments

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The shared language of the match moments, ported from `MatchMomentScenes.swift`:
 * everything here is a function of elapsed time, so a frame can be drawn from the clock
 * alone and the scene can be skipped to its end without unwinding animations.
 */
object MatchMomentCurve {
    fun clamp(value: Double): Double = value.coerceIn(0.0, 1.0)

    fun easeOut(value: Double): Double {
        val t = clamp(value)
        return 1 - (1 - t).pow(3)
    }

    fun easeInOut(value: Double): Double {
        val t = clamp(value)
        return if (t < 0.5) 4 * t * t * t else 1 - (-2 * t + 2).pow(3) / 2
    }

    /** Pulls back a little before it goes: a wind-up. */
    fun anticipate(value: Double): Double {
        val t = clamp(value)
        val overshoot = 1.7
        return t * t * ((overshoot + 1) * t - overshoot)
    }

    /**
     * Closed-form underdamped spring from 0 to 1, parameterised like SwiftUI's
     * `.spring(response:dampingFraction:)` so the numbers mean the same thing on both
     * platforms and the beats stay in sync.
     */
    fun spring(elapsed: Double, response: Double, damping: Double): Double {
        if (elapsed <= 0) return 0.0
        val omega = 2 * PI / response
        val decay = damping * omega
        val damped = omega * sqrt(1 - damping * damping)
        return 1 - exp(-decay * elapsed) * (cos(damped * elapsed) + decay / damped * sin(damped * elapsed))
    }

    /** A struck-and-released impulse: rises within ~60 ms, overshoots once, dies out. */
    fun bump(elapsed: Double): Double {
        if (elapsed < 0 || elapsed >= 0.8) return 0.0
        return exp(-9 * elapsed) * sin(24 * elapsed)
    }
}

object MatchMomentPalette {
    val ball = Color(0xFFD6FA57)
    val volleyballYellow = Color(0xFFFACC38)
    val volleyballBlue = Color(0xFF295CBD)
    val water = Color(0xFF73CCFF)
}

/**
 * What flies in the sports that throw something. Glow, trail and landing rings take its
 * colour; a black squash ball would vanish, so it borrows the brand yellow.
 */
enum class MatchMomentProjectile(
    val flightSize: Float,
    val accent: Color,
    val isShuttle: Boolean = false,
) {
    TENNIS_BALL(32f, MatchMomentPalette.ball),
    PADEL_BALL(30f, MatchMomentPalette.ball),
    SHUTTLECOCK(30f, Color.White, isShuttle = true),
    PING_PONG(18f, Color.White),
    VOLLEYBALL(34f, MatchMomentPalette.volleyballYellow),
    FOOTBALL(34f, Color.White),
    SQUASH_BALL(18f, MatchMomentPalette.ball);

    companion object {
        /** `MatchMomentRally(sport:)`: the sports without one play their own scene. */
        fun of(sport: Sport): MatchMomentProjectile? = when (sport) {
            Sport.TENNIS -> TENNIS_BALL
            Sport.PADEL -> PADEL_BALL
            Sport.BADMINTON -> SHUTTLECOCK
            Sport.TABLE_TENNIS -> PING_PONG
            Sport.VOLLEYBALL -> VOLLEYBALL
            Sport.FOOTBALL -> FOOTBALL
            Sport.SQUASH -> SQUASH_BALL
            Sport.RUNNING, Sport.BOXING, Sport.FITNESS, Sport.YOGA, Sport.SUPBOARD -> null
        }
    }
}

/** Draws the ball, shuttle or cork at [size] pixels, centred on [center]. */
fun DrawScope.drawProjectile(kind: MatchMomentProjectile, center: Offset, size: Float) {
    val radius = size / 2
    when (kind) {
        MatchMomentProjectile.TENNIS_BALL, MatchMomentProjectile.PADEL_BALL -> {
            drawCircle(MatchMomentPalette.ball, radius, center)
            val seam = Stroke(width = size * 0.08f)
            drawArc(
                color = Color.White.copy(alpha = 0.9f),
                startAngle = 40f,
                sweepAngle = 100f,
                useCenter = false,
                topLeft = Offset(center.x - radius * 0.88f, center.y - radius * 0.92f),
                size = Size(size * 0.88f, size * 0.92f),
                style = seam,
            )
            drawArc(
                color = Color.White.copy(alpha = 0.9f),
                startAngle = 220f,
                sweepAngle = 100f,
                useCenter = false,
                topLeft = Offset(center.x - radius * 0.88f, center.y - radius * 0.92f),
                size = Size(size * 0.88f, size * 0.92f),
                style = seam,
            )
        }
        MatchMomentProjectile.PING_PONG -> drawCircle(Color.White, radius, center)
        MatchMomentProjectile.SQUASH_BALL -> {
            drawCircle(Color(0xFF1A1A1A), radius, center)
            drawCircle(MatchMomentPalette.ball, radius * 0.22f, center.copy(y = center.y - radius * 0.3f))
        }
        MatchMomentProjectile.VOLLEYBALL -> {
            drawCircle(MatchMomentPalette.volleyballYellow, radius, center)
            val panel = Stroke(width = size * 0.09f)
            drawArc(
                color = MatchMomentPalette.volleyballBlue,
                startAngle = 110f,
                sweepAngle = 140f,
                useCenter = false,
                topLeft = Offset(center.x - radius, center.y - radius),
                size = Size(size, size),
                style = panel,
            )
            drawArc(
                color = Color.White,
                startAngle = 290f,
                sweepAngle = 140f,
                useCenter = false,
                topLeft = Offset(center.x - radius, center.y - radius),
                size = Size(size, size),
                style = panel,
            )
        }
        MatchMomentProjectile.FOOTBALL -> {
            drawCircle(Color.White, radius, center)
            drawCircle(Color(0xFF14181B), radius * 0.3f, center)
            repeat(5) { index ->
                val angle = PI * 2 * index / 5
                drawCircle(
                    color = Color(0xFF14181B),
                    radius = radius * 0.16f,
                    center = Offset(
                        center.x + (radius * 0.68f * cos(angle)).toFloat(),
                        center.y + (radius * 0.68f * sin(angle)).toFloat(),
                    ),
                )
            }
        }
        MatchMomentProjectile.SHUTTLECOCK -> {
            // Cork down, skirt up: the shuttle points where it flies.
            val skirt = Path().apply {
                moveTo(center.x - radius * 0.62f, center.y - radius)
                lineTo(center.x + radius * 0.62f, center.y - radius)
                lineTo(center.x + radius * 0.3f, center.y + radius * 0.25f)
                lineTo(center.x - radius * 0.3f, center.y + radius * 0.25f)
                close()
            }
            drawPath(skirt, Color.White.copy(alpha = 0.92f))
            drawPath(skirt, Color(0x33000000), style = Stroke(width = size * 0.05f))
            drawCircle(Color(0xFFE8C98A), radius * 0.32f, center.copy(y = center.y + radius * 0.52f))
        }
    }
}

/**
 * Port of `MatchMomentSportResolver`. The deck's sport filter wins: it is what the viewer
 * was browsing for. Otherwise the first sport both players list, in the viewer's own
 * order; then the other player's main sport, since theirs is the card that was liked;
 * then the viewer's; the fallback only when neither profile names a sport.
 */
fun matchMomentSport(
    deckFilter: Sport?,
    viewer: List<Sport>,
    player: List<Sport>,
    fallback: Sport = Sport.TENNIS,
): Sport {
    deckFilter?.let { return it }
    viewer.firstOrNull { player.contains(it) }?.let { return it }
    return player.firstOrNull() ?: viewer.firstOrNull() ?: fallback
}

/** Port of `MatchMomentCopy`: what the moment says, in the words of this sport. */
fun matchMomentTitle(sport: Sport): String = when (sport) {
    Sport.RUNNING -> L10n.string("You both want to run", "Вы оба хотите побегать")
    Sport.FITNESS, Sport.BOXING -> L10n.string("You both want to train", "Вы оба хотите потренироваться")
    Sport.YOGA -> L10n.string("You both want to practice", "Вы оба хотите позаниматься")
    Sport.SUPBOARD -> L10n.string("You both want to paddle", "Вы оба хотите покататься на сапе")
    Sport.TENNIS, Sport.PADEL, Sport.SQUASH, Sport.BADMINTON,
    Sport.TABLE_TENNIS, Sport.VOLLEYBALL, Sport.FOOTBALL,
    -> L10n.string("You both want to play", "Вы оба хотите сыграть")
}

fun matchMomentSubtitle(sport: Sport): String {
    val venueEn: String
    val venueRu: String
    when (sport) {
        Sport.TENNIS, Sport.PADEL, Sport.SQUASH, Sport.BADMINTON -> {
            venueEn = "court"; venueRu = "корте"
        }
        Sport.VOLLEYBALL -> {
            venueEn = "court"; venueRu = "площадке"
        }
        Sport.FOOTBALL -> {
            venueEn = "pitch"; venueRu = "поле"
        }
        Sport.RUNNING -> {
            venueEn = "route"; venueRu = "маршруте"
        }
        Sport.FITNESS, Sport.BOXING -> {
            venueEn = "gym"; venueRu = "зале"
        }
        Sport.TABLE_TENNIS, Sport.YOGA, Sport.SUPBOARD -> {
            venueEn = "place"; venueRu = "месте"
        }
    }
    return L10n.string(
        "Now agree on a time and a $venueEn.",
        "Осталось договориться о времени и $venueRu.",
    )
}

fun matchMomentAction(sport: Sport): String = when (sport) {
    Sport.RUNNING -> L10n.string("Plan the run", "Договориться о пробежке")
    Sport.FITNESS, Sport.BOXING -> L10n.string("Plan the session", "Договориться о тренировке")
    Sport.YOGA -> L10n.string("Plan the class", "Договориться о занятии")
    Sport.SUPBOARD -> L10n.string("Plan the trip", "Договориться о прогулке")
    Sport.TENNIS, Sport.PADEL, Sport.SQUASH, Sport.BADMINTON,
    Sport.TABLE_TENNIS, Sport.VOLLEYBALL, Sport.FOOTBALL,
    -> L10n.string("Plan the game", "Договориться об игре")
}

/** Headline once a game in this sport is agreed. Port of `MatchMomentCopy`. */
fun matchMomentConfirmedTitle(sport: Sport): String = when (sport) {
    Sport.RUNNING -> L10n.string("Run confirmed", "Пробежка подтверждена")
    Sport.FITNESS, Sport.BOXING -> L10n.string("Session confirmed", "Тренировка подтверждена")
    Sport.YOGA -> L10n.string("Class confirmed", "Занятие подтверждено")
    Sport.SUPBOARD -> L10n.string("Trip confirmed", "Прогулка подтверждена")
    Sport.TENNIS, Sport.PADEL, Sport.SQUASH, Sport.BADMINTON,
    Sport.TABLE_TENNIS, Sport.VOLLEYBALL, Sport.FOOTBALL,
    -> L10n.string("Game confirmed", "Игра подтверждена")
}

/** `MatchMomentBeats.rest` and `.landingFeel` for the sports that have their own scene. */
fun matchMomentRest(sport: Sport): Double = when (sport) {
    Sport.YOGA -> 2.1
    Sport.SUPBOARD -> 1.5
    else -> 1.23
}

/** A full celebration, or, where the scene is calm, a single soft success. */
fun matchMomentLandsGently(sport: Sport): Boolean = sport == Sport.YOGA || sport == Sport.SUPBOARD

enum class MatchMomentParticleKind { CONFETTI, SPLASH, MOTE }

/**
 * Port of `MatchMomentParticle`. The sets below are built with the same seeded generator
 * as iOS, so a burst looks the same on both platforms and screenshots stay comparable.
 */
data class MatchMomentParticle(
    val id: Int,
    val kind: MatchMomentParticleKind,
    val angle: Double,
    val speed: Double,
    val spin: Double,
    val delay: Double,
    val width: Float,
    val height: Float,
    val color: Color,
    val isRound: Boolean,
) {
    val lifetime: Double
        get() = when (kind) {
            MatchMomentParticleKind.CONFETTI -> 1.0
            MatchMomentParticleKind.SPLASH -> 0.9
            MatchMomentParticleKind.MOTE -> 1.8
        }

    fun offset(age: Double, origin: Offset): Offset = when (kind) {
        MatchMomentParticleKind.CONFETTI, MatchMomentParticleKind.SPLASH -> {
            val travel = speed * age
            val fall = 0.5 * (if (kind == MatchMomentParticleKind.SPLASH) 900.0 else 640.0) * age * age
            Offset(
                (origin.x + cos(angle) * travel).toFloat(),
                (origin.y + sin(angle) * travel + fall).toFloat(),
            )
        }
        MatchMomentParticleKind.MOTE -> {
            val sway = 8 * sin(age * 3 + id)
            Offset(
                (origin.x + cos(angle) * 90 + sway).toFloat(),
                (origin.y - speed * age).toFloat(),
            )
        }
    }

    fun opacity(age: Double): Double {
        val fadeStart = 0.55 * lifetime
        val fadeOut = 1 - maxOf(0.0, age - fadeStart) / (lifetime - fadeStart)
        return if (kind == MatchMomentParticleKind.MOTE) minOf(age / 0.3, 1.0) * fadeOut else fadeOut
    }

    companion object {
        /** Seeded, so every match bursts the same way; same constants as the Swift one. */
        private fun seeded(start: ULong): () -> Double {
            var seed = start
            return {
                seed = seed * 6_364_136_223_846_793_005UL + 1_442_695_040_888_963_407UL
                (seed shr 33).toDouble() / (1UL shl 31).toDouble()
            }
        }

        val confetti: List<MatchMomentParticle> = run {
            val next = seeded(0x5EED_BA11UL)
            val palette = listOf(
                MatchMomentPalette.ball, AppTheme.clay, AppTheme.mint,
                AppTheme.creamLight, MatchMomentPalette.ball,
            )
            (0 until 18).map { index ->
                val isRound = index % 3 == 0
                val length = 8 + 8 * next()
                MatchMomentParticle(
                    id = index,
                    kind = MatchMomentParticleKind.CONFETTI,
                    angle = -PI * (0.06 + 0.88 * next()),
                    speed = 190 + 170 * next(),
                    spin = (next() - 0.5) * 900,
                    delay = 0.12 * next(),
                    width = if (isRound) 7f else (length * 0.55).toFloat(),
                    height = if (isRound) 7f else length.toFloat(),
                    color = palette[index % palette.size],
                    isRound = isRound,
                )
            }
        }

        val splash: List<MatchMomentParticle> = run {
            val next = seeded(0x5A1_5A5UL)
            val palette = listOf(Color.White, MatchMomentPalette.water, Color(0xFFB3EDFF))
            (0 until 16).map { index ->
                val drop = (5 + 4 * next()).toFloat()
                MatchMomentParticle(
                    id = index,
                    kind = MatchMomentParticleKind.SPLASH,
                    angle = -PI * (0.18 + 0.64 * next()),
                    speed = 170 + 170 * next(),
                    spin = 0.0,
                    delay = 0.06 * next(),
                    width = drop,
                    height = drop,
                    color = palette[index % palette.size],
                    isRound = true,
                )
            }
        }

        val motes: List<MatchMomentParticle> = run {
            val next = seeded(0xB4EA_7EUL)
            val palette = listOf(AppTheme.mint, AppTheme.creamLight, MatchMomentPalette.ball.copy(alpha = 0.8f))
            (0 until 14).map { index ->
                val mote = (4 + 4 * next()).toFloat()
                MatchMomentParticle(
                    id = index,
                    kind = MatchMomentParticleKind.MOTE,
                    angle = PI * next(),
                    speed = 45 + 40 * next(),
                    spin = 0.0,
                    delay = 0.25 * next(),
                    width = mote,
                    height = mote,
                    color = palette[index % palette.size],
                    isRound = true,
                )
            }
        }

        /** Which burst a sport gets: breathing drifts, water splashes, everything else celebrates. */
        fun forSport(sport: Sport): List<MatchMomentParticle> = when (sport) {
            Sport.YOGA -> motes
            Sport.SUPBOARD -> splash
            else -> confetti
        }
    }
}

/** Port of `MatchMomentReveal`: fades up and settles the last 16 points. */
fun Modifier.matchMomentReveal(time: Double, start: Double): Modifier {
    val progress = MatchMomentCurve.easeOut((time - start) / 0.42)
    return alpha(progress.toFloat()).layout { measurable, constraints ->
        val placeable = measurable.measure(constraints)
        layout(placeable.width, placeable.height) {
            placeable.place(0, (16 * (1 - progress)).toInt())
        }
    }
}

/** Port of `MatchMomentPrimaryButtonStyle`. */
@Composable
fun MatchMomentPrimaryButton(
    text: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = MatchMomentPalette.ball,
            contentColor = AppTheme.ink,
            disabledContainerColor = MatchMomentPalette.ball,
            disabledContentColor = AppTheme.ink,
        ),
        modifier = modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(text, style = AppText.headlineBold, color = AppTheme.ink)
        }
    }
}

/** Rotates [block] by [degrees] around [pivot]. */
fun DrawScope.rotatedAround(degrees: Float, pivot: Offset, block: DrawScope.() -> Unit) {
    rotate(degrees, pivot) { block() }
}
