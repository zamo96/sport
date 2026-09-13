package shop.sportsearch.app.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Domain enums ported from ios/TennisSearchIOS/Core/AppModels.swift.
 * Wire values match the Swift `rawValue`s so both clients talk to the same API.
 */

@Serializable
enum class Sport(val wire: String) {
    @SerialName("table_tennis") TABLE_TENNIS("table_tennis"),
    @SerialName("tennis") TENNIS("tennis"),
    @SerialName("padel") PADEL("padel"),
    @SerialName("squash") SQUASH("squash"),
    @SerialName("badminton") BADMINTON("badminton"),
    @SerialName("volleyball") VOLLEYBALL("volleyball"),
    @SerialName("fitness") FITNESS("fitness"),
    @SerialName("boxing") BOXING("boxing"),
    @SerialName("yoga") YOGA("yoga"),
    @SerialName("football") FOOTBALL("football"),
    @SerialName("running") RUNNING("running"),
    @SerialName("supboard") SUPBOARD("supboard");

    val title: String
        get() = when (this) {
            TABLE_TENNIS -> L10n.string("Table tennis", "Настольный теннис")
            TENNIS -> L10n.string("Tennis", "Теннис")
            PADEL -> L10n.string("Padel", "Падел")
            SQUASH -> L10n.string("Squash", "Сквош")
            BADMINTON -> L10n.string("Badminton", "Бадминтон")
            VOLLEYBALL -> L10n.string("Volleyball", "Волейбол")
            FITNESS -> L10n.string("Fitness", "Фитнес")
            BOXING -> L10n.string("Boxing", "Бокс")
            YOGA -> L10n.string("Yoga", "Йога")
            FOOTBALL -> L10n.string("Football", "Футбол")
            RUNNING -> L10n.string("Running", "Бег")
            SUPBOARD -> L10n.string("SUP", "Сапборд")
        }

    companion object {
        fun from(value: String?): Sport? = entries.firstOrNull { it.wire == value }

        /** Port of `Sport.defaultAuthSports`: the order sports are offered in. */
        val defaultAuthSports: List<Sport> = listOf(
            TENNIS, PADEL, RUNNING, SUPBOARD, SQUASH, BADMINTON,
            TABLE_TENNIS, VOLLEYBALL, FITNESS, BOXING, YOGA, FOOTBALL,
        )
    }
}

/** Port of `struct SportPlaybook`. */
data class SportPlaybook(
    val allowedFormats: List<PlayFormat>,
    val defaultFormat: PlayFormat,
    val defaultDurationMinutes: Int,
    val defaultPlayersNeededByFormat: Map<PlayFormat, Int>,
    val maxPlayersNeeded: Int,
)

