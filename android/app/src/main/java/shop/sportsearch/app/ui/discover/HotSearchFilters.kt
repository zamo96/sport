package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale as JavaLocale
import shop.sportsearch.app.core.*
import shop.sportsearch.app.core.DiscoverUser
import shop.sportsearch.app.core.GameSearch
import shop.sportsearch.app.core.LatLng
import shop.sportsearch.app.core.districtAreasById
import shop.sportsearch.app.core.formattedDateTime
import shop.sportsearch.app.core.isRouteSport
import shop.sportsearch.app.core.localizedDistrictName
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `private enum ActiveHotSearchFilter` in DiscoverView.swift. */
enum class ActiveHotSearchFilter {
    ALL, TODAY, TOMORROW, CALENDAR, NEARBY, LEVEL;

    val title: String
        get() = when (this) {
            ALL -> L10n.string("All", "Все")
            TODAY -> L10n.string("Today", "Сегодня")
            TOMORROW -> L10n.string("Tomorrow", "Завтра")
            CALENDAR -> L10n.string("Calendar", "Календарь")
            NEARBY -> L10n.string("Nearby", "Рядом")
            LEVEL -> L10n.string("My level", "Мой уровень")
        }
}

private val zone: ZoneId get() = ZoneId.systemDefault()

/** `isVisibleActiveHotSearch(_:)`. */
fun isVisibleActiveHotSearch(search: GameSearch): Boolean {
    if (search.searchType != SearchType.HOT) return false
    if (search.isActive == false) return false
    if (search.isExpired == true) return false
    return search.status.lowercase() !in setOf("matched", "closed", "canceled", "cancelled", "expired")
}

/**
 * `isListedHotSearch(_:postedBy:)`: one rule for the searches list and the tab count,
 * so the badge can never promise a search the list does not show.
 */
fun isListedHotSearch(
    search: GameSearch,
    user: DiscoverUser,
    currentUserId: String?,
    localResponseStatuses: Map<String, String>,
): Boolean {
    if (user.id == currentUserId) return false
    if (!isVisibleActiveHotSearch(search)) return false
    val ownResponse = currentUserId?.let { id -> search.responses.firstOrNull { it.responderUser.id == id } }
    val status = localResponseStatuses[search.id] ?: ownResponse?.status
    return status != "rejected"
}

/** `listedHotSearchCount(in:)`. */
fun listedHotSearchCount(
    feed: List<DiscoverUser>,
    currentUserId: String?,
    localResponseStatuses: Map<String, String>,
): Int = feed.sumOf { user ->
    user.gameSearches.count { isListedHotSearch(it, user, currentUserId, localResponseStatuses) }
}

/** `isTodayHotSearch(_:)`. */
fun isTodayHotSearch(search: GameSearch): Boolean {
    parseServerInstant(search.hotStartsAt)?.let {
        return it.atZone(zone).toLocalDate() == LocalDate.now(zone)
    }
    return search.hotWindow == HotWindow.TODAY
}

/** `isTomorrowHotSearch(_:)`. */
fun isTomorrowHotSearch(search: GameSearch): Boolean {
    parseServerInstant(search.hotStartsAt)?.let {
        return it.atZone(zone).toLocalDate() == LocalDate.now(zone).plusDays(1)
    }
    return search.hotWindow == HotWindow.TOMORROW
}

/** `isHotSearch(_:on:)`. */
fun isHotSearch(search: GameSearch, on: LocalDate): Boolean {
    parseServerInstant(search.hotStartsAt)?.let {
        return it.atZone(zone).toLocalDate() == on
    }
    val today = LocalDate.now(zone)
    return when (search.hotWindow) {
        HotWindow.TODAY -> today == on
        HotWindow.TOMORROW -> today.plusDays(1) == on
        HotWindow.DAY_AFTER_TOMORROW -> today.plusDays(2) == on
        null -> false
    }
}

