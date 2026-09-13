package shop.sportsearch.app.core

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Port of the `extension MatchGameRequest` block in
 * ios/TennisSearchIOS/Core/AppModels.swift (lines 2944-3251) plus the presence
 * helpers on `DiscoverUser`.
 *
 * The status vocabulary here is load-bearing: `statusTintColor` and
 * `statusSurfaceColor` switch on the *rendered* label, exactly as the Swift
 * code does, so both clients colour a badge from the same string.
 */

val MatchGameRequest.isRegularOccurrence: Boolean
    get() = sourceType == "regular_occurrence"

val MatchGameRequest.proposedDate: Instant?
    get() = parseServerInstant(proposedDatetime)

private val MatchGameRequest.durationSeconds: Long
    get() = (durationMinutes ?: 90).toLong() * 60

fun MatchGameRequest.hasEnded(referenceDate: Instant = Instant.now()): Boolean {
    val start = proposedDate ?: return false
    return Duration.between(start, referenceDate).seconds >= durationSeconds
}

val MatchGameRequest.needsOutcomeReview: Boolean
    get() {
        val raw = status.lowercase()
        if (raw != "accepted" && raw != "approved") return false
        return outcome == null && hasEnded()
    }

val MatchGameRequest.canAddPhotoReport: Boolean
    get() {
        val raw = status.lowercase()
        if (raw != "accepted" && raw != "approved") return false
        return report == null && outcome != "not_played" && hasEnded()
    }

val MatchGameRequest.hasPhotoReport: Boolean
    get() = report != null

val MatchGameRequest.isArchivedForTimeline: Boolean
    get() {
        val raw = status.lowercase()
        if (raw in setOf("cancelled", "canceled", "declined", "rejected", "withdrawn")) return true
        if (needsOutcomeReview) return false
        val start = proposedDate ?: return false
        val postGameDisplayInterval = 2L * 60 * 60
        return Duration.between(start, Instant.now()).seconds >= durationSeconds + postGameDisplayInterval
    }

val MatchGameRequest.outcomeLabel: String?
    get() = when (outcome) {
        "played" -> L10n.string("Game played", "Игра прошла")
        "not_played" -> L10n.string("Not played", "Не сыграли")
        else -> null
    }

val MatchGameRequest.statusLabel: String
    get() {
        outcomeLabel?.let { return it }

        val start = proposedDate
        val now = Instant.now()

        return when (status.lowercase()) {
            "cancelled", "canceled", "declined", "rejected", "withdrawn" ->
                L10n.string("Canceled", "Отменена")

            "pending", "proposed" -> when {
                matchedUserId != null -> L10n.string("Awaiting confirmation", "Ждёт подтверждения")
                format == PlayFormat.DOUBLES || format == PlayFormat.BOTH ->
                    L10n.string("Finding players", "Подбор игроков")
                else -> L10n.string("Search", "Поиск")
            }

            "accepted", "approved" -> {
                if (start == null) return L10n.string("Game confirmed", "Игра подтверждена")

                val secondsUntilStart = Duration.between(now, start).seconds
                if (secondsUntilStart in 1..(2 * 60 * 60)) {
                    return L10n.string("Starting soon", "Скоро начнется")
                }

                val secondsSinceStart = Duration.between(start, now).seconds
                when {
                    secondsSinceStart in 0..(10 * 60) -> L10n.string("Game started", "Игра началась")
                    secondsSinceStart > 10 * 60 && secondsSinceStart < durationSeconds ->
                        L10n.string("Game in progress", "Игра идет")
                    secondsSinceStart >= durationSeconds -> L10n.string("Game ended", "Игра закончилась")
                    else -> L10n.string("Game confirmed", "Игра подтверждена")
                }
            }

            else -> L10n.string("Search", "Поиск")
        }
    }

val MatchGameRequest.nextStepLabel: String
    get() {
        val raw = status.lowercase()

        if (isRegularOccurrence && (raw == "accepted" || raw == "approved")) {
            return L10n.string(
                "The game is confirmed. Open the regular pair to change the next time slot.",
                "Игра подтверждена. Если нужно поменять следующий слот, открой регулярную пару.",
            )
        }

        return when (raw) {
            "pending", "proposed" ->
                if (matchedUserId != null) {
                    L10n.string(
                        "Proposal sent. Waiting for the other player's confirmation.",
                        "Предложение отправлено. Ждём подтверждение второго игрока.",
                    )
                } else {
                    L10n.string(
                        "Gather the players and turn this search into a scheduled game.",
                        "Нужно собрать состав и перевести поиск в конкретную игру.",
                    )
                }

            "accepted", "approved" -> L10n.string(
                "The game is confirmed. Open the chat to finalize the remaining details.",
                "Игра подтверждена. Дальше открой чат и договорись только о последних нюансах.",
            )

            "declined", "rejected", "withdrawn", "canceled", "cancelled" -> L10n.string(
                "This arrangement is no longer active. Start a new one if you still want to play.",
                "Эта договоренность уже не активна. Если всё ещё хочешь сыграть, начни новую.",
            )

            else -> L10n.string(
                "Open the details and continue toward your next game.",
                "Открой детали и продолжай путь к следующей игре.",
            )
        }
    }