val Sport.playbook: SportPlaybook
    get() = when (this) {
        Sport.TENNIS -> SportPlaybook(
            allowedFormats = listOf(PlayFormat.SINGLES, PlayFormat.DOUBLES, PlayFormat.BOTH),
            defaultFormat = PlayFormat.SINGLES,
            defaultDurationMinutes = 90,
            defaultPlayersNeededByFormat = mapOf(PlayFormat.SINGLES to 1, PlayFormat.DOUBLES to 3, PlayFormat.BOTH to 1),
            maxPlayersNeeded = 8,
        )
        Sport.PADEL -> SportPlaybook(
            allowedFormats = listOf(PlayFormat.DOUBLES),
            defaultFormat = PlayFormat.DOUBLES,
            defaultDurationMinutes = 90,
            defaultPlayersNeededByFormat = mapOf(PlayFormat.SINGLES to 3, PlayFormat.DOUBLES to 3, PlayFormat.BOTH to 3),
            maxPlayersNeeded = 8,
        )
        Sport.BADMINTON -> SportPlaybook(
            allowedFormats = listOf(PlayFormat.SINGLES, PlayFormat.DOUBLES, PlayFormat.BOTH),
            defaultFormat = PlayFormat.BOTH,
            defaultDurationMinutes = 60,
            defaultPlayersNeededByFormat = mapOf(PlayFormat.SINGLES to 1, PlayFormat.DOUBLES to 3, PlayFormat.BOTH to 1),
            maxPlayersNeeded = 8,
        )
        Sport.TABLE_TENNIS, Sport.SQUASH -> SportPlaybook(
            allowedFormats = listOf(PlayFormat.SINGLES),
            defaultFormat = PlayFormat.SINGLES,
            defaultDurationMinutes = 60,
            defaultPlayersNeededByFormat = mapOf(PlayFormat.SINGLES to 1, PlayFormat.DOUBLES to 1, PlayFormat.BOTH to 1),
            maxPlayersNeeded = 8,
        )
        Sport.FOOTBALL -> SportPlaybook(
            allowedFormats = listOf(PlayFormat.DOUBLES),
            defaultFormat = PlayFormat.DOUBLES,
            defaultDurationMinutes = 90,
            defaultPlayersNeededByFormat = mapOf(PlayFormat.SINGLES to 9, PlayFormat.DOUBLES to 9, PlayFormat.BOTH to 9),
            maxPlayersNeeded = 12,
        )
        Sport.VOLLEYBALL -> SportPlaybook(
            allowedFormats = listOf(PlayFormat.DOUBLES),
            defaultFormat = PlayFormat.DOUBLES,
            defaultDurationMinutes = 90,
            defaultPlayersNeededByFormat = mapOf(PlayFormat.SINGLES to 5, PlayFormat.DOUBLES to 5, PlayFormat.BOTH to 5),
            maxPlayersNeeded = 12,
        )
        Sport.FITNESS, Sport.BOXING, Sport.YOGA, Sport.RUNNING, Sport.SUPBOARD -> SportPlaybook(
            allowedFormats = listOf(PlayFormat.SINGLES, PlayFormat.BOTH),
            defaultFormat = PlayFormat.SINGLES,
            defaultDurationMinutes = 60,
            defaultPlayersNeededByFormat = mapOf(PlayFormat.SINGLES to 1, PlayFormat.DOUBLES to 1, PlayFormat.BOTH to 1),
            maxPlayersNeeded = 8,
        )
    }

val Sport.allowedFormats: List<PlayFormat> get() = playbook.allowedFormats
val Sport.defaultFormat: PlayFormat get() = playbook.defaultFormat
val Sport.defaultDurationMinutes: Int get() = playbook.defaultDurationMinutes
val Sport.maxPlayersNeeded: Int get() = playbook.maxPlayersNeeded

fun Sport.resolveFormat(requested: PlayFormat): PlayFormat =
    if (allowedFormats.contains(requested)) requested else defaultFormat

fun Sport.defaultPlayersNeeded(format: PlayFormat): Int =
    playbook.defaultPlayersNeededByFormat[resolveFormat(format)] ?: 1

val Sport.venueTitle: String
    get() = when (this) {
        Sport.TENNIS, Sport.PADEL, Sport.BADMINTON, Sport.SQUASH -> L10n.string("Court", "Корт")
        Sport.TABLE_TENNIS -> L10n.string("Venue", "Зал")
        Sport.FOOTBALL, Sport.VOLLEYBALL -> L10n.string("Field", "Площадка")
        Sport.FITNESS, Sport.BOXING -> L10n.string("Gym", "Зал")
        Sport.YOGA -> L10n.string("Studio", "Студия")
        Sport.RUNNING, Sport.SUPBOARD -> L10n.string("Route", "Маршрут")
    }

val Sport.isRouteSport: Boolean get() = this == Sport.RUNNING || this == Sport.SUPBOARD
val Sport.routeFollowsRoads: Boolean get() = this == Sport.RUNNING

val Sport.routeDefaultTitle: String
    get() = if (this == Sport.SUPBOARD) {
        L10n.string("Water route", "Маршрут по воде")
    } else {
        L10n.string("Running route", "Маршрут бега")
    }

private enum class VenueNounGender { MASCULINE, FEMININE, NEUTER }

private val Sport.venueGender: VenueNounGender
    get() = when (venueTitle) {
        "Студия", "Площадка" -> VenueNounGender.FEMININE
        "Здание", "Место" -> VenueNounGender.NEUTER
        else -> VenueNounGender.MASCULINE
    }

