package shop.sportsearch.app.ui.moments

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.theme.AppTheme
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.min

/**
 * The rally half of `MatchMomentScenes.swift`: everything that makes a rally feel like
 * its sport — the ground, what flies, the path it takes, how fast and how high, and how
 * hard each contact lands in the hand.
 *
 * All geometry is in stage units (points relative to the stage centre), as on iOS; the
 * overlay converts to pixels when it draws.
 */
enum class MatchMomentFeel { LIGHT, SOFT, MEDIUM, RIGID }

/** -1 is the viewer's card, 1 the other player's, null a wall or the ground. */
data class MatchMomentContact(val time: Double, val hitter: Int?, val feel: MatchMomentFeel)

data class MatchMomentBeats(
    val contacts: List<MatchMomentContact>,
    val converge: Double,
    val landing: Double,
    val cardsTouch: Boolean,
    val rest: Double = 1.23,
    val gentle: Boolean = false,
) {
    val copy: Double get() = landing - 0.11
    val actions: Double get() = landing + 0.17

    /** Every spring, ring and particle has come to rest by now; the timeline pauses. */
    val settle: Double get() = landing + rest

    /** When this card strikes, plus the moment the two cards collide when they do. */
    fun hits(side: Int): List<Double> {
        val strikes = contacts.filter { it.hitter == side }.map { it.time }
        return if (cardsTouch) strikes + landing else strikes
    }

    companion object {
        val meet = MatchMomentBeats(emptyList(), converge = 0.3, landing = 0.6, cardsTouch = true)

        /** Serve, return, closing shot: the shape every net rally shares. */
        fun exchange(
            returnHit: Double,
            closingHit: Double,
            landing: Double,
            feel: MatchMomentFeel,
        ) = MatchMomentBeats(
            contacts = listOf(
                MatchMomentContact(0.55, -1, MatchMomentFeel.LIGHT),
                MatchMomentContact(returnHit, 1, feel),
                MatchMomentContact(closingHit, -1, feel),
            ),
            converge = closingHit + 0.05,
            landing = landing,
            cardsTouch = false,
        )
    }
}

enum class MatchMomentPath { OVER_NET, GROUND, OFF_WALL }

/**
 * Each ground turned sideways with the net upright. Net sports keep their real
 * proportions; `aspect` is length over width.
 */
enum class MatchMomentGround(
    val aspect: Float,
    val surface: Color,
    val lineOpacity: Float,
    val netWidth: Float?,
) {
    TENNIS(23.77f / 10.97f, AppTheme.court, 0.2f, 2.5f),
    PADEL(20f / 10f, Color(0xFF2961A8), 0.2f, 2.5f),
    BADMINTON(13.4f / 6.1f, Color(0xFF1F7566), 0.2f, 2.5f),
    TABLE_TENNIS(2.74f / 1.525f, Color(0xFF1F4D8F), 0.5f, 2.5f),
    VOLLEYBALL(18f / 9f, AppTheme.clay, 0.2f, 3.5f),
    SQUASH(2.1f, Color(0xFFC79E66), 0.2f, null),
    FOOTBALL(105f / 68f, Color(0xFF29803D), 0.2f, null);

    val lineWidth: Float get() = if (this == TABLE_TENNIS) 2.5f else 1.5f
}

