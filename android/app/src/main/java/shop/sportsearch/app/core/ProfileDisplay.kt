package shop.sportsearch.app.core

import java.time.Instant

/**
 * Ports of the profile helpers that live as private methods on
 * `struct ProfileView` in ios/TennisSearchIOS/Views/ProfileView.swift.
 */

/** Port of `enum ProfileScreenMode`. */
enum class ProfileScreenMode {
    EDITING, PREVIEW;

    val title: String
        get() = when (this) {
            EDITING -> L10n.string("Editing", "Редактирование")
            PREVIEW -> L10n.string("Public preview", "Как видят другие")
        }
}

data class ProfileCompletionStatus(val percent: Int, val missingSteps: List<String>)

/** Port of `Sport.shortTitle` in ProfileView.swift. */
val Sport.shortTitle: String
    get() = if (this == Sport.TABLE_TENNIS) L10n.string("Table tennis", "Наст. теннис") else title

fun profileDistrictsEnabled(profile: UserProfile): Boolean {
    if (profile.location != null) return profile.coverage.districtsEnabled
    val city = SupportedCity.resolve(profile.city) ?: return false
    return SupportedCity.selectableCases.contains(city)
}

/** Port of `profileCompletionStatus(for:)`. */
fun profileCompletionStatus(profile: UserProfile): ProfileCompletionStatus {
    val coveredCity = SupportedCity.resolve(profile.city)
    val hasConfirmedCity = profile.location != null ||
        (coveredCity != null && SupportedCity.selectableCases.contains(coveredCity))
    val hasDistrict = !profile.district.isNullOrBlank() || profile.preferredDistricts.isNotEmpty()
    val hasLevels = profile.preferredSports.isNotEmpty() && profile.preferredSports.all { sport ->
        profile.sportLevels[sport.wire] != null || (sport == Sport.TENNIS && profile.tennisLevel != null)
    }
    val hasAvailability = profile.availabilityByDay.values.any { it.isNotEmpty() }
    val hasPhoto = !profile.avatarUrl.isNullOrBlank() || profile.profilePhotoUrls.isNotEmpty()

    val requirements = mutableListOf(
        !profile.name.isNullOrBlank() to L10n.string("Add your name", "Добавьте имя"),
        (profile.age != null) to L10n.string("Add your age", "Укажите возраст"),
        hasConfirmedCity to L10n.string("Choose a city", "Выберите город"),
        hasPhoto to L10n.string("Add a main photo", "Добавьте основное фото"),
        profile.preferredSports.isNotEmpty() to
            L10n.string("Choose at least one sport", "Выберите хотя бы один вид спорта"),
        hasLevels to L10n.string(
            "Set a level for your selected sports",
            "Укажите уровень для выбранных видов спорта",
        ),
        hasAvailability to L10n.string("Add convenient days and times", "Отметьте удобные дни и время"),
        !profile.bio.isNullOrBlank() to L10n.string("Tell others about yourself", "Расскажите о себе"),
    )

    if (profileDistrictsEnabled(profile) && coveredCity == SupportedCity.SAINT_PETERSBURG) {
        requirements += hasDistrict to L10n.string("Choose a district", "Выберите район Санкт-Петербурга")
    }

    val completed = requirements.count { it.first }
    val percent = Math.round(completed.toDouble() / requirements.size * 100).toInt()
    return ProfileCompletionStatus(percent, requirements.filterNot { it.first }.map { it.second })
}

fun sportsSummary(profile: UserProfile): String {
    if (profile.preferredSports.isEmpty()) {
        return L10n.string("No sports selected yet", "Виды спорта ещё не выбраны")
    }
    val count = profile.preferredSports.size
    return L10n.string("$count sports and levels", "$count вида спорта и уровни")
}

fun playLocationSummary(profile: UserProfile): String {
    val districts = profile.preferredDistricts.ifEmpty { listOfNotNull(profile.district) }
    if (districts.isEmpty()) {
        return L10n.string("Districts and favorite clubs are not set", "Районы и любимые клубы не указаны")
    }
    return L10n.string("${districts.size} districts, favorite clubs", "${districts.size} района, любимые клубы")
}

fun activitySummary(profile: UserProfile): String =
    if (profile.isLookingForGame) {
        L10n.string("Looking for a game now", "Ищешь игру сейчас")
    } else {
        L10n.string("No active searches", "Активных поисков нет")
    }