val Sport.venueBookedTitle: String
    get() = if (LocaleStore.current == AppLocale.EN) {
        "$venueTitle already booked"
    } else {
        when (venueGender) {
            VenueNounGender.FEMININE -> "$venueTitle уже забронирована"
            VenueNounGender.NEUTER -> "$venueTitle уже забронировано"
            VenueNounGender.MASCULINE -> "$venueTitle уже забронирован"
        }
    }

/** Port of `Sport.venueFieldTitle` - the section title above the venue picker. */
/**
 * Port of the `Sport.purposeTitle` / `localizedPurposeTitle` pair in
 * MatchesView.swift - the genitive form used in "Ищет партнера для тенниса".
 */
val Sport.purposeTitle: String
    get() = when (this) {
        Sport.TABLE_TENNIS -> "настольного тенниса"
        Sport.TENNIS -> "тенниса"
        Sport.PADEL -> "падела"
        Sport.SQUASH -> "сквоша"
        Sport.BADMINTON -> "бадминтона"
        Sport.VOLLEYBALL -> "волейбола"
        Sport.FITNESS -> "фитнеса"
        Sport.BOXING -> "бокса"
        Sport.YOGA -> "йоги"
        Sport.FOOTBALL -> "футбола"
        Sport.RUNNING -> "бега"
        Sport.SUPBOARD -> "сапборда"
    }

val Sport.localizedPurposeTitle: String
    get() = when (this) {
        Sport.TABLE_TENNIS -> L10n.string("table tennis", purposeTitle)
        Sport.TENNIS -> L10n.string("tennis", purposeTitle)
        Sport.PADEL -> L10n.string("padel", purposeTitle)
        Sport.SQUASH -> L10n.string("squash", purposeTitle)
        Sport.BADMINTON -> L10n.string("badminton", purposeTitle)
        Sport.VOLLEYBALL -> L10n.string("volleyball", purposeTitle)
        Sport.FITNESS -> L10n.string("fitness", purposeTitle)
        Sport.BOXING -> L10n.string("boxing", purposeTitle)
        Sport.YOGA -> L10n.string("yoga", purposeTitle)
        Sport.FOOTBALL -> L10n.string("football", purposeTitle)
        Sport.RUNNING -> L10n.string("running", purposeTitle)
        Sport.SUPBOARD -> L10n.string("SUP", purposeTitle)
    }

val Sport.venueFieldTitle: String
    get() = venueTitle

val Sport.venuePendingTitle: String
    get() = L10n.string("$venueTitle to be selected", "$venueTitle подбирается")

val Sport.venueUnspecifiedTitle: String
    get() = L10n.string("$venueTitle to be confirmed", "$venueTitle уточняется")

val Sport.venueExistsTitle: String
    get() = L10n.string("$venueTitle available", "$venueTitle есть")

private val Sport.isTeamSport: Boolean get() = this == Sport.FOOTBALL || this == Sport.VOLLEYBALL

fun Sport.formatTitle(format: PlayFormat, playersNeeded: Int? = null): String {
    if (format == PlayFormat.BOTH) return L10n.string("Any", "Любой")

    val resolvedPlayersNeeded = playersNeeded ?: defaultPlayersNeeded(format)
    val isGroup = resolvedPlayersNeeded > 1

    if (isTeamSport) return L10n.string("Team", "Командная")

    return when (this) {
        Sport.FITNESS, Sport.BOXING, Sport.YOGA, Sport.RUNNING, Sport.SUPBOARD ->
            if (isGroup) L10n.string("Group", "Групповая") else L10n.string("Individual", "Индивидуально")
        else -> {
            if (isGroup && resolvedPlayersNeeded > 3) {
                L10n.string("Group", "Групповая")
            } else {
                when (format) {
                    PlayFormat.SINGLES -> if (isGroup) L10n.string("Group", "Групповая") else L10n.string("Singles", "Одиночная")
                    PlayFormat.DOUBLES -> if (resolvedPlayersNeeded > 3) L10n.string("Group", "Групповая") else L10n.string("Doubles", "Парная")
                    PlayFormat.BOTH -> L10n.string("Any", "Любой")
                }
            }
        }
    }
}

@Serializable
enum class SwipeAction(val wire: String) {
    @SerialName("like") LIKE("like"),
    @SerialName("dislike") DISLIKE("dislike"),
    @SerialName("superlike") SUPERLIKE("superlike"),
}