fun MatchGameRequest.isPendingForRecipient(currentUserId: String?): Boolean {
    if (status.lowercase() != "pending" || currentUserId == null) return false
    return matchedUserId == currentUserId
}

fun MatchGameRequest.canCancel(currentUserId: String?): Boolean {
    if (currentUserId == null) return false
    return createdByUserId == currentUserId || matchedUserId == currentUserId
}

val DiscoverUser.lastActiveDate: Instant?
    get() = parseServerInstant(lastActiveAt)

/** Port of `DiscoverUser.isOnline` - active within the last five minutes. */
val DiscoverUser.isOnline: Boolean
    get() {
        val last = lastActiveDate ?: return false
        return Duration.between(last, Instant.now()).seconds <= 5 * 60
    }

/** Port of `DiscoverUser.presenceLabel`. */
val DiscoverUser.presenceLabel: String
    get() {
        val last = lastActiveDate ?: return L10n.string("Active recently", "Был недавно")
        if (isOnline) return L10n.string("Online", "Онлайн")

        val minutes = Duration.between(last, Instant.now()).toMinutes().toInt()
        if (minutes < 60) {
            val value = maxOf(minutes, 1)
            return L10n.string("Active $value min ago", "Был $value мин назад")
        }

        val zone = ZoneId.systemDefault()
        if (last.atZone(zone).toLocalDate() == LocalDate.now(zone)) {
            return L10n.string("Active at ${last.formattedHourMinute()}", "Был ${last.formattedHourMinute()}")
        }

        return L10n.string("Active on ${last.formattedDayMonth()}", "Был ${last.formattedDayMonth()}")
    }

/**
 * Port of `String.localizedMatchesText`. The backend hands these strings back
 * already written in Russian, so the English build translates them on the way
 * to the screen rather than at the call site.
 */
val String.localizedMatchesText: String
    get() {
        if (LocaleStore.current != AppLocale.EN) return this

        exactMatchesTranslations[this]?.let { return it }

        var value = this
        for ((russian, english) in matchesFragmentTranslations) {
            value = value.replace(russian, english)
        }
        return value
    }

private val exactMatchesTranslations = mapOf(
    "Новый мэтч" to "New match",
    "Нужно действие" to "Action needed",
    "Игра закончилась" to "Game ended",
    "Игра подтверждена" to "Game confirmed",
    "Ждёт подтверждения" to "Awaiting confirmation",
    "Ждем подтверждения" to "Awaiting confirmation",
    "Отменена" to "Canceled",
    "Поиск" to "Search",
    "Подбор игроков" to "Finding players",
    "Скоро начнется" to "Starting soon",
    "Игра началась" to "Game started",
    "Игра идет" to "Game in progress",
    "Игра прошла" to "Game played",
    "Не сыграли" to "Not played",
    "Одиночная" to "Singles",
    "Парная" to "Doubles",
    "Любой" to "Any",
    "Игрок уже отметил, что хочет с вами сыграть." to
        "This player has already said they would like to play with you.",
)

private val matchesFragmentTranslations = listOf(
    "Совпадает вид спорта" to "Same sport",
    "Подходит уровень" to "Compatible level",
    "Совпадает район" to "Same preferred area",
    "Совпадает время" to "Compatible availability",
    "Недалеко от вас" to "Near you",
)

/** Port of `extension RegularPairOccurrence`. */
val RegularPairOccurrence.statusLabel: String
    get() = when (status.lowercase()) {
        "confirmed" -> L10n.string("Confirmed", "Подтверждено")
        "declined" -> L10n.string("Someone can't make it", "Кто-то не может")
        "canceled", "cancelled" -> L10n.string("Canceled", "Отменено")
        "expired" -> L10n.string("Already passed", "Уже прошло")
        else -> L10n.string("Awaiting confirmation", "Ждёт подтверждения")
    }

