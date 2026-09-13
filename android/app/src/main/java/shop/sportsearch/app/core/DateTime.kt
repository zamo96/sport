package shop.sportsearch.app.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale as JavaLocale

/**
 * Date helpers ported from the `String`/`Date` extensions at the bottom of
 * ios/TennisSearchIOS/Core/AppModels.swift and APIClient.swift.
 */

/** `String.parsedISODateValue()` - accepts ISO-8601 with or without fractional seconds. */
fun parseServerInstant(value: String?): Instant? {
    if (value.isNullOrBlank()) return null
    return try {
        Instant.parse(value)
    } catch (_: DateTimeParseException) {
        try {
            java.time.OffsetDateTime.parse(value).toInstant()
        } catch (_: DateTimeParseException) {
            null
        }
    }
}

/** `Date.serverISOString()` - `.withInternetDateTime`, no fractional seconds. */
fun Instant.toServerISOString(): String =
    DateTimeFormatter.ISO_INSTANT.format(this.truncatedTo(java.time.temporal.ChronoUnit.SECONDS))

private fun localeForDisplay(): JavaLocale = JavaLocale.forLanguageTag(LocaleStore.current.code)

private fun formatter(pattern: String): DateTimeFormatter =
    DateTimeFormatter.ofPattern(pattern, localeForDisplay()).withZone(ZoneId.systemDefault())

/** `String.formattedDateTime()` - "d MMM, HH:mm". */
fun String.formattedDateTime(): String {
    val instant = parseServerInstant(this) ?: return this
    return formatter("d MMM, HH:mm").format(instant)
}

/** `String.formattedNumericDateTime()` - "dd.MM.yyyy HH:mm". */
fun String.formattedNumericDateTime(): String {
    val instant = parseServerInstant(this) ?: return this
    return formatter("dd.MM.yyyy HH:mm").format(instant)
}

/** `Date.formattedHourMinute()` - "HH:mm". */
fun Instant.formattedHourMinute(): String = formatter("HH:mm").format(this)

fun Instant.formattedDayMonth(): String = formatter("d MMM").format(this)

fun Instant.formattedWeekdayShort(): String = formatter("EEE").format(this)

/** `setLocalizedDateFormatFromTemplate("EEE, d MMMM")`, capitalised like iOS. */
fun Instant.formattedWeekdayDayMonth(): String = formatter("EEE, d MMMM").format(this).replaceFirstChar(Char::uppercase)

/** `setLocalizedDateFormatFromTemplate("EEEE, d MMMM")`, capitalised like iOS. */
fun Instant.formattedWeekdayDayMonthLong(): String =
    formatter("EEEE, d MMMM").format(this).replaceFirstChar(Char::uppercase)

/** `Date.formattedShortRelative()` in SearchesView.swift. */
fun Instant.formattedShortRelative(): String {
    val zone = ZoneId.systemDefault()
    val day = atZone(zone).toLocalDate()
    val today = java.time.LocalDate.now(zone)
    return when (day) {
        today -> LocaleAwareToday(formattedHourMinute())
        today.plusDays(1) -> LocaleAwareTomorrow(formattedHourMinute())
        else -> formatter("d MMM, HH:mm").format(this)
    }
}

private fun LocaleAwareToday(time: String) = L10n.string("Today, $time", "Сегодня, $time")
private fun LocaleAwareTomorrow(time: String) = L10n.string("Tomorrow, $time", "Завтра, $time")
