package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.maps.RunningRoutePreviewMapView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.time.LocalDate
import java.time.ZoneId

/** Port of `struct ActiveHotSearchCard` in ios/TennisSearchIOS/Views/DiscoverView.swift. */
@Composable
fun ActiveHotSearchCard(
    user: DiscoverUser,
    search: GameSearch,
    responseStatus: String?,
    responseId: String?,
    onOpenUser: () -> Unit,
    onOpenCourt: (Court) -> Unit,
    onOpenApprovedChat: () -> Unit,
    onAction: () -> Unit,
    onOpenRoute: () -> Unit = {},
) {
    val zone = ZoneId.systemDefault()
    val startDate = parseServerInstant(search.hotStartsAt)

    val dayText = when {
        startDate == null -> search.hotWindow?.title ?: L10n.string("Today", "Сегодня")
        startDate.atZone(zone).toLocalDate() == LocalDate.now(zone) -> L10n.string("Today", "Сегодня")
        startDate.atZone(zone).toLocalDate() == LocalDate.now(zone).plusDays(1) ->
            L10n.string("Tomorrow", "Завтра")
        else -> startDate.formattedDayMonth()
    }
    val timeText = startDate?.formattedHourMinute() ?: L10n.string("Time", "Время")

    val minLevel = search.desiredLevelMin ?: search.selfLevel ?: 1
    val maxLevel = search.desiredLevelMax ?: search.selfLevel ?: 10
    val levelText = if (minLevel == maxLevel) {
        L10n.string("Level $minLevel", "Уровень $minLevel")
    } else {
        L10n.string("Level $minLevel-$maxLevel", "Уровень $minLevel-$maxLevel")
    }

    val playersNeededText = when {
        search.playersNeeded == 1 -> L10n.string("1 player needed", "Нужен 1 игрок")
        LocaleStore.current == AppLocale.EN -> "${search.playersNeeded} players needed"
        else -> "Нужно ${search.playersNeeded} ${hotPlayerWord(search.playersNeeded)}"
    }

    val courtName = search.preferredCourt?.name
        ?: search.customVenueAddress
        ?: search.customVenueTitle
        ?: if (search.sport.isRouteSport) {
            L10n.string("Route to be confirmed", "Маршрут уточняется")
        } else {
            search.sport.venuePendingTitle
        }

    val courtDetails = run {
        val address = search.preferredCourt?.address?.trim()
            ?: search.customVenueAddress?.trim()
            ?: search.runningRoute?.trim()
        val distance = (search.preferredCourt?.distanceLabel ?: user.distanceLabel).trim()
        listOfNotNull(address, if (search.preferredCourt == null) null else distance)
            .filter { it.isNotEmpty() }
            .joinToString(" · ")
            .ifEmpty { L10n.string("Place to be confirmed", "Место уточняется") }
    }

    val districtText = user.districtLabel
        ?: localizedDistrictName(user.district)
        ?: user.city
        ?: L10n.string("Area not provided", "Район не указан")

    val canOpenApprovedChat = responseStatus == "approved" &&
        (search.playersNeeded > 1 || search.regularPair?.id != null)

    val actionTitle = when (responseStatus) {
        "pending" -> L10n.string("Cancel", "Отменить")
        "approved" -> if (canOpenApprovedChat) {
            L10n.string("Open chat", "Открыть чат")
        } else {
            L10n.string("Response accepted", "Отклик принят")
        }
        "rejected" -> L10n.string("Response declined", "Отклик отклонён")
        else -> L10n.string("Respond", "Откликнуться")
    }
    val actionTint = when (responseStatus) {
        "pending" -> Color.White.copy(alpha = 0.14f)
        "approved" -> if (canOpenApprovedChat) AppTheme.court else Color.White.copy(alpha = 0.14f)
        "rejected" -> Color.Red.copy(alpha = 0.48f)
        else -> AppTheme.court
    }
    val isActionDisabled = responseStatus == "rejected" ||
        (responseStatus == "pending" && responseId == null) ||
        (responseStatus == "approved" && !canOpenApprovedChat)

    val shape = continuousShape(28.dp)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .appShadow(Color.Black.copy(alpha = 0.22f), radius = 22.dp, offsetY = 14.dp, shape = shape)
            .clip(shape)
            .border(1.dp, Color.White.copy(alpha = 0.10f), shape),
    ) {
        // cardBackground: a diagonal base plus a court-green radial glow top-right.
        Box(
            modifier = Modifier.matchParentSize().background(
                Brush.linearGradient(
                    listOf(
                        Color(red = 0.04f, green = 0.09f, blue = 0.09f),
                        Color(red = 0.02f, green = 0.04f, blue = 0.04f),
                    ),
                ),
            ),
        )
        Box(
            modifier = Modifier.matchParentSize().background(
                Brush.radialGradient(
                    colors = listOf(AppTheme.court.copy(alpha = 0.22f), Color.Transparent),
                    center = Offset(Float.POSITIVE_INFINITY, 0f),
                    radius = 700f,
                ),
            ),
        )

        Column(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // header
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                Box(modifier = Modifier.clickable(onClick = onOpenUser)) {
                    RemoteAvatarView(
                        name = user.displayName,
                        path = user.avatarUrl,
                        size = 64.dp,
                        modifier = Modifier.border(1.dp, Color.White.copy(alpha = 0.12f), continuousShape(22.dp)),
                    )
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .offset(x = 3.dp, y = 3.dp)
                            .size(16.dp)
                            .clip(CircleShape)
                            .background(if (user.isOnline) Color(0xFF4CAF50) else Color.White.copy(alpha = 0.52f))
                            .border(3.dp, Color(red = 0.03f, green = 0.07f, blue = 0.07f), CircleShape),
                    )
                }

                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        user.age?.let { "${user.displayName}, $it" } ?: user.displayName,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )

                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .height(24.dp)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.10f))
                                .padding(horizontal = 8.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                user.presenceLabel,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                                maxLines = 1,
                            )
                        }
                        Text(
                            districtText,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.64f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }

            // searchSummary
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(24.dp))
                    .background(Color.White.copy(alpha = 0.045f))
                    .border(1.dp, Color.White.copy(alpha = 0.08f), continuousShape(24.dp))
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                    Box(
                        modifier = Modifier
                            .size(58.dp)
                            .clip(continuousShape(16.dp))
                            .background(Color.Black.copy(alpha = 0.24f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        SportIconView(sport = search.sport, color = AppTheme.court, size = 34.dp)
                    }

                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(
                            "${search.sport.title} · ${search.sport.formatTitle(search.format, search.playersNeeded)}",
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Black,
                            color = Color.White,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            levelText,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.66f),
                            maxLines = 1,
                        )
                    }
                }

                Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ActiveHotSearchDetailTile(
                        Icons.Filled.CalendarMonth,
                        L10n.string("Date", "Дата"),
                        dayText,
                        Modifier.weight(1f),
                    )
                    ActiveHotSearchDetailTile(
                        Icons.Filled.Schedule,
                        L10n.string("Time", "Время"),
                        timeText,
                        Modifier.weight(1f),
                    )
                    ActiveHotSearchDetailTile(
                        Icons.Filled.People,
                        L10n.string("Looking for", "Ищем"),
                        playersNeededText,
                        Modifier.weight(1f),
                    )
                }

                val court = search.preferredCourt
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(continuousShape(18.dp))
                        .background(Color.Black.copy(alpha = 0.18f))
                        .border(
                            1.dp,
                            Color.White.copy(alpha = if (court != null) 0.12f else 0.06f),
                            continuousShape(18.dp),
                        )
                        .then(if (court != null) Modifier.clickable { onOpenCourt(court) } else Modifier)
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Box(modifier = Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                        Icon(Icons.Outlined.Place, null, tint = AppTheme.court, modifier = Modifier.size(17.dp))
                    }

                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            courtName,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            courtDetails,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.62f),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }

                    if (court != null) {
                        Icon(
                            Icons.Filled.ChevronRight,
                            null,
                            tint = Color.White.copy(alpha = 0.46f),
                            modifier = Modifier.padding(top = 4.dp).size(13.dp),
                        )
                    }
                }

                if (search.sport.isRouteSport && search.runningRoutePoints.size >= 2) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(138.dp)
                            .clip(continuousShape(18.dp))
                            .border(1.dp, Color.White.copy(alpha = 0.10f), continuousShape(18.dp))
                            .clickable { onOpenRoute() },
                    ) {
                        RunningRoutePreviewMapView(
                            points = search.runningRoutePoints,
                            followsRoads = search.sport.routeFollowsRoads,
                            modifier = Modifier.fillMaxSize(),
                        )
                        Text(
                            L10n.string("Open directions", "Открыть маршрут"),
                            style = AppText.captionBold,
                            color = Color.White,
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(10.dp)
                                .clip(CircleShape)
                                .background(Color.Black.copy(alpha = 0.48f))
                                .padding(horizontal = 10.dp, vertical = 7.dp),
                        )
                    }
                }
            }

            // footer
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(46.dp)
                    .clip(CircleShape)
                    .background(actionTint)
                    .border(
                        1.dp,
                        Color.White.copy(alpha = if (responseStatus == "pending") 0.12f else 0f),
                        CircleShape,
                    )
                    .clickable(enabled = !isActionDisabled) {
                        if (canOpenApprovedChat) onOpenApprovedChat() else onAction()
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    actionTitle,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = if (isActionDisabled) 0.72f else 1f),
                    maxLines = 1,
                )
            }
        }
    }
}