@Serializable
enum class PlayFormat(val wire: String) {
    @SerialName("singles") SINGLES("singles"),
    @SerialName("doubles") DOUBLES("doubles"),
    @SerialName("both") BOTH("both");

    val title: String
        get() = when (this) {
            SINGLES -> L10n.string("Singles", "Одиночный")
            DOUBLES -> L10n.string("Doubles", "Парный")
            BOTH -> L10n.string("Any", "Любой")
        }

    companion object {
        fun from(value: String?): PlayFormat? = entries.firstOrNull { it.wire == value }
    }
}

@Serializable
enum class Surface(val wire: String) {
    @SerialName("hard") HARD("hard"),
    @SerialName("clay") CLAY("clay"),
    @SerialName("grass") GRASS("grass"),
    @SerialName("any") ANY("any");

    val title: String
        get() = when (this) {
            HARD -> L10n.string("Hard", "Хард")
            CLAY -> L10n.string("Clay", "Грунт")
            GRASS -> L10n.string("Grass", "Трава")
            ANY -> L10n.string("Any", "Любое")
        }

    companion object {
        fun from(value: String?): Surface? = entries.firstOrNull { it.wire == value }
    }
}

@Serializable
enum class SearchType(val wire: String) {
    @SerialName("regular") REGULAR("regular"),
    @SerialName("hot") HOT("hot");

    val title: String
        get() = when (this) {
            REGULAR -> L10n.string("Regular", "Регулярный")
            HOT -> L10n.string("Urgent", "Срочный")
        }

    companion object {
        val userVisibleCases = listOf(HOT)
        fun from(value: String?): SearchType? = entries.firstOrNull { it.wire == value }
    }
}

@Serializable
enum class HotWindow(val wire: String) {
    @SerialName("today") TODAY("today"),
    @SerialName("tomorrow") TOMORROW("tomorrow"),
    @SerialName("day_after_tomorrow") DAY_AFTER_TOMORROW("day_after_tomorrow");

    val title: String
        get() = when (this) {
            TODAY -> L10n.string("Today", "Сегодня")
            TOMORROW -> L10n.string("Tomorrow", "Завтра")
            DAY_AFTER_TOMORROW -> L10n.string("Day after tomorrow", "Послезавтра")
        }

    companion object {
        fun from(value: String?): HotWindow? = entries.firstOrNull { it.wire == value }
    }
}

@Serializable
enum class TimeRange(val wire: String) {
    @SerialName("morning") MORNING("morning"),
    @SerialName("day") DAY("day"),
    @SerialName("evening") EVENING("evening");

    val title: String
        get() = when (this) {
            MORNING -> L10n.string("Morning", "Утро")
            DAY -> L10n.string("Afternoon", "День")
            EVENING -> L10n.string("Evening", "Вечер")
        }

    companion object {
        fun from(value: String?): TimeRange? = entries.firstOrNull { it.wire == value }
    }
}

@Serializable
enum class DayOfWeek(val wire: String) {
    @SerialName("monday") MONDAY("monday"),
    @SerialName("tuesday") TUESDAY("tuesday"),
    @SerialName("wednesday") WEDNESDAY("wednesday"),
    @SerialName("thursday") THURSDAY("thursday"),
    @SerialName("friday") FRIDAY("friday"),
    @SerialName("saturday") SATURDAY("saturday"),
    @SerialName("sunday") SUNDAY("sunday");

    val shortTitle: String
        get() = when (this) {
            MONDAY -> L10n.string("Mon", "Пн")
            TUESDAY -> L10n.string("Tue", "Вт")
            WEDNESDAY -> L10n.string("Wed", "Ср")
            THURSDAY -> L10n.string("Thu", "Чт")
            FRIDAY -> L10n.string("Fri", "Пт")
            SATURDAY -> L10n.string("Sat", "Сб")
            SUNDAY -> L10n.string("Sun", "Вс")
        }

    val title: String
        get() = when (this) {
            MONDAY -> L10n.string("Monday", "Понедельник")
            TUESDAY -> L10n.string("Tuesday", "Вторник")
            WEDNESDAY -> L10n.string("Wednesday", "Среда")
            THURSDAY -> L10n.string("Thursday", "Четверг")
            FRIDAY -> L10n.string("Friday", "Пятница")
            SATURDAY -> L10n.string("Saturday", "Суббота")
            SUNDAY -> L10n.string("Sunday", "Воскресенье")
        }