/** Port of `MatchMomentRally`; null for the sports that play their own scene. */
data class MatchMomentRally(
    val ground: MatchMomentGround,
    val projectile: MatchMomentProjectile,
    val path: MatchMomentPath,
    val beats: MatchMomentBeats,
    /** Arc height per leg of the path; the last one is the closing shot. */
    val apex: List<Float>,
) {
    companion object {
        fun of(sport: Sport): MatchMomentRally? = when (sport) {
            Sport.TENNIS -> MatchMomentRally(
                MatchMomentGround.TENNIS, MatchMomentProjectile.TENNIS_BALL, MatchMomentPath.OVER_NET,
                MatchMomentBeats.exchange(0.83, 1.09, 1.47, MatchMomentFeel.RIGID), listOf(92f, 78f, 150f),
            )
            // Flatter and a touch quicker than tennis: the glass keeps rallies low.
            Sport.PADEL -> MatchMomentRally(
                MatchMomentGround.PADEL, MatchMomentProjectile.PADEL_BALL, MatchMomentPath.OVER_NET,
                MatchMomentBeats.exchange(0.8, 1.05, 1.42, MatchMomentFeel.RIGID), listOf(64f, 58f, 150f),
            )
            // The shuttle floats high and brakes hard, so the rally is the slowest.
            Sport.BADMINTON -> MatchMomentRally(
                MatchMomentGround.BADMINTON, MatchMomentProjectile.SHUTTLECOCK, MatchMomentPath.OVER_NET,
                MatchMomentBeats.exchange(0.95, 1.33, 1.76, MatchMomentFeel.SOFT), listOf(130f, 118f, 165f),
            )
            // Quick, low ticks across a small table.
            Sport.TABLE_TENNIS -> MatchMomentRally(
                MatchMomentGround.TABLE_TENNIS, MatchMomentProjectile.PING_PONG, MatchMomentPath.OVER_NET,
                MatchMomentBeats.exchange(0.73, 0.91, 1.24, MatchMomentFeel.LIGHT), listOf(34f, 30f, 120f),
            )
            Sport.VOLLEYBALL -> MatchMomentRally(
                MatchMomentGround.VOLLEYBALL, MatchMomentProjectile.VOLLEYBALL, MatchMomentPath.OVER_NET,
                MatchMomentBeats.exchange(0.92, 1.27, 1.68, MatchMomentFeel.MEDIUM), listOf(120f, 110f, 165f),
            )
            // Two passes along the grass, barely leaving it, then a chip onto the seal.
            Sport.FOOTBALL -> MatchMomentRally(
                MatchMomentGround.FOOTBALL, MatchMomentProjectile.FOOTBALL, MatchMomentPath.GROUND,
                MatchMomentBeats.exchange(0.86, 1.14, 1.52, MatchMomentFeel.MEDIUM), listOf(5f, 5f, 145f),
            )
            // Hit, wall, the other player: six contacts, the wall ones felt lighter.
            Sport.SQUASH -> MatchMomentRally(
                MatchMomentGround.SQUASH, MatchMomentProjectile.SQUASH_BALL, MatchMomentPath.OFF_WALL,
                MatchMomentBeats(
                    contacts = listOf(
                        MatchMomentContact(0.55, -1, MatchMomentFeel.RIGID),
                        MatchMomentContact(0.69, null, MatchMomentFeel.LIGHT),
                        MatchMomentContact(0.86, 1, MatchMomentFeel.RIGID),
                        MatchMomentContact(1.0, null, MatchMomentFeel.LIGHT),
                        MatchMomentContact(1.16, -1, MatchMomentFeel.RIGID),
                        MatchMomentContact(1.29, null, MatchMomentFeel.LIGHT),
                    ),
                    converge = 1.21,
                    landing = 1.54,
                    cardsTouch = false,
                ),
                listOf(8f, 36f, 60f),
            )
            Sport.RUNNING, Sport.BOXING, Sport.FITNESS, Sport.YOGA, Sport.SUPBOARD -> null
        }
    }

    /**
     * The path in stage units. Legs run back to back from the first contact to the
     * landing, one per gap between contacts.
     */
    fun legs(stage: MatchMomentStageGeometry): List<MatchMomentLeg> {
        val times = beats.contacts.map { it.time } + beats.landing
        val landing = stage.landing
        val stops: List<Offset>
        val heights: List<Float>
        when (path) {
            MatchMomentPath.OVER_NET -> {
                stops = listOf(stage.leftHit, stage.rightHit, stage.leftHit, landing)
                heights = apex
            }
            MatchMomentPath.GROUND -> {
                stops = listOf(stage.leftFoot, stage.rightFoot, stage.leftFoot, landing)
                heights = apex
            }
            MatchMomentPath.OFF_WALL -> {
                val wall = stage.wallY
                stops = listOf(
                    stage.leftHit, Offset(-58f, wall), stage.rightHit,
                    Offset(46f, wall), stage.leftHit, Offset(-8f, wall), landing,
                )
                // Flat into the wall, dropping on the way back, the last one onto the seal.
                heights = listOf(apex[0], apex[1], apex[0], apex[1], apex[0], apex[2])
            }
        }
        return (0 until stops.size - 1).map { index ->
            MatchMomentLeg(stops[index], stops[index + 1], times[index], times[index + 1], heights[index])
        }
    }
}

