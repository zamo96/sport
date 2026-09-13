package shop.sportsearch.app.ui.components

import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.composed
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import shop.sportsearch.app.core.ChatReceipt
import shop.sportsearch.app.core.ChatReceiptAcknowledgements
import shop.sportsearch.app.core.displayLabel
import shop.sportsearch.app.data.TennisRepository
import shop.sportsearch.app.ui.theme.AppText

class ChatReceiptVisibility {
    private val rows = mutableMapOf<String, LayoutCoordinates>()

    fun remove(id: String) { rows.remove(id) }

    fun track(id: String, coordinates: LayoutCoordinates) { rows[id] = coordinates }

    fun visible(ids: Collection<String>): List<String> = ids.filter { id ->
        val row = rows[id]
        row != null && row.isAttached && row.boundsInWindow().let { it.width > 0 && it.height > 0 }
    }
}

fun Modifier.chatReceiptRow(tracker: ChatReceiptVisibility, id: String): Modifier = composed {
    DisposableEffect(tracker, id) {
        onDispose { tracker.remove(id) }
    }
    onGloballyPositioned { tracker.track(id, it) }
}

/** Delivery follows fetch; read follows an actually visible row in a foreground conversation. */
@Composable
fun rememberChatReceipts(
    repository: TennisRepository,
    matchId: String? = null,
    searchId: String? = null,
    incomingIds: List<String>,
    conversationVisible: Boolean,
): ChatReceiptVisibility {
    val tracker = remember(matchId, searchId) { ChatReceiptVisibility() }
    val acknowledgements = remember(matchId, searchId) { ChatReceiptAcknowledgements() }
    val latestIds = rememberUpdatedState(incomingIds)
    val latestVisible = rememberUpdatedState(conversationVisible)
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val window = LocalWindowInfo.current

    LaunchedEffect(repository, matchId, searchId, lifecycle) {
        while (isActive) {
            suspend fun acknowledge(ids: List<String>, status: String) {
                for (batch in acknowledgements.pending(ids, status).chunked(200)) {
                    // Recheck immediately before every network operation, including later batches.
                    if (status == "read" && (!latestVisible.value || !window.isWindowFocused ||
                            !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))) return
                    val actual = if (status == "read") tracker.visible(batch) else batch
                    if (actual.isEmpty()) continue
                    try {
                        repository.acknowledgeChatMessages(matchId, searchId, actual, status)
                        acknowledgements.confirmed(actual, status)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        // Retain pending IDs for retry without disrupting the conversation.
                    }
                }
            }
            acknowledge(latestIds.value, "delivered")
            if (latestVisible.value && window.isWindowFocused && lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                acknowledge(tracker.visible(latestIds.value), "read")
            }
            delay(1000)
        }
    }
    return tracker
}

@Composable
fun ChatReceiptLabel(receipt: ChatReceipt?, group: Boolean = false) {
    val marks = if (receipt?.status == "delivered" || receipt?.status == "read") "✓✓" else "✓"
    Text(
        "$marks ${receipt.displayLabel(group)}",
        style = AppText.caption2,
        color = if (receipt?.status == "read") Color(0xFFB9F6CA) else Color.White.copy(alpha = 0.72f),
    )
}