/** `isNearbyHotSearch(_:)` - shared districts, or any distance label at all. */
fun isNearbyHotSearch(currentUser: UserProfile?, user: DiscoverUser): Boolean {
    val mine = currentUser?.preferredDistricts.orEmpty().map { it.lowercase() }.toSet()
    val theirs = (user.preferredDistricts + listOfNotNull(user.district)).map { it.lowercase() }.toSet()
    if (mine.isNotEmpty() && theirs.isNotEmpty() && mine.intersect(theirs).isNotEmpty()) return true

    val distance = user.distanceLabel.lowercase()
    return distance.contains("км") || distance.contains("м") || distance.contains("рядом")
}

/** `matchesCurrentUserLevel(_:)`. */
fun matchesCurrentUserLevel(currentUser: UserProfile?, search: GameSearch): Boolean {
    val user = currentUser ?: return false
    val level = user.sportLevels[search.sport.wire] ?: user.tennisLevel ?: return false
    if (search.desiredLevelMin == null && search.desiredLevelMax == null) return true
    return level >= (search.desiredLevelMin ?: 1) && level <= (search.desiredLevelMax ?: 10)
}

/**
 * Port of `activeHotSearchDateRail` - "All" plus the next ten days, each with a
 * badge counting the searches on that day.
 */
@Composable
fun ActiveHotSearchDateRail(
    filter: ActiveHotSearchFilter,
    calendarDate: LocalDate,
    totalCount: Int,
    countOn: (LocalDate) -> Int,
    onSelectAll: () -> Unit,
    onSelectDate: (LocalDate) -> Unit,
) {
    val today = LocalDate.now(zone)
    val locale = JavaLocale.forLanguageTag(LocaleStore.current.code)

    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(horizontal = 2.dp)) {
        RailChip(
            isSelected = filter == ActiveHotSearchFilter.ALL,
            count = totalCount,
            onClick = onSelectAll,
        ) { selected ->
            Text(
                L10n.string("All", "Все"),
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = if (selected) Color.White else Color.White.copy(alpha = 0.78f),
            )
            Text(
                L10n.string("searches", "поиски"),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = (if (selected) Color.White else Color.White.copy(alpha = 0.78f)).copy(alpha = 0.78f),
            )
        }

        (0..9).forEach { offset ->
            val date = today.plusDays(offset.toLong())
            val isSelected = filter == ActiveHotSearchFilter.CALENDAR && calendarDate == date
            val dayTitle = if (date == today) {
                L10n.string("Today", "Сегодня")
            } else {
                date.dayOfWeek.getDisplayName(TextStyle.SHORT, locale)
                    .replaceFirstChar { it.uppercase() }
            }

            RailChip(
                isSelected = isSelected,
                count = countOn(date),
                onClick = { onSelectDate(date) },
            ) { selected ->
                Text(
                    "${date.dayOfMonth}",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Black,
                    color = if (selected) Color.White else Color.White.copy(alpha = 0.78f),
                )
                Text(
                    dayTitle,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (selected) Color.White else Color.White.copy(alpha = 0.78f),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun RailChip(
    isSelected: Boolean,
    count: Int,
    onClick: () -> Unit,
    content: @Composable (Boolean) -> Unit,
) {
    val shape = continuousShape(18.dp)
    Box {
        Column(
            modifier = Modifier
                .height(58.dp)
                .clip(shape)
                .background(if (isSelected) AppTheme.court.copy(alpha = 0.9f) else Color.White.copy(alpha = 0.07f))
                .border(1.dp, if (isSelected) AppTheme.court else Color.White.copy(alpha = 0.12f), shape)
                .clickable(onClick = onClick)
                .padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
        ) { content(isSelected) }

        if (count > 0) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(5.dp)
                    .defaultMinSize(minWidth = 20.dp, minHeight = 20.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) Color.White.copy(alpha = 0.94f) else AppTheme.court.copy(alpha = 0.95f))
                    .border(1.dp, Color.Black.copy(alpha = 0.18f), CircleShape)
                    .padding(horizontal = if (count > 9) 3.dp else 0.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "${minOf(count, 99)}",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Black,
                    color = if (isSelected) AppTheme.court else Color.White,
                )
            }
        }
    }
}

/** Port of the remaining `ActiveHotSearchFilterChip`s: Nearby and My level. */
@Composable
fun ActiveHotSearchFilterChip(title: String, count: Int?, isSelected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .height(40.dp)
            .clip(CircleShape)
            .background(if (isSelected) AppTheme.court else Color.White.copy(alpha = 0.07f))
            .border(1.dp, if (isSelected) AppTheme.court else Color.White.copy(alpha = 0.12f), CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isSelected) Color.White else Color.White.copy(alpha = 0.82f),
            maxLines = 1,
        )
        if (count != null && count > 0) {
            Text(
                "$count",
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) Color.White.copy(alpha = 0.86f) else AppTheme.court,
            )
        }
    }
}

