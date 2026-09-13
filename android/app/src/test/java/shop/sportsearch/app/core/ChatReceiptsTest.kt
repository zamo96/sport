package shop.sportsearch.app.core

import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class ChatReceiptsTest {
    @Test fun legacyMessagesDecodeWithoutReceipts() {
        val json = """{"id":"m","senderUserId":"u","text":"","createdAt":"2026-09-08T12:00:00Z"}"""
        assertNull(Json.decodeFromString<ChatMessage>(json).receipt)
        assertNull(Json.decodeFromString<SearchLobbyMessage>(json).receipt)
    }

    @Test fun receiptOnlyRefreshUpdatesWithoutRegressingConfirmedStatus() {
        val read = ChatReceipt("read", 3, 2)
        assertEquals(read, mergeChatReceipt(read, ChatReceipt()))
        assertEquals(read, mergeChatReceipt(read, null))
        assertEquals(read, mergeChatReceipt(ChatReceipt(), read))
        assertEquals(ChatReceipt("read", 4, 2), mergeChatReceipt(read, ChatReceipt("delivered", 4, 0)))
    }

    @Test fun failedAcknowledgementsRemainPendingAndReadImpliesDelivery() {
        val state = ChatReceiptAcknowledgements()
        assertEquals(listOf("m"), state.pending(listOf("m", "m"), "read"))
        // A failed request never calls confirmed: the next attempt retains the same IDs.
        assertEquals(listOf("m"), state.pending(listOf("m"), "read"))
        state.confirmed(listOf("m"), "read")
        assertTrue(state.pending(listOf("m"), "read").isEmpty())
        assertTrue(state.pending(listOf("m"), "delivered").isEmpty())
        assertEquals(listOf("later"), state.pending(listOf("m", "later"), "read"))
    }

    @Test fun deliveryCanAdvanceToReadAndAnotherConversationHasIndependentState() {
        val state = ChatReceiptAcknowledgements()
        state.confirmed(listOf("m"), "delivered")
        assertEquals(listOf("m"), state.pending(listOf("m"), "read"))
        assertEquals(listOf("m"), ChatReceiptAcknowledgements().pending(listOf("m"), "delivered"))
    }
}
