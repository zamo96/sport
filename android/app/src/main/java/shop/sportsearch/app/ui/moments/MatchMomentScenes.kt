package shop.sportsearch.app.ui.moments

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.ui.theme.AppTheme
import kotlin.math.sin

/**
 * The scene a sport plays. Port of `MatchMomentStyle` in MatchMomentScenes.swift: the
 * sports that hit something play a rally, the rest have a scene of their own.
 */
enum class MatchMomentScene { RALLY, SPRINT, GLOVES, LIFT, BREATHE, FLOAT, MEET }

class MatchMomentStyle(val sport: Sport) {
    val rally: MatchMomentRally? = MatchMomentRally.of(sport)

    val scene: MatchMomentScene = when {
        rally != null -> MatchMomentScene.RALLY
        sport == Sport.RUNNING -> MatchMomentScene.SPRINT
        sport == Sport.BOXING -> MatchMomentScene.GLOVES
        sport == Sport.FITNESS -> MatchMomentScene.LIFT
        sport == Sport.YOGA -> MatchMomentScene.BREATHE
        sport == Sport.SUPBOARD -> MatchMomentScene.FLOAT
        else -> MatchMomentScene.MEET
    }

    val beats: MatchMomentBeats = when (scene) {
        MatchMomentScene.RALLY -> rally!!.beats
        MatchMomentScene.SPRINT -> MatchMomentBeats.sprint
        MatchMomentScene.GLOVES -> MatchMomentBeats.gloves
        MatchMomentScene.LIFT -> MatchMomentBeats.lift
        MatchMomentScene.BREATHE -> MatchMomentBeats.breathe
        MatchMomentScene.FLOAT -> MatchMomentBeats.float
        MatchMomentScene.MEET -> MatchMomentBeats.meet
    }

    /** Court, track, ring, gym floor, mat or water under the cards; the neutral scene draws none. */
    val ground: MatchMomentGround? = when (scene) {
        MatchMomentScene.RALLY -> rally!!.ground
        MatchMomentScene.SPRINT -> MatchMomentGround.TRACK
        MatchMomentScene.GLOVES -> MatchMomentGround.RING
        MatchMomentScene.LIFT -> MatchMomentGround.GYM
        MatchMomentScene.BREATHE -> MatchMomentGround.MAT
        MatchMomentScene.FLOAT -> MatchMomentGround.WATER
        MatchMomentScene.MEET -> null
    }

    /**
     * When the ground steps back to let the seal read. Where the players leave their
     * places for the centre that is when they go; where the whole scene is the approach
     * (the run, the drift, the water), only once they have arrived.
     */
    val groundRecedes: Double = when (scene) {
        MatchMomentScene.SPRINT, MatchMomentScene.BREATHE, MatchMomentScene.FLOAT -> beats.landing
        else -> beats.converge
    }

    val accent: Color = when (scene) {
        MatchMomentScene.RALLY -> rally!!.projectile.accent
        MatchMomentScene.BREATHE -> AppTheme.mint
        MatchMomentScene.FLOAT -> MatchMomentPalette.water
        else -> MatchMomentPalette.ball
    }

    /** Where the cards settle, left and right of the centre. */
    val meetX: Float = when (scene) {
        MatchMomentScene.GLOVES -> 84f
        MatchMomentScene.LIFT -> 60f
        MatchMomentScene.FLOAT -> 58f
        else -> 54f
    }

    val settledTilt: Double = when (scene) {
        MatchMomentScene.GLOVES -> 3.0
        MatchMomentScene.LIFT -> 2.0
        MatchMomentScene.FLOAT -> 5.0
        MatchMomentScene.BREATHE -> 6.0
        else -> 8.0
    }

    val particles: List<MatchMomentParticle> = when (scene) {
        MatchMomentScene.BREATHE -> MatchMomentParticle.motes
        MatchMomentScene.FLOAT -> MatchMomentParticle.splash
        else -> MatchMomentParticle.confetti
    }

    fun landingPoint(stage: MatchMomentStageGeometry): Offset = when (scene) {
        MatchMomentScene.GLOVES -> Offset(0f, -30f)
        MatchMomentScene.LIFT -> Offset(0f, MatchMomentLift.barY(squat = 0.0, press = 1.0))
        MatchMomentScene.FLOAT -> Offset(0f, 50f)
        else -> stage.landing
    }

    /** The waves out of the landing point. */
    val rings: List<MatchMomentRing> = when (scene) {
        MatchMomentScene.BREATHE -> listOf(0.2, 0.95).map {
            MatchMomentRing(it, 1.6, 110f, 1f, 0.28f)
        } + MatchMomentRing(beats.landing, 1.9, 170f, 1f, 0.4f)
        MatchMomentScene.FLOAT -> listOf(0.0, 0.18, 0.36).map {
            MatchMomentRing(beats.landing + it, 1.1, 170f, 0.34f, 0.55f)
        }
        else -> listOf(0.0, 0.1).map {
            MatchMomentRing(beats.landing + it, 0.75, 150f, 1f, 0.6f)
        }
    }
}

