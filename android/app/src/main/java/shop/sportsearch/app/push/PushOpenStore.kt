package shop.sportsearch.app.push

import android.content.Context

/**
 * Push taps still waiting to be reported as `push_opened`. A tap from the tray
 * can cold-start the app before the session is restored, so the delivery id
 * waits here until AppViewModel has a signed-in user to report it for - the
 * `ios.push.opened.pending.ids` queue in NotificationManager.swift.
 *
 * Like on iOS it survives a logout: the server only stamps a delivery owned by
 * the reporting user, so a previous account's id is a harmless no-op, and
 * signing back in as the same player keeps the open.
 */
class PushOpenStore(context: Context) {
    private val prefs = context.getSharedPreferences("sportsearch.push", Context.MODE_PRIVATE)

    fun pending(): List<String> =
        prefs.getString(KEY, null)?.split(SEPARATOR)?.filter { it.isNotBlank() }.orEmpty()

    fun add(deliveryId: String) {
        val current = pending()
        if (deliveryId in current) return
        // Capped so a long offline stretch can't grow it without bound; the
        // oldest taps are the least useful ones to lose.
        save((current + deliveryId).takeLast(MAX_PENDING))
    }

    fun remove(deliveryId: String) = save(pending() - deliveryId)

    private fun save(ids: List<String>) {
        prefs.edit().putString(KEY, ids.joinToString(SEPARATOR)).apply()
    }

    private companion object {
        const val KEY = "push.opened.pending.ids"
        const val SEPARATOR = "\n"
        const val MAX_PENDING = 50
    }
}