/** Port of `private enum ActiveHotSearchDisplayMode`. */
enum class ActiveHotSearchDisplayMode {
    LIST, MAP;

    val title: String
        get() = when (this) {
            LIST -> L10n.string("List", "Список")
            MAP -> L10n.string("Map", "Карта")
        }
}

/** Port of `activeHotSearchDisplayControl`. */
@Composable
fun ActiveHotSearchDisplayControl(
    mode: ActiveHotSearchDisplayMode,
    onSelect: (ActiveHotSearchDisplayMode) -> Unit,
) {
    Row(
        modifier = Modifier
            .clip(continuousShape(16.dp))
            .background(Color.White.copy(alpha = 0.07f)),
    ) {
        ActiveHotSearchDisplayMode.entries.forEach { option ->
            val isSelected = mode == option
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .padding(4.dp)
                    .clip(continuousShape(13.dp))
                    .background(if (isSelected) Color(0xFFA1EDBF) else Color.Transparent)
                    .clickable { onSelect(option) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (option == ActiveHotSearchDisplayMode.LIST) {
                        Icons.AutoMirrored.Filled.List
                    } else {
                        Icons.Filled.Map
                    },
                    contentDescription = option.title,
                    tint = if (isSelected) Color.Black else Color.White.copy(alpha = 0.7f),
                    modifier = Modifier.size(17.dp),
                )
            }
        }
    }
}

/**
 * Port of `private struct ActiveHotSearchItem` - a user paired with one of their
 * searches, plus everything the map and its card read off it.
 */
data class ActiveHotSearchItem(
    val user: DiscoverUser,
    val search: GameSearch,
    val viewerMapCenter: LatLng,
) {
    val id: String get() = "${user.id}-${search.id}"

    val districtId: String?
        get() = search.preferredCourt?.district?.lowercase()?.takeIf { it.isNotEmpty() }
            ?: search.preferredDistricts.firstOrNull()?.lowercase()?.takeIf { it.isNotEmpty() }
            ?: user.district?.lowercase()?.takeIf { it.isNotEmpty() }

    val coordinate: LatLng
        get() {
            val points = search.runningRoutePoints
            if (points.size >= 2) {
                return LatLng(points.sumOf { it.lat } / points.size, points.sumOf { it.lng } / points.size)
            }
            search.preferredCourt?.let { return LatLng(it.locationLat, it.locationLng) }
            districtId?.let { districtAreasById[it] }?.let { return it.centerCoordinate }
            return viewerMapCenter
        }

    val venueTitle: String
        get() {
            search.preferredCourt?.let { return it.name }
            search.customVenueAddress?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            search.customVenueTitle?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            search.runningRoute?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            districtId?.let { localizedDistrictName(it) }?.let { return it }
            return if (search.sport.isRouteSport) {
                L10n.string("Route to be confirmed", "Маршрут уточняется")
            } else {
                L10n.string("Place to be confirmed", "Место уточняется")
            }
        }

    val timeTitle: String
        get() = search.hotStartsAt?.formattedDateTime()
            ?: L10n.string("Time to be confirmed", "Время уточняется")

    val playersTitle: String
        get() {
            val approved = search.responses.count { it.status == "approved" }
            val needed = maxOf(search.playersNeeded, 1)
            return L10n.string("$approved / $needed joined", "$approved / $needed собрано")
        }
}