data class MatchMomentLeg(
    val from: Offset,
    val to: Offset,
    val start: Double,
    val end: Double,
    val apex: Float,
)

/** Where the ball, shuttle or cork is at a moment in the rally. */
data class MatchMomentFlight(
    val position: Offset,
    val size: Float,
    /** Grows toward the apex, as if coming closer. */
    val depth: Float,
    val rotation: Float,
    val squashX: Float,
    val squashY: Float,
    val isInFlight: Boolean,
) {
    companion object {
        fun state(time: Double, stage: MatchMomentStageGeometry, rally: MatchMomentRally): MatchMomentFlight? {
            val kind = rally.projectile
            val legs = rally.legs(stage)
            val first = legs[0]
            val toss = 0.12
            if (time < first.start - toss) return null

            if (time < first.start) {
                // A ball at the feet is simply there; anything else is tossed up to be hit.
                val up = MatchMomentCurve.easeOut((time - first.start + toss) / toss)
                val lift = if (kind.rolls) 0f else (18 * (1 - up)).toFloat()
                return MatchMomentFlight(
                    position = Offset(first.from.x, first.from.y + lift),
                    size = kind.flightSize * up.toFloat(),
                    depth = up.toFloat(),
                    rotation = if (kind.isShuttle) 90f else 0f,
                    squashX = 1f, squashY = 1f,
                    isInFlight = false,
                )
            }

            legs.firstOrNull { time < it.end }?.let { leg ->
                val u = (time - leg.start) / (leg.end - leg.start)
                val arc = 4 * u * (1 - u)
                val depth = 1 + 0.22 * arc * min(leg.apex / 60.0, 1.0)
                val position = position(leg, u, kind.isShuttle)
                return MatchMomentFlight(
                    position = position,
                    size = (kind.flightSize * depth).toFloat(),
                    depth = depth.toFloat(),
                    rotation = rotation(kind, time, position, leg, u),
                    squashX = 1f, squashY = 1f,
                    isInFlight = true,
                )
            }

            // Landed: a short hop, a squash that rings out, and it grows into the seal.
            // A shuttle doesn't squash; it swings round to stand cork down.
            val last = legs.last()
            val landed = time - last.end
            val ring = if (kind.isShuttle) 0.0 else exp(-8 * landed) * cos(26 * landed)
            val hop = 10 * exp(-7 * landed) * abs(kotlin.math.sin(11 * landed))
            val grow = MatchMomentCurve.spring(landed, response = 0.4, damping = 0.6)
            val settledRotation = if (kind.isShuttle) {
                val arrival = heading(last, 1.0)
                arrival + (90 - arrival) * MatchMomentCurve.spring(landed, response = 0.45, damping = 0.62)
            } else {
                val arrival = rotation(kind, last.end, last.to, last, 1.0).toDouble()
                arrival + 90 * (1 - exp(-5 * landed))
            }
            return MatchMomentFlight(
                position = Offset(last.to.x, last.to.y - hop.toFloat()),
                size = kind.flightSize + (kind.sealSize - kind.flightSize) * grow.toFloat(),
                depth = 1f,
                rotation = settledRotation.toFloat(),
                squashX = (1 + 0.26 * ring).toFloat(),
                squashY = (1 - 0.22 * ring).toFloat(),
                isInFlight = false,
            )
        }

        /** A shuttle points where it flies; a football turns as far as it rolls; balls spin. */
        private fun rotation(
            kind: MatchMomentProjectile,
            time: Double,
            position: Offset,
            leg: MatchMomentLeg,
            u: Double,
        ): Float {
            if (kind.isShuttle) return heading(leg, u).toFloat()
            if (kind.rolls) return (position.x * 360 / (Math.PI * kind.flightSize)).toFloat()
            return (time * 720).toFloat()
        }

        /**
         * Balls cross at constant speed under a parabola, so they read as thrown, not
         * tweened. A shuttle leaves fast and brakes, so its fall comes steeply at the end.
         */
        private fun position(leg: MatchMomentLeg, u: Double, shuttle: Boolean): Offset {
            val across = if (shuttle) 1 - (1 - u) * (1 - u) else u
            val arc = 4 * u * (1 - u)
            return Offset(
                leg.from.x + (leg.to.x - leg.from.x) * across.toFloat(),
                leg.from.y + (leg.to.y - leg.from.y) * u.toFloat() - leg.apex * arc.toFloat(),
            )
        }

        /** Direction of travel in degrees, for a shuttle whose cork leads. */
        private fun heading(leg: MatchMomentLeg, u: Double): Double {
            val dx = (leg.to.x - leg.from.x) * 2 * (1 - u)
            val dy = (leg.to.y - leg.from.y) - leg.apex * (4 - 8 * u)
            return Math.toDegrees(atan2(dy, max(abs(dx), 0.001) * (if (dx < 0) -1.0 else 1.0)))
        }

        private fun max(a: Double, b: Double) = if (a > b) a else b
    }
}

