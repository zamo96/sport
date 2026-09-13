package shop.sportsearch.app.ui.components

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/**
 * Port of `enum AppHaptics`. iOS has dedicated selection/impact/notification
 * generators; Android maps them onto the closest HapticFeedbackConstants.
 */
class AppHaptics(private val view: View) {

    fun selection() = perform(HapticFeedbackConstants.CLOCK_TICK)

    fun impactLight() = perform(HapticFeedbackConstants.KEYBOARD_TAP)

    fun impactMedium() = perform(
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.CONFIRM
        } else {
            HapticFeedbackConstants.VIRTUAL_KEY
        },
    )

    fun impactHeavy() = perform(HapticFeedbackConstants.LONG_PRESS)

    fun success() = perform(
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.CONFIRM
        } else {
            HapticFeedbackConstants.VIRTUAL_KEY
        },
    )

    fun warning() = perform(
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.REJECT
        } else {
            HapticFeedbackConstants.LONG_PRESS
        },
    )

    /** `successCelebration()`: a short escalating pattern, same beats as iOS. */
    suspend fun successCelebration() {
        success()
        kotlinx.coroutines.delay(90)
        impactHeavy()
        kotlinx.coroutines.delay(110)
        impactMedium()
        kotlinx.coroutines.delay(120)
        selection()
    }

    private fun perform(constant: Int) {
        view.performHapticFeedback(constant)
    }
}

@Composable
fun rememberAppHaptics(): AppHaptics {
    val view = LocalView.current
    return remember(view) { AppHaptics(view) }
}
