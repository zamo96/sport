package shop.sportsearch.app.core

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Port of `struct UpcomingGamesWidgetPayload`. */
@Serializable
data class UpcomingGamesWidgetPayload(
    val updatedAtEpochSeconds: Long = 0,
    val games: List<UpcomingGamesWidgetGame> = emptyList(),
)

/** Port of `struct UpcomingGamesWidgetGame`. */
@Serializable
data class UpcomingGamesWidgetGame(
    val id: String,
    val title: String,
    val sportTitle: String,
    val startsAtEpochSeconds: Long? = null,
    val durationMinutes: Int? = null,
    val dateText: String,
    val timeText: String,
    val courtName: String,
    val courtAddress: String? = null,
    val statusLabel: String,
    val eventType: String? = null,
) {
    val isPersonalEvent: Boolean get() = eventType == "personal"

    val startsAt: Instant? get() = startsAtEpochSeconds?.let(Instant::ofEpochSecond)

    /** `UpcomingGamesWidgetGame.compactVenueLine`. */
    val compactVenueLine: String
        get() = courtName.trim().takeIf { it.isNotEmpty() }?.let { "$sportTitle · $it" } ?: sportTitle

    /** `UpcomingGamesWidgetGame.effectiveStatusLabel(referenceDate:)`. */
    fun effectiveStatusLabel(reference: Instant): String {
        val start = startsAt ?: return statusLabel
        if (statusLabel in TERMINAL_STATUS_LABELS) return statusLabel

        val durationSeconds = (durationMinutes ?: 90) * 60L
        val secondsUntilStart = start.epochSecond - reference.epochSecond
        if (secondsUntilStart > 0) {
            return if (secondsUntilStart <= 2 * 60 * 60) "Скоро начнется" else statusLabel
        }

        val secondsSinceStart = reference.epochSecond - start.epochSecond
        return when {
            secondsSinceStart <= 10 * 60 -> if (isPersonalEvent) "Визит начался" else "Игра началась"
            secondsSinceStart < durationSeconds -> if (isPersonalEvent) "Визит идет" else "Игра идет"
            else -> if (isPersonalEvent) "Визит завершён" else "Игра закончилась"
        }
    }

    /** `UpcomingGamesWidgetGame.compactStatusLabel(referenceDate:)`. */
    fun compactStatusLabel(reference: Instant): String =
        when (val label = effectiveStatusLabel(reference)) {
            "Ждём подтверждение", "Ждёт подтверждения", "Требуется ответ", "Ожидает подтверждения" -> "Ждём"
            "Игра подтверждена" -> "Подтв."
            "Скоро начнется" -> "Скоро"
            "Игра началась", "Визит начался" -> "Старт"
            "Игра идет", "Визит идет" -> "Идёт"
            "Игра закончилась" -> "Финиш"
            "Игра прошла" -> "Прошла"
            "Визит запланирован" -> "Визит"
            "Визит завершён" -> "Готово"
            else -> label
        }

    private companion object {
        val TERMINAL_STATUS_LABELS = setOf("Отменена", "Отменён", "Игра прошла", "Не сыграли", "Визит завершён")
    }
}

/**
 * Port of `enum UpcomingGamesWidgetStore`.
 *
 * iOS shares the payload with its widget extension through an App Group;
 * Android's widget runs in the same process, so plain SharedPreferences do.
 */
object UpcomingGamesWidgetStore {
    private const val PREFS_NAME = "sportsearch.widget"
    private const val PAYLOAD_KEY = "upcomingGamesWidget.payload.v1"
    private const val CURRENT_USER_ID_KEY = "upcomingGamesWidget.currentUserId.v1"

    private val json = Json { ignoreUnknownKeys = true }

