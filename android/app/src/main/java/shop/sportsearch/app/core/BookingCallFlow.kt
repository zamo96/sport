package shop.sportsearch.app.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Port of `final class BookingCallFlow` in
 * ios/TennisSearchIOS/Core/BookingCallFlow.swift.
 *
 * The point of the state machine is to only ask "did you manage to book?" once
 * the user has actually left for the dialler and come back. iOS reads
 * `ScenePhase`; Android feeds it the same three beats from lifecycle callbacks.
 */
class BookingCallFlow {

    var isResultPresented by mutableStateOf(false)

    private var attemptId: Long? = null
    private var wasOpenAccepted = false
    private var didEnterBackground = false
    private var didReturnToActive = false
    private var timeoutJob: Job? = null

    /**
     * Call after handing the intent to the system. [accepted] is false when no
     * activity could handle it, which is the Android answer to the `openURL`
     * completion handler iOS gets.
     */
    fun start(scope: CoroutineScope, accepted: Boolean) {
        reset()

        val nextAttemptId = System.nanoTime()
        attemptId = nextAttemptId

        if (!accepted) {
            resetTracking()
            return
        }

        wasOpenAccepted = true
        presentResultIfReady()

        timeoutJob = scope.launch {
            delay(15_000)
            if (attemptId == nextAttemptId && !didEnterBackground) {
                resetTracking()
            }
        }
    }

    /** `handle(scenePhase:)` - the app went to the background. */
    fun onStopped() {
        if (attemptId == null) return
        didEnterBackground = true
        presentResultIfReady()
    }

    /** `handle(scenePhase:)` - the app came back to the foreground. */
    fun onResumed() {
        if (attemptId == null || !didEnterBackground) return
        didReturnToActive = true
        presentResultIfReady()
    }

    fun reset() {
        isResultPresented = false
        resetTracking()
    }

    private fun presentResultIfReady() {
        if (!wasOpenAccepted || !didEnterBackground || !didReturnToActive || isResultPresented) return
        resetTracking()
        isResultPresented = true
    }

    private fun resetTracking() {
        timeoutJob?.cancel()
        timeoutJob = null
        attemptId = null
        wasOpenAccepted = false
        didEnterBackground = false
        didReturnToActive = false
    }
}