/** The stage's fixed points, in units relative to its centre. */
interface MatchMomentStageGeometry {
    val courtWidth: Float
    val courtHeight: Float
    val baselineX: Float

    /** Struck off the card's inner top corner, so the card reads as the racket. */
    val leftHit: Offset get() = Offset(-baselineX + CARD_WIDTH_UNITS / 2 - 2, -44f)
    val rightHit: Offset get() = Offset(baselineX - CARD_WIDTH_UNITS / 2 + 2, -44f)

    /** Kicked off the card's inner bottom corner, along the grass. */
    val leftFoot: Offset get() = Offset(-baselineX + CARD_WIDTH_UNITS / 2 + 4, 58f)
    val rightFoot: Offset get() = Offset(baselineX - CARD_WIDTH_UNITS / 2 - 4, 58f)

    /** The squash front wall's face, well above the cards. */
    val wallY: Float get() = -courtHeight / 2 - 58f

    /** The gap between the two cards' top corners once they meet. */
    val landing: Offset get() = Offset(0f, -CARD_HEIGHT_UNITS / 2 + 4)
}

const val CARD_WIDTH_UNITS = 116f
const val CARD_HEIGHT_UNITS = 148f

/**
 * The ground's markings, turned sideways with the net upright. Port of
 * `MatchMomentGroundLines`; only the grounds the rallies use are drawn here.
 */
