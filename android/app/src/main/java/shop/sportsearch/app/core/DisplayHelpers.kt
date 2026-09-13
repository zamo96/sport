package shop.sportsearch.app.core

/**
 * Display extensions ported from the `extension DiscoverUser` / `UserProfile` /
 * `GameSearch` blocks in ios/TennisSearchIOS/Core/AppModels.swift.
 */

private fun uniqueNonEmptyMediaPaths(paths: List<String>): List<String> =
    paths.map(String::trim).filter(String::isNotEmpty).distinct()

val DiscoverUser.displayName: String
    get() = name?.takeIf { it.isNotEmpty() } ?: L10n.string("Player", "Игрок")

val DiscoverUser.districtDisplayNames: List<String>
    get() {
        val base = if (preferredDistricts.isEmpty()) {
            listOfNotNull(districtLabel ?: district)
        } else {
            preferredDistricts
        }
        return base.mapNotNull(::localizedDistrictName).distinct()
    }

val DiscoverUser.districtDisplaySummary: String
    get() = districtDisplayNames.takeIf { it.isNotEmpty() }?.take(3)?.joinToString(", ")
        ?: L10n.string("Areas not specified", "Районы не указаны")

val DiscoverUser.sportChips: List<String>
    get() = preferredSports.take(2).map { sport ->
        val level = sportLevels[sport.wire] ?: tennisLevel ?: 5
        "${sport.title} $level"
    }

val DiscoverUser.profilePhotoPaths: List<String>
    get() = uniqueNonEmptyMediaPaths(profilePhotoUrls + listOfNotNull(avatarUrl))

val DiscoverUser.profileHeroImagePath: String?
    get() = profilePhotoPaths.firstOrNull()

val DiscoverUser.playerCardMediaItems: List<PlayerMediaItem>
    get() = profilePhotoPaths.map { PlayerMediaItem(PlayerMediaKind.PHOTO, it) } +
        uniqueNonEmptyMediaPaths(profileVideoUrls).map { PlayerMediaItem(PlayerMediaKind.VIDEO, it) }

val UserProfile.displayName: String
    get() = name?.takeIf { it.isNotEmpty() } ?: email ?: L10n.string("Profile", "Профиль")

val UserProfile.profilePhotoPaths: List<String>
    get() = uniqueNonEmptyMediaPaths(profilePhotoUrls + listOfNotNull(avatarUrl))

/** The same media list the swipe card builds, for the profile's own preview. */
val UserProfile.playerCardMediaItems: List<PlayerMediaItem>
    get() = profilePhotoPaths.map { PlayerMediaItem(PlayerMediaKind.PHOTO, it) } +
        uniqueNonEmptyMediaPaths(profileVideoUrls).map { PlayerMediaItem(PlayerMediaKind.VIDEO, it) }

val UserProfile.profileHeroImagePath: String?
    get() = profilePhotoPaths.firstOrNull()

val GuestOnboardingDraft.displayName: String
    get() = name.trim().ifEmpty { L10n.string("Your profile", "Твой профиль") }

val GameSearch.scheduleLine: String
    get() {
        if (searchType == SearchType.HOT) {
            val day = hotWindow?.title
            val time = hotStartsAt?.formattedDateTime()
            return listOfNotNull(day, time).joinToString(", ")
        }

        val days = preferredDays.take(2).map { DayOfWeek.from(it)?.shortTitle ?: it.replaceFirstChar(Char::uppercase) }
        val times = preferredTimeRanges.take(2).map(::localizedTimePreferenceTitle)
        return (days + times).joinToString(" • ")
    }

val GameSearch.statusLabel: String
    get() = when (status.lowercase()) {
        "active" -> L10n.string("Recruiting", "Идет набор")
        "in_review" -> L10n.string("Awaiting decision", "Ожидает решения")
        "matched" -> L10n.string("Players found", "Игроки найдены")
        "closed" -> L10n.string("Closed", "Закрыт")
        else -> status
    }

// MatchGameRequest display helpers live in MatchDisplay.kt.

val Court.subtitleLine: String
    get() = listOfNotNull(
        metroDisplayName,
        distanceLabel,
        localizedDistrictName(district),
    ).joinToString(" · ")

/** Port of `isOwnedActiveHotSearchForAttention(_:currentUserId:)`. */
fun isOwnedActiveHotSearchForAttention(search: GameSearch, currentUserId: String?): Boolean {
    if (currentUserId == null) return false
    if (search.createdByUserId != currentUserId) return false
    if (search.searchType != SearchType.HOT) return false
    if (search.isActive == false) return false
    return search.status.lowercase() in setOf("active", "in_review")
}

/** Port of `SearchResponse.applying(responseUpdate:)`. */
fun SearchResponse.applying(result: SearchResponseUpdateResult): SearchResponse {
    if (id != result.response.id) return this
    return result.response.copy(matchId = result.response.matchId ?: result.matchId ?: matchId)
}

/** Port of `GameSearch.applying(responseUpdate:)`. */
fun GameSearch.applying(result: SearchResponseUpdateResult): GameSearch {
    val touchesThisSearch = responses.any { it.id == result.response.id } || result.gameSearch?.id == id
    if (!touchesThisSearch) return this

    val update = result.gameSearch?.takeIf { it.id == id }
    return copy(
        status = update?.status ?: status,
        isActive = update?.isActive ?: isActive,
        responses = responses.map { it.applying(result) },
    )
}

fun List<GameSearch>.applying(result: SearchResponseUpdateResult): List<GameSearch> = map { it.applying(result) }

/** Port of `SearchLobbyGameSearch.applying(responseUpdate:)`. */
fun SearchLobbyGameSearch.applying(result: SearchResponseUpdateResult): SearchLobbyGameSearch {
    val touchesThisSearch = responses.any { it.id == result.response.id } || result.gameSearch?.id == id
    if (!touchesThisSearch) return this

    val update = result.gameSearch?.takeIf { it.id == id }
    return copy(
        status = update?.status ?: status,
        isActive = update?.isActive ?: isActive,
        responses = responses.map { it.applying(result) },
    )
}