/** Height over width: 1 is a circle, less lays it flat on the water. */
data class MatchMomentRing(
    val start: Double,
    val duration: Double,
    val radius: Float,
    val flatten: Float,
    val strength: Float,
)

/** The barbell and the squat under it, as functions of time. Port of `MatchMomentLift`. */
object MatchMomentLift {
    const val PRESS_HEIGHT = 40f

    /**
     * Card height scale for a squat depth: 0 standing, 1 at the bottom, negative when the
     * legs drive through at lockout.
     */
    fun stature(squat: Double): Float = (1 - 0.1 * squat).toFloat()

    /**
     * The bar's centre relative to the stage centre: resting on the card tops, which are
     * anchored at their bottoms, lifted by the press.
     */
    fun barY(squat: Double, press: Double): Float =
        CARD_HEIGHT_UNITS / 2 - CARD_HEIGHT_UNITS * stature(squat) - 4 - PRESS_HEIGHT * press.toFloat()

    /** Catch dips, recover, one full squat, drive up through lockout, settle. */
    fun squat(time: Double, beats: MatchMomentBeats): Double {
        val caught = beats.contacts[0].time
        val landing = beats.landing
        if (time < caught) return 0.0
        if (time >= landing) {
            return -0.25 * (1 - MatchMomentCurve.spring(time - landing, response = 0.4, damping = 0.6))
        }
        val keys = listOf(
            caught to 0.0,
            caught + 0.07 to 0.45,
            caught + 0.2 to 0.05,
            landing - 0.3 to 1.0,
            landing to -0.25,
        )
        for (index in 1 until keys.size) {
            if (time < keys[index].first) {
                val from = keys[index - 1]
                val to = keys[index]
                val u = MatchMomentCurve.easeInOut((time - from.first) / (to.first - from.first))
                return from.second + (to.second - from.second) * u
            }
        }
        return -0.25
    }

    /** How far the bar has gone from the shoulders to overhead. */
    fun press(time: Double, beats: MatchMomentBeats): Double =
        MatchMomentCurve.easeOut((time - (beats.landing - 0.22)) / 0.22)
}

/** The water's lines are its waves, which move. Port of `MatchMomentWaves`. */
fun matchMomentWaves(rect: Rect, phase: Double): Path = Path().apply {
    val rows = 4
    val wavelength = 72.0
    for (row in 0 until rows) {
        val y = rect.top + rect.height * (row + 0.5f) / rows
        val drift = phase * 38 * (if (row % 2 == 0) 1.0 else -0.7) + row * 23
        fun crest(x: Float) = y + 4 * sin((x + drift) / wavelength * 2 * Math.PI).toFloat()
        var x = rect.left
        moveTo(x, crest(x))
        while (x < rect.right) {
            x = minOf(x + 6, rect.right)
            lineTo(x, crest(x))
        }
    }
}

/** The markings of the grounds that belong to the bespoke scenes. */
fun matchMomentSceneGroundLines(ground: MatchMomentGround, rect: Rect): Path = Path().apply {
    when (ground) {
        MatchMomentGround.MAT -> addRoundRect(
            androidx.compose.ui.geometry.RoundRect(
                rect,
                androidx.compose.ui.geometry.CornerRadius(rect.height * 0.18f),
            ),
        )
        MatchMomentGround.WATER -> Unit
        else -> addRect(rect)
    }
    when (ground) {
        // Lanes, and the finish line where the tape is stretched.
        MatchMomentGround.TRACK -> {
            for (lane in 1..3) {
                val y = rect.top + rect.height * lane / 4
                moveTo(rect.left, y)
                lineTo(rect.right, y)
            }
            moveTo(rect.center.x, rect.top)
            lineTo(rect.center.x, rect.bottom)
        }
        // Three ropes inside the apron.
        MatchMomentGround.RING -> listOf(9f, 18f).forEach { inset ->
            addRoundRect(
                androidx.compose.ui.geometry.RoundRect(
                    Rect(rect.left + inset, rect.top + inset, rect.right - inset, rect.bottom - inset),
                    androidx.compose.ui.geometry.CornerRadius(4f),
                ),
            )
        }
        // Rubber floor tiles.
        MatchMomentGround.GYM -> {
            for (column in 1 until 6) {
                val x = rect.left + rect.width * column / 6
                moveTo(x, rect.top)
                lineTo(x, rect.bottom)
            }
            for (row in 1 until 3) {
                val y = rect.top + rect.height * row / 3
                moveTo(rect.left, y)
                lineTo(rect.right, y)
            }
        }
        // The mat's end stripes.
        MatchMomentGround.MAT -> listOf(
            rect.left + rect.width * 0.09f,
            rect.right - rect.width * 0.09f,
        ).forEach { x ->
            moveTo(x, rect.top + 10)
            lineTo(x, rect.bottom - 10)
        }
        else -> Unit
    }
}