/** Port of `extension GameRequestInvitee`. */
val GameRequestInvitee.statusLabel: String
    get() = when (status.lowercase()) {
        "accepted" -> L10n.string("Accepted", "Принял")
        "declined", "rejected" -> L10n.string("Declined", "Отклонил")
        "canceled", "cancelled", "withdrawn" -> L10n.string("Canceled", "Отменено")
        else -> L10n.string("Awaiting response", "Ожидаем ответ")
    }

/** Port of `GameRequestInvitee.statusTint`. */
val GameRequestInvitee.statusTintColor: androidx.compose.ui.graphics.Color
    get() = when (status.lowercase()) {
        "accepted" -> shop.sportsearch.app.ui.theme.AppTheme.court
        "declined", "rejected" -> androidx.compose.ui.graphics.Color.Red.copy(alpha = 0.88f)
        "canceled", "cancelled", "withdrawn" ->
            androidx.compose.ui.graphics.Color.Gray.copy(alpha = 0.82f)
        else -> androidx.compose.ui.graphics.Color(0xFFFFB34D)
    }

/** Port of `MatchGameRequest.visibleParticipants(currentUserId:)`. */
fun MatchGameRequest.visibleParticipants(currentUserId: String?): List<DiscoverUser> =
    participants.filter { currentUserId == null || it.id != currentUserId }.distinctBy { it.id }

/** Port of `MatchGameRequest.participantNamesLine(currentUserId:)`. */
fun MatchGameRequest.participantNamesLine(currentUserId: String?): String? =
    visibleParticipants(currentUserId)
        .map { it.displayName }
        .filter { it.isNotEmpty() }
        .takeIf { it.isNotEmpty() }
        ?.joinToString(", ")

/** Port of `MatchGameRequest.participantCount`. */
val MatchGameRequest.participantCount: Int
    get() = participants.distinctBy { it.id }.size

private fun MatchGameRequest.otherUser(currentUserId: String?): ChatSender? =
    if (createdByUserId == currentUserId) matchedUser else createdByUser

/** Port of `MatchGameRequest.upcomingDisplayName(currentUserId:)`. */
fun MatchGameRequest.upcomingDisplayName(currentUserId: String?): String {
    val people = visibleParticipants(currentUserId)

    if (people.size >= 3) {
        val first = people.first()
        val rest = people.size - 1
        return L10n.string("${first.displayName} and $rest more", "${first.displayName} и еще $rest")
    }
    if (people.size == 2) {
        return people.joinToString(L10n.string(" and ", " и ")) { it.displayName }
    }
    people.firstOrNull()?.let { return it.displayName }

    return otherUser(currentUserId)?.name ?: L10n.string("Player", "Игрок")
}

/** Port of `MatchGameRequest.upcomingAvatarURL(currentUserId:)`. */
fun MatchGameRequest.upcomingAvatarUrl(currentUserId: String?): String? =
    visibleParticipants(currentUserId).firstOrNull()?.avatarUrl ?: otherUser(currentUserId)?.avatarUrl

/** Port of `MatchGameRequest.startsInMinutesText(referenceDate:)`. */
fun MatchGameRequest.startsInMinutesText(referenceDate: Instant = Instant.now()): String? {
    val start = proposedDate ?: return null
    val secondsUntilStart = Duration.between(referenceDate, start).seconds
    if (secondsUntilStart <= 0) return null

    val totalMinutes = maxOf(Math.ceil(secondsUntilStart / 60.0).toInt(), 1)
    val days = totalMinutes / (24 * 60)
    val hours = (totalMinutes % (24 * 60)) / 60
    val minutes = totalMinutes % 60

    if (days > 0) {
        return if (hours > 0) {
            L10n.string("Game in ${days}d ${hours}h", "До игры $days д $hours ч")
        } else {
            L10n.string("Game in ${days}d", "До игры $days д")
        }
    }
    if (hours > 0) {
        return if (minutes > 0) {
            L10n.string("Game in ${hours}h ${minutes}min", "До игры $hours ч $minutes мин")
        } else {
            L10n.string("Game in ${hours}h", "До игры $hours ч")
        }
    }
    return L10n.string("Game in $minutes min", "До игры $minutes мин")
}

/** `participantsCountWord(_:)` in UpcomingGameCard. */
fun participantsCountWord(count: Int): String {
    if (LocaleStore.current == AppLocale.EN) return if (count == 1) "participant" else "participants"
    val mod10 = count % 10
    val mod100 = count % 100
    if (mod10 == 1 && mod100 != 11) return "участник"
    if (mod10 in 2..4 && mod100 !in 12..14) return "участника"
    return "участников"
}