    fun save(
        context: Context,
        gameRequests: List<MatchGameRequest>,
        personalActivities: List<PersonalActivity>,
        currentUserId: String?,
    ) {
        val gameItems = gameRequests
            .filterNot { it.isArchivedForTimeline }
            .map { request ->
                UpcomingGamesWidgetGame(
                    id = request.id,
                    title = request.upcomingDisplayName(currentUserId),
                    sportTitle = request.sport.title,
                    startsAtEpochSeconds = request.proposedDate?.epochSecond,
                    durationMinutes = request.durationMinutes,
                    dateText = widgetDateText(request.proposedDate),
                    timeText = widgetTimeText(request.proposedDate),
                    courtName = request.proposedCourt?.name ?: request.sport.venuePendingTitle,
                    courtAddress = request.proposedCourt?.address,
                    statusLabel = request.statusLabel,
                    eventType = "game",
                )
            }

        val personalItems = personalActivities
            .filterNot { it.isArchivedForTimeline }
            .map { activity ->
                UpcomingGamesWidgetGame(
                    id = activity.id,
                    title = "Личный визит",
                    sportTitle = activity.sport.title,
                    startsAtEpochSeconds = activity.scheduledInstant?.epochSecond,
                    durationMinutes = activity.durationMinutes,
                    dateText = widgetDateText(activity.scheduledInstant),
                    timeText = widgetTimeText(activity.scheduledInstant),
                    courtName = activity.court?.name ?: activity.sport.venuePendingTitle,
                    courtAddress = activity.court?.address,
                    statusLabel = activity.widgetStatusLabel,
                    eventType = "personal",
                )
            }

        val games = (gameItems + personalItems)
            .sortedBy { it.startsAtEpochSeconds ?: Long.MAX_VALUE }
            .take(3)

        write(context, UpcomingGamesWidgetPayload(Instant.now().epochSecond, games))
        prefs(context).edit().apply {
            if (currentUserId != null) putString(CURRENT_USER_ID_KEY, currentUserId)
            else remove(CURRENT_USER_ID_KEY)
        }.apply()
    }

    fun clear(context: Context) {
        write(context, UpcomingGamesWidgetPayload(Instant.now().epochSecond, emptyList()))
        prefs(context).edit().remove(CURRENT_USER_ID_KEY).apply()
    }

    fun load(context: Context): UpcomingGamesWidgetPayload {
        val raw = prefs(context).getString(PAYLOAD_KEY, null) ?: return UpcomingGamesWidgetPayload()
        return runCatching { json.decodeFromString<UpcomingGamesWidgetPayload>(raw) }
            .getOrDefault(UpcomingGamesWidgetPayload())
    }

    private fun write(context: Context, payload: UpcomingGamesWidgetPayload) {
        prefs(context).edit().putString(PAYLOAD_KEY, json.encodeToString(UpcomingGamesWidgetPayload.serializer(), payload)).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** `widgetDateText(for:)` - the widget is Russian-only on iOS too. */
    private fun widgetDateText(date: Instant?): String {
        if (date == null) return "Дата уточняется"
        val zone = ZoneId.systemDefault()
        val day = date.atZone(zone).toLocalDate()
        val today = LocalDate.now(zone)
        return when (day) {
            today -> "Сегодня"
            today.plusDays(1) -> "Завтра"
            else -> DateTimeFormatter.ofPattern("d MMM", Locale.forLanguageTag("ru")).format(date.atZone(zone))
        }
    }

    private fun widgetTimeText(date: Instant?): String {
        if (date == null) return "--:--"
        return DateTimeFormatter.ofPattern("HH:mm", Locale.forLanguageTag("ru")).format(date.atZone(ZoneId.systemDefault()))
    }
}

/** Port of `extension PersonalActivity.widgetStatusLabel`. */
val PersonalActivity.widgetStatusLabel: String
    get() = when (status.lowercase()) {
        "completed" -> "Визит завершён"
        "canceled", "cancelled" -> "Отменён"
        else -> if (hasEnded) "Визит завершён" else "Визит запланирован"
    }