/** Port of `struct ActiveHotSearchDetailTile`. */
@Composable
private fun ActiveHotSearchDetailTile(
    icon: ImageVector,
    title: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .heightIn(min = 96.dp)
            .clip(continuousShape(18.dp))
            .background(Color.Black.copy(alpha = 0.18f))
            .border(1.dp, Color.White.copy(alpha = 0.07f), continuousShape(18.dp))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier.size(24.dp).clip(CircleShape).background(AppTheme.court.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = AppTheme.court, modifier = Modifier.size(13.dp))
        }

        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                title,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.58f),
                maxLines = 1,
            )
            Text(
                value,
                fontSize = 15.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Port of `struct ActiveHotSearchSportChip`. */
@Composable
fun ActiveHotSearchSportChip(title: String, sport: Sport?, isSelected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .height(40.dp)
            .clip(CircleShape)
            .background(if (isSelected) Color(red = 0.63f, green = 0.93f, blue = 0.75f) else Color.White.copy(alpha = 0.07f))
            .border(
                1.dp,
                if (isSelected) Color.Transparent else Color.White.copy(alpha = 0.1f),
                CircleShape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        sport?.let {
            SportIconView(sport = it, color = if (isSelected) Color.Black else Color.White, size = 15.dp)
        }
        Text(
            title,
            style = AppText.subheadlineSemibold,
            color = if (isSelected) Color.Black else Color.White,
            maxLines = 1,
        )
    }
}

/** Port of `struct UrgentSearchEmptyState`. */
@Composable
fun UrgentSearchEmptyState(showsCreateButton: Boolean, onCreateSearch: () -> Unit) {
    val shape = continuousShape(28.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.78f))
            .border(1.dp, AppTheme.line, shape)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier.size(66.dp).clip(CircleShape).background(AppTheme.court.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.Search,
                null,
                tint = AppTheme.court,
                modifier = Modifier.size(32.dp),
            )
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                L10n.string("No active searches yet", "Активных поисков пока нет"),
                style = AppText.title3Bold,
                color = AppTheme.ink,
            )
            Text(
                L10n.string(
                    "Create a search to quickly find players for the near future.",
                    "Создай поиск, чтобы быстро собрать игроков на ближайшее время.",
                ),
                style = AppText.subheadline,
                color = AppTheme.ink.copy(alpha = 0.62f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }

        if (showsCreateButton) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .clip(continuousShape(18.dp))
                    .background(AppTheme.court)
                    .clickable(onClick = onCreateSearch),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Filled.Add,
                    null,
                    tint = Color.White,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    L10n.string("Create search", "Создать поиск"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }
    }
}

private fun hotPlayerWord(count: Int): String {
    val r10 = count % 10
    val r100 = count % 100
    if (r10 == 1 && r100 != 11) return "игрок"
    if (r10 in 2..4 && r100 !in 12..14) return "игрока"
    return "игроков"
}