fun enabledNotificationCount(profile: UserProfile): Int =
    listOf(profile.notificationMatches, profile.notificationMessages, profile.notificationGames).count { it }

fun notificationsSummary(profile: UserProfile): String {
    val enabled = enabledNotificationCount(profile)
    if (enabled == 0) return L10n.string("All events are disabled", "Все события выключены")
    return L10n.string(
        "$enabled of 3 events, sound ${if (profile.notificationSound) "on" else "off"}",
        "$enabled из 3 событий, звук ${if (profile.notificationSound) "включён" else "выключен"}",
    )
}

fun availabilityHeadline(availabilityByDay: Map<String, List<String>>): String {
    if (availabilityByDay.isEmpty()) return L10n.string("Play time is not set", "Время игры не указано")
    val ranges = availabilityByDay.values.flatten().toSet()
        .mapNotNull { TimeRange.from(it)?.title?.lowercase() }.sorted().joinToString(", ")
    val daysCount = availabilityByDay.count { it.value.isNotEmpty() }
    return L10n.string("$daysCount days, $ranges", "$daysCount дней, $ranges")
}

fun activeProfileDistricts(profile: UserProfile): List<String> =
    profile.preferredDistricts.ifEmpty { listOfNotNull(profile.district).filter { it.isNotEmpty() } }

/** Port of `enum ProfileGameFeedItem`. */
sealed interface ProfileGameFeedItem {
    data class Game(val request: MatchGameRequest) : ProfileGameFeedItem
    data class Visit(val activity: PersonalActivity) : ProfileGameFeedItem

    val id: String
        get() = when (this) {
            is Game -> "game-${request.id}"
            is Visit -> "visit-${activity.id}"
        }

    val date: Instant
        get() = when (this) {
            is Game -> request.proposedDate ?: Instant.EPOCH
            is Visit -> activity.scheduledInstant ?: Instant.EPOCH
        }

    companion object {
        fun make(
            games: List<MatchGameRequest>,
            visits: List<PersonalActivity>,
            ownerID: String,
            referenceDate: Instant = Instant.now(),
        ): List<ProfileGameFeedItem> {
            val gameItems = games.filter { request ->
                if (!request.hasEnded(referenceDate)) return@filter false
                request.report?.let { return@filter it.visibility == "profile" }
                request.outcome == "played"
            }.map(ProfileGameFeedItem::Game)

            val visitItems = visits.filter { activity ->
                if (activity.userId != ownerID) return@filter false
                if (activity.status.lowercase() != "completed") return@filter false
                if (activity.photoUrls.isEmpty()) return@filter false
                val date = activity.scheduledInstant ?: return@filter false
                val duration = (activity.durationMinutes ?: activity.sport.defaultDurationMinutes) * 60L
                referenceDate.epochSecond - date.epochSecond >= duration
            }.map(ProfileGameFeedItem::Visit)

            return (gameItems + visitItems)
                .sortedWith(compareByDescending<ProfileGameFeedItem> { it.date }.thenBy { it.id })
                .take(6)
        }
    }
}

/**
 * Port of `DiscoverUser.init(profile:)` - the profile rendered as the card
 * other players see in Discover.
 */
fun discoverUserFromProfile(profile: UserProfile): DiscoverUser = DiscoverUser(
    id = profile.id,
    showOnMap = profile.showOnMap,
    mapAreasRaw = emptyList(),
    name = profile.name,
    age = profile.age,
    city = profile.city,
    district = profile.district,
    districtLabel = localizedDistrictName(profile.district),
    preferredDistricts = profile.preferredDistricts,
    bio = profile.bio,
    avatarUrl = profile.avatarUrl,
    profilePhotoUrls = profile.profilePhotoUrls,
    profileVideoUrls = profile.profileVideoUrls,
    profileMediaOrder = profile.profileMediaOrder,
    lastActiveAt = null,
    tennisLevel = profile.tennisLevel,
    preferredSports = profile.preferredSports,
    sportLevels = profile.sportLevels,
    preferredPlayFormatRaw = profile.preferredPlayFormat.wire,
    preferredSurfaceRaw = profile.preferredSurface.wire,
    availableDays = profile.availableDays,
    availableTimeRanges = profile.availableTimeRanges,
    distanceLabelRaw = localizedDistrictName(profile.district)
        ?: profile.city
        ?: L10n.string("Location not specified", "Локация не указана"),
    score = null,
    explainabilityReasons = emptyList(),
    gameSearches = emptyList(),
)
