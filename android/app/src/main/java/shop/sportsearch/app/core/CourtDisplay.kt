package shop.sportsearch.app.core

import java.net.URI

/**
 * Port of the `extension Court` block at the bottom of
 * ios/TennisSearchIOS/Views/CourtsView.swift.
 */

fun Court.sportsTitle(fallback: Sport?): String {
    val sports = supportedSports.ifEmpty { listOfNotNull(fallback) }
    return sports.ifEmpty { listOf(Sport.TENNIS) }.joinToString(" · ") { it.title }
}

val Court.displayAddress: String
    get() {
        val cityValue = city?.trim()
        if (cityValue.isNullOrEmpty()) return address
        if (address.contains(cityValue, ignoreCase = true)) return address
        return "$cityValue, $address"
    }

val Court.displayTags: List<String>
    get() {
        if (amenities.isNotEmpty()) return amenities.take(8)

        val tags = mutableListOf<String>()

        workingHours?.takeIf { it.isNotEmpty() }?.let {
            tags += L10n.string("Open: $it", "Открыто: $it")
        }

        val indoorSports = setOf(Sport.TENNIS, Sport.PADEL, Sport.BADMINTON, Sport.SQUASH, Sport.TABLE_TENNIS)
        if (supportedSports.any { it in indoorSports }) {
            tags += L10n.string("Indoor courts", "Крытые корты")
        }

        tags += L10n.string("Showers", "Душевые")
        tags += L10n.string("Parking", "Парковка")

        if (bookingLinkUrl != null) {
            tags += L10n.string("Online booking", "Онлайн-бронь")
        }

        return tags.take(6)
    }

val Court.detailDescription: String
    get() {
        about?.takeIf { it.trim().isNotEmpty() }?.let { return it }

        val sports = sportsTitle(null).lowercase()
        val place = metroDisplayName ?: localizedDistrictName(district)
            ?: L10n.string("Saint Petersburg", "Санкт-Петербурге")
        return L10n.string(
            "A club for $sports near $place. Contact details and the booking link are shown above " +
                "so you can quickly check availability.",
            "Клуб для игры в $sports рядом с $place. Контакты и ссылка на бронирование вынесены выше, " +
                "чтобы быстро связаться с клубом и уточнить свободное время.",
        )
    }

private fun validUrl(value: String?): String? {
    val trimmed = value?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    return runCatching { URI(trimmed) }.getOrNull()?.let { trimmed }
}

val Court.websiteLinkUrl: String? get() = validUrl(websiteUrl)
val Court.bookingLinkUrl: String? get() = validUrl(bookingUrl)
val Court.messengerLinkUrl: String? get() = validUrl(messengerUrl)

val Court.messengerTitle: String
    get() = when (messengerType?.lowercase()) {
        "telegram", "tg" -> "Telegram"
        "max" -> L10n.string("MAX", "МАКС")
        else -> L10n.string("Messenger", "Мессенджер")
    }

val Court.messengerSubtitle: String
    get() = if (messengerLinkUrl == null) {
        L10n.string("Not specified", "Не указан")
    } else {
        L10n.string("Message", "Написать")
    }

private fun hostLabel(url: String?): String? =
    url?.let { runCatching { URI(it).host }.getOrNull() }
        ?.takeIf { it.isNotEmpty() }
        ?.removePrefix("www.")

val Court.websiteHostLabel: String? get() = hostLabel(websiteLinkUrl)
val Court.bookingHostLabel: String? get() = hostLabel(bookingLinkUrl)

/**
 * Port of `playerPlural(_:)` / `activeSearchText(_:)`, duplicated in
 * CourtsView.swift on both the list card and the detail sheet.
 */
fun playerPlural(count: Int): String {
    if (count % 100 in 11..14) return "игроков"
    return when (count % 10) {
        1 -> "игрок"
        2, 3, 4 -> "игрока"
        else -> "игроков"
    }
}

fun activeSearchText(count: Int): String {
    if (LocaleStore.current == AppLocale.EN) {
        return if (count == 1) "1 player is looking for a game" else "$count players are looking for a game"
    }
    return "$count ${playerPlural(count)} ${if (count == 1) "ищет" else "ищут"} игру"
}
