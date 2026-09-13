package shop.sportsearch.app.core

import kotlinx.serialization.Serializable

@Serializable
data class ChatReceipt(
    val status: String = "sent",
    val deliveredCount: Int = 0,
    val readCount: Int = 0,
)

/** A stale refresh must never erase a confirmed receipt. */
fun mergeChatReceipt(previous: ChatReceipt?, incoming: ChatReceipt?): ChatReceipt? {
    if (previous == null) return incoming
    if (incoming == null) return previous
    val read = maxOf(previous.readCount, incoming.readCount)
    val delivered = maxOf(previous.deliveredCount, incoming.deliveredCount, read)
    val status = when {
        read > 0 || previous.status == "read" || incoming.status == "read" -> "read"
        delivered > 0 || previous.status == "delivered" || incoming.status == "delivered" -> "delivered"
        else -> "sent"
    }
    return ChatReceipt(status, delivered, read)
}

class ChatReceiptAcknowledgements {
    private val delivered = mutableSetOf<String>()
    private val read = mutableSetOf<String>()

    fun pending(ids: Collection<String>, status: String): List<String> =
        ids.distinct().filterNot { it in if (status == "read") read else delivered }

    fun confirmed(ids: Collection<String>, status: String) {
        delivered.addAll(ids)
        if (status == "read") read.addAll(ids)
    }
}

fun ChatReceipt?.displayLabel(group: Boolean): String {
    val receipt = this ?: ChatReceipt()
    return when (receipt.status) {
        "read" -> if (group) L10n.string("Read by: ${receipt.readCount}", "Прочитали: ${receipt.readCount}")
            else L10n.string("Read", "Прочитано")
        "delivered" -> if (group) L10n.string("Delivered to: ${receipt.deliveredCount}", "Доставлено: ${receipt.deliveredCount}")
            else L10n.string("Delivered", "Доставлено")
        else -> L10n.string("Sent", "Отправлено")
    }
}
