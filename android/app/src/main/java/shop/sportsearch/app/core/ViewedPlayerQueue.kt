package shop.sportsearch.app.core

/**
 * Port of `struct ViewedPlayerQueue`.
 *
 * Players whose card has played through are moved to the back of the deck
 * rather than removed, so the tray can bring them back.
 */
data class ViewedPlayerQueue(val viewedIDs: List<String> = emptyList()) {
    fun orderedIDs(candidates: List<String>): List<String> {
        val available = candidates.toSet()
        val seen = viewedIDs.toSet()
        return candidates.filterNot { seen.contains(it) } + viewedIDs.filter { available.contains(it) }
    }

    fun newestViewedIDs(candidates: List<String>): List<String> {
        val available = candidates.toSet()
        return viewedIDs.reversed().filter { available.contains(it) }
    }

    fun deferPlayer(id: String): ViewedPlayerQueue = ViewedPlayerQueue(remove(id).viewedIDs + id)

    fun remove(id: String): ViewedPlayerQueue = ViewedPlayerQueue(viewedIDs.filterNot { it == id })
}