    companion object {
        fun from(value: String?): DayOfWeek? = entries.firstOrNull { it.wire == value }
    }
}

/** Port of `localizedTimePreferenceTitle`. */
fun localizedTimePreferenceTitle(value: String): String =
    localizedPairedTimePreference(value) ?: TimeRange.from(value)?.title ?: value

/** Port of `localizedTimePreferenceDetailTitle`. */
fun localizedTimePreferenceDetailTitle(value: String): String {
    localizedPairedTimePreference(value)?.let { return it }

    return when (TimeRange.from(value)) {
        TimeRange.MORNING -> L10n.string("Morning", "Утро")
        TimeRange.DAY -> L10n.string("Afternoon", "День")
        TimeRange.EVENING -> L10n.string("Evening (after 6:00 PM)", "Вечер (после 18:00)")
        null -> value
    }
}

private fun localizedPairedTimePreference(value: String): String? {
    val parts = value.split("@", limit = 2)
    if (parts.size != 2) return null
    val day = DayOfWeek.from(parts[0]) ?: return null
    return "${day.shortTitle} ${parts[1]}"
}

enum class DiscoverTab(val wire: String) {
    UPCOMING("upcoming"),
    SWIPE("swipe"),
    LIKES("likes"),
    SEEKING("seeking"),
    HOT("hot");

    val title: String
        get() = when (this) {
            UPCOMING -> L10n.string("Upcoming games", "Ближайшие игры")
            SWIPE -> L10n.string("Similar players", "Похожие игроки")
            LIKES -> L10n.string("Want to play with you", "Хотят с тобой поиграть")
            SEEKING -> L10n.string("Regular", "Регулярно")
            HOT -> L10n.string("Searches", "Поиски")
        }

    companion object {
        val userVisibleCases = listOf(UPCOMING, HOT, SWIPE, LIKES)
        fun from(value: String?): DiscoverTab? = entries.firstOrNull { it.wire == value }
    }
}

enum class AuthStep { INTRO, PROFILE, AVAILABILITY, EMAIL, CODE }

@Serializable
enum class Gender(val wire: String) {
    @SerialName("male") MALE("male"),
    @SerialName("female") FEMALE("female"),
    @SerialName("other") OTHER("other");

    val title: String
        get() = when (this) {
            MALE -> L10n.string("Man", "Мужчина")
            FEMALE -> L10n.string("Woman", "Женщина")
            OTHER -> L10n.string("Other", "Другое")
        }

    companion object {
        fun from(value: String?): Gender? = entries.firstOrNull { it.wire == value }
    }
}

enum class PlayerMediaKind(val wire: String) { PHOTO("photo"), VIDEO("video") }

data class PlayerMediaItem(val kind: PlayerMediaKind, val path: String) {
    val id: String get() = "${kind.wire}-$path"
}

@Serializable
enum class UserSafetyReason(val wire: String) {
    @SerialName("harassment") HARASSMENT("harassment"),
    @SerialName("hate_speech") HATE_SPEECH("hate_speech"),
    @SerialName("sexual_content") SEXUAL_CONTENT("sexual_content"),
    @SerialName("violence") VIOLENCE("violence"),
    @SerialName("spam") SPAM("spam"),
    @SerialName("impersonation") IMPERSONATION("impersonation"),
    @SerialName("other") OTHER("other");

    val title: String
        get() = when (this) {
            HARASSMENT -> L10n.string("Harassment or bullying", "Оскорбления или травля")
            HATE_SPEECH -> L10n.string("Hate speech", "Язык ненависти")
            SEXUAL_CONTENT -> L10n.string("Inappropriate content", "Неприемлемый контент")
            VIOLENCE -> L10n.string("Threats or violence", "Угрозы или насилие")
            SPAM -> L10n.string("Spam or fraud", "Спам или мошенничество")
            IMPERSONATION -> L10n.string("Impersonation", "Выдаёт себя за другого")
            OTHER -> L10n.string("Other reason", "Другая причина")
        }
}