fun matchMomentGroundLines(ground: MatchMomentGround, rect: Rect): Path = Path().apply {
    addRect(rect)
    when (ground) {
        MatchMomentGround.TENNIS -> {
            val singlesInset = rect.height * (10.97f - 8.23f) / 2 / 10.97f
            val serviceOffset = rect.width / 2 * 6.40f / 11.885f
            horizontal(rect, rect.top + singlesInset)
            horizontal(rect, rect.bottom - singlesInset)
            vertical(rect.center.x - serviceOffset, rect.top + singlesInset, rect.bottom - singlesInset)
            vertical(rect.center.x + serviceOffset, rect.top + singlesInset, rect.bottom - singlesInset)
            centre(rect, rect.center.x - serviceOffset, rect.center.x + serviceOffset)
            listOf(rect.left to 1f, rect.right to -1f).forEach { (x, direction) ->
                moveTo(x, rect.center.y)
                lineTo(x + 6 * direction, rect.center.y)
            }
        }
        MatchMomentGround.PADEL -> {
            val serviceOffset = rect.width / 2 * 6.95f / 10f
            vertical(rect.center.x - serviceOffset, rect.top, rect.bottom)
            vertical(rect.center.x + serviceOffset, rect.top, rect.bottom)
            centre(rect, rect.center.x - serviceOffset, rect.center.x + serviceOffset)
        }
        MatchMomentGround.BADMINTON -> {
            val singlesInset = rect.height * 0.46f / 6.1f
            val shortService = rect.width / 2 * 1.98f / 6.7f
            val longService = rect.width * 0.76f / 13.4f
            horizontal(rect, rect.top + singlesInset)
            horizontal(rect, rect.bottom - singlesInset)
            listOf(
                rect.center.x - shortService, rect.center.x + shortService,
                rect.left + longService, rect.right - longService,
            ).forEach { vertical(it, rect.top, rect.bottom) }
            centre(rect, rect.left, rect.center.x - shortService)
            centre(rect, rect.center.x + shortService, rect.right)
        }
        MatchMomentGround.TABLE_TENNIS -> centre(rect, rect.left, rect.right)
        MatchMomentGround.VOLLEYBALL -> {
            val attack = rect.width / 2 * 3f / 9f
            vertical(rect.center.x - attack, rect.top, rect.bottom)
            vertical(rect.center.x + attack, rect.top, rect.bottom)
        }
        MatchMomentGround.SQUASH -> {
            // The short line, the half-court line behind it and the two service boxes.
            val shortLine = rect.top + rect.height * 0.42f
            val box = rect.height * 0.3f
            horizontal(rect, shortLine)
            vertical(rect.center.x, shortLine, rect.bottom)
            addRect(Rect(rect.left, shortLine, rect.left + box, shortLine + box))
            addRect(Rect(rect.right - box, shortLine, rect.right, shortLine + box))
        }
        MatchMomentGround.FOOTBALL -> {
            val penaltyDepth = rect.width * 16.5f / 105f
            val penaltyWidth = rect.height * 40.32f / 68f
            val goalAreaDepth = rect.width * 5.5f / 105f
            val goalAreaWidth = rect.height * 18.32f / 68f
            val goalWidth = rect.height * 7.32f / 68f
            val circle = rect.height * 9.15f / 68f
            vertical(rect.center.x, rect.top, rect.bottom)
            addOval(
                Rect(
                    rect.center.x - circle, rect.center.y - circle,
                    rect.center.x + circle, rect.center.y + circle,
                ),
            )
            listOf(rect.left to 1f, rect.right to -1f).forEach { (edge, inward) ->
                val penaltyX = if (inward > 0) edge else edge - penaltyDepth
                val goalAreaX = if (inward > 0) edge else edge - goalAreaDepth
                val goalX = if (inward > 0) edge - 6 else edge
                addRect(Rect(penaltyX, rect.center.y - penaltyWidth / 2, penaltyX + penaltyDepth, rect.center.y + penaltyWidth / 2))
                addRect(Rect(goalAreaX, rect.center.y - goalAreaWidth / 2, goalAreaX + goalAreaDepth, rect.center.y + goalAreaWidth / 2))
                addRect(Rect(goalX, rect.center.y - goalWidth / 2, goalX + 6, rect.center.y + goalWidth / 2))
            }
        }
    }
}

private fun Path.horizontal(rect: Rect, y: Float) {
    moveTo(rect.left, y)
    lineTo(rect.right, y)
}

private fun Path.vertical(x: Float, from: Float, to: Float) {
    moveTo(x, from)
    lineTo(x, to)
}

/** The centre service line, drawn between two x positions. */
private fun Path.centre(rect: Rect, from: Float, to: Float) {
    moveTo(from, rect.center.y)
    lineTo(to, rect.center.y)
}
