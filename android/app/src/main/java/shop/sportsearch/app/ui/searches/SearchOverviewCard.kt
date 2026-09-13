package shop.sportsearch.app.ui.searches

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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.maps.RunningRoutePreviewMapView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct SearchOverviewCard` in ios/TennisSearchIOS/Views/SearchesView.swift. */
@Composable
fun SearchOverviewCard(
    search: GameSearch,
    currentUserId: String?,
    updatingSearchID: String?,
    onOpenDetails: () -> Unit,
    onEdit: () -> Unit,
    onToggleActive: (Boolean) -> Unit,
    onOpenRoute: () -> Unit = {},
) {
    val isOwned = search.createdByUserId == null || currentUserId == null ||
        search.createdByUserId == currentUserId
    val myResponse = currentUserId?.let { id -> search.responses.firstOrNull { it.responderUser.id == id } }

    val scopedResponses = if (isOwned) search.responses else listOfNotNull(myResponse)
    val pendingResponses = scopedResponses.filter { it.status == "pending" }
    val approvedResponses = scopedResponses.filter { it.status == "approved" }
    val rejectedResponses = scopedResponses.filter { it.status == "rejected" }
    val withdrawnResponses = scopedResponses.filter { it.status == "withdrawn" }
    val visibleResponses =
        (approvedResponses + pendingResponses + rejectedResponses + withdrawnResponses).take(4)

    val isCompleted = search.status.lowercase() in setOf("matched", "completed", "finished") ||
        search.responses.count { it.status == "approved" } >= maxOf(search.playersNeeded, 1)
    val isActive = search.isActive ?: true
    val canManage = isOwned && !isCompleted
    val canOpenDetails = isOwned || myResponse?.status == "approved"
    val remainingSeats = maxOf(search.playersNeeded - approvedResponses.size, 0)

    val myResponseStatusTitle = when (myResponse?.status) {
        "approved" -> L10n.string("Approved", "Одобрено")
        "rejected" -> L10n.string("Rejected", "Отклонено")
        "withdrawn" -> L10n.string("Withdrawn", "Отозвано")
        else -> L10n.string("Pending", "На рассмотрении")
    }

    val headlineText = when {
        !isOwned -> {
            val min = search.desiredLevelMin
            val max = search.desiredLevelMax
            if (min != null && max != null) {
                L10n.string(
                    "You responded to a level $min–$max search",
                    "Вы откликнулись на поиск уровня $min–$max",
                )
            } else {
                L10n.string("You responded to this search", "Вы откликнулись на этот поиск")
            }
        }
        isCompleted -> L10n.string("Game is full", "Игра собрана")
        else -> {
            val min = search.desiredLevelMin
            val max = search.desiredLevelMax
            val noun = playerNoun(search.playersNeeded)
            if (min != null && max != null) {
                L10n.string(
                    "Looking for ${search.playersNeeded} player(s), level $min–$max",
                    "Ищу $noun уровня $min–$max",
                )
            } else {
                L10n.string("Looking for ${search.playersNeeded} player(s)", "Ищу $noun")
            }
        }
    }

    val cardStatusTitle = when {
        !isOwned -> myResponseStatusTitle
        isCompleted -> L10n.string("Full", "Собрано")
        !isActive -> L10n.string("Paused", "Остановлен")
        pendingResponses.isNotEmpty() -> L10n.string("Has responses", "Есть отклики")
        else -> L10n.string("Active", "Активен")
    }

    val cardStatusTint = when {
        !isOwned -> when (myResponse?.status) {
            "approved" -> AppTheme.mint
            "rejected", "withdrawn" -> Color.Gray.copy(alpha = 0.16f)
            else -> AppTheme.cream
        }
        isCompleted -> Color.Blue.copy(alpha = 0.16f)
        !isActive -> Color.Gray.copy(alpha = 0.16f)
        else -> AppTheme.mint
    }

    val cardStatusForeground = when {
        !isOwned -> when (myResponse?.status) {
            "approved" -> AppTheme.court
            "rejected", "withdrawn" -> AppTheme.ink.copy(alpha = 0.72f)
            else -> Color(red = 0.70f, green = 0.46f, blue = 0.04f)
        }
        isCompleted -> Color.Blue.copy(alpha = 0.9f)
        !isActive -> AppTheme.ink.copy(alpha = 0.72f)
        else -> AppTheme.court
    }

    val cardAccentColor = when {
        !isOwned -> AppTheme.ink.copy(alpha = 0.42f)
        isCompleted -> Color.Blue.copy(alpha = 0.78f)
        !isActive -> AppTheme.ink.copy(alpha = 0.42f)
        pendingResponses.isNotEmpty() -> AppTheme.court
        search.sport == Sport.PADEL -> Color(red = 0.80f, green = 0.60f, blue = 0.16f)
        else -> AppTheme.court.copy(alpha = 0.78f)
    }

    val cardSurfaceColor = when {
        !isOwned -> Color.Black.copy(alpha = 0.04f)
        isCompleted -> Color.Blue.copy(alpha = 0.10f)
        !isActive -> Color.Gray.copy(alpha = 0.14f)
        pendingResponses.isNotEmpty() -> Color(red = 1.0f, green = 0.96f, blue = 0.86f).copy(alpha = 0.82f)
        else -> AppTheme.mint.copy(alpha = 0.42f)
    }

    val responseSummaryTitle = when {
        !isOwned -> myResponseStatusTitle
        isCompleted -> {
            val count = maxOf(maxOf(search.playersNeeded, approvedResponses.size), approvedResponses.size)
            "$count ${peopleWord(count)}"
        }
        remainingSeats == 0 -> L10n.string("Roster complete", "Состав собран")
        else -> L10n.string("$remainingSeats left", "Осталось $remainingSeats")
    }

    val responseSummarySubtitle = when {
        !isOwned -> L10n.string("Your response", "Ваш отклик")
        isCompleted -> L10n.string("Everyone confirmed", "Все подтвердили")
        pendingResponses.isEmpty() -> "${search.responses.size} ${responseWord(search.responses.size)}"
        else -> L10n.string("${pendingResponses.size} new", "${pendingResponses.size} новых")
    }

    val primaryActionTitle = when {
        !isOwned -> if (myResponse?.status == "approved") L10n.string("Lobby", "Лобби") else myResponseStatusTitle
        search.responses.isNotEmpty() -> L10n.string("Responses", "Отклики")
        isCompleted -> L10n.string("Open", "Открыть")
        else -> L10n.string("Details", "Детали")
    }

    val primaryActionTint = when {
        !isOwned -> AppTheme.ink
        isCompleted -> Color.Blue.copy(alpha = 0.85f)
        else -> AppTheme.court
    }

    val sportTint = when (search.sport) {
        Sport.PADEL -> Color(red = 0.82f, green = 0.60f, blue = 0.05f)
        Sport.BADMINTON -> Color.Blue.copy(alpha = 0.82f)
        else -> AppTheme.court
    }

    val areaText = search.preferredDistricts.firstOrNull()?.let { localizedDistrictName(it) ?: it }
        ?: L10n.string("Any district", "Любой район")
    val courtText = search.preferredCourt?.name
        ?: search.customVenueAddress
        ?: search.customVenueTitle
        ?: if (search.sport.isRouteSport) {
            L10n.string("Route to be confirmed", "Маршрут уточняется")
        } else {
            L10n.string("No club", "Без клуба")
        }

    val shape = continuousShape(26.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .appShadow(AppTheme.ink.copy(alpha = 0.04f), radius = 14.dp, offsetY = 8.dp, shape = shape)
            .clip(shape)
            .background(cardSurfaceColor)
            .border(1.2.dp, cardAccentColor.copy(alpha = 0.28f), shape)
            .clickable(enabled = canOpenDetails, onClick = onOpenDetails)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(42.dp).clip(CircleShape).background(sportTint.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                SportIconView(sport = search.sport, color = sportTint, size = 20.dp)
            }

            Text(
                "${search.sport.title} · ${search.sport.formatTitle(search.format, search.playersNeeded)}",
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.88f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )

            AppInlineChip(text = cardStatusTitle, tint = cardStatusTint, foreground = cardStatusForeground)

            Box(
                modifier = Modifier.size(30.dp).clickable(enabled = canOpenDetails, onClick = onOpenDetails),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.MoreHoriz,
                    null,
                    tint = AppTheme.ink.copy(alpha = 0.74f),
                    modifier = Modifier.size(18.dp),
                )
            }
        }

        Text(
            headlineText,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (search.searchType == SearchType.HOT) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    HotMetaPill(Icons.Filled.LocalFireDepartment, L10n.string("Urgent", "Срочно"), isFlame = true)
                    HotMetaPill(
                        Icons.Filled.Schedule,
                        search.hotStartsAt?.formattedDateTime()
                            ?: L10n.string("Time not specified", "Время не указано"),
                        isFlame = false,
                    )
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    CardMeta(
                        Icons.Filled.CalendarMonth,
                        search.preferredDays.mapNotNull { DayOfWeek.from(it)?.shortTitle }
                            .take(2).joinToString(", "),
                        Modifier.weight(1f),
                    )
                    CardMeta(
                        Icons.Filled.Schedule,
                        search.preferredTimeRanges.map(::localizedTimePreferenceTitle).take(1).joinToString(", "),
                        Modifier.weight(1f),
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CardMeta(Icons.Filled.LocationOn, areaText, Modifier.weight(1f))
                CardMeta(Icons.Filled.Apartment, courtText, Modifier.weight(1f))
            }
        }

        if (search.sport.isRouteSport && search.runningRoutePoints.size >= 2) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(132.dp)
                    .clip(continuousShape(20.dp))
                    .border(1.dp, cardAccentColor.copy(alpha = 0.24f), continuousShape(20.dp))
                    .clickable { onOpenRoute() },
            ) {
                RunningRoutePreviewMapView(
                    points = search.runningRoutePoints,
                    followsRoads = search.sport.routeFollowsRoads,
                    modifier = Modifier.fillMaxSize(),
                )
                Text(
                    L10n.string("Open route", "Открыть маршрут"),
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

        Box(Modifier.fillMaxWidth().height(1.dp).background(AppTheme.ink.copy(alpha = 0.08f)))

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(horizontalArrangement = Arrangement.spacedBy((-10).dp)) {
                visibleResponses.forEach { response ->
                    RemoteAvatarView(
                        name = response.responderUser.displayName,
                        path = response.responderUser.avatarUrl,
                        size = 38.dp,
                        modifier = Modifier.border(2.dp, Color.White, CircleShape),
                    )
                }
                val overflow = maxOf(search.responses.size - visibleResponses.size, 0)
                if (overflow > 0) {
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.05f))
                            .border(2.dp, Color.White, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "+$overflow",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppTheme.ink.copy(alpha = 0.76f),
                        )
                    }
                }
            }

            Spacer(Modifier.weight(1f))

            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    responseSummaryTitle,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppTheme.ink,
                )
                Text(
                    responseSummarySubtitle,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (pendingResponses.isEmpty()) {
                        AppTheme.ink.copy(alpha = 0.48f)
                    } else {
                        Color.Red.copy(alpha = 0.9f)
                    },
                )
            }

            Icon(
                Icons.Filled.ChevronRight,
                null,
                tint = AppTheme.ink.copy(alpha = 0.3f),
                modifier = Modifier.size(12.dp),
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CardActionButton(
                title = primaryActionTitle,
                icon = if (primaryActionTitle == L10n.string("Responses", "Отклики")) {
                    Icons.Filled.HowToReg
                } else {
                    Icons.AutoMirrored.Filled.ArrowForward
                },
                background = primaryActionTint,
                foreground = Color.White,
                bordered = false,
                enabled = canOpenDetails,
                modifier = Modifier.weight(1f),
                onClick = onOpenDetails,
            )

            if (canManage) {
                CardActionButton(
                    title = L10n.string("Edit", "Изм."),
                    icon = Icons.Filled.Edit,
                    background = Color.White,
                    foreground = AppTheme.ink,
                    bordered = true,
                    enabled = updatingSearchID != search.id,
                    modifier = Modifier.weight(1f),
                    onClick = onEdit,
                )

                if (updatingSearchID == search.id) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(38.dp)
                            .clip(continuousShape(14.dp))
                            .background(Color.White)
                            .border(1.dp, Color.Black.copy(alpha = 0.08f), continuousShape(14.dp)),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            color = AppTheme.court,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                } else {
                    CardActionButton(
                        title = if (isActive) L10n.string("Pause", "Остановить") else L10n.string("Resume", "Возобновить"),
                        icon = if (isActive) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        background = Color.White,
                        foreground = AppTheme.ink,
                        bordered = true,
                        enabled = true,
                        modifier = Modifier.weight(1f),
                        onClick = { onToggleActive(!isActive) },
                    )
                }
            }
        }
    }
}

@Composable
private fun CardMeta(icon: ImageVector, text: String, modifier: Modifier = Modifier) {
    if (text.isEmpty()) {
        Spacer(modifier)
        return
    }
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = AppTheme.ink.copy(alpha = 0.72f), modifier = Modifier.size(11.dp))
        Text(
            text,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = AppTheme.ink.copy(alpha = 0.84f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun HotMetaPill(icon: ImageVector, text: String, isFlame: Boolean) {
    val foreground = if (isFlame) Color.Red.copy(alpha = 0.92f) else AppTheme.ink
    Row(
        modifier = Modifier
            .height(30.dp)
            .clip(CircleShape)
            .background(if (isFlame) Color.Red.copy(alpha = 0.10f) else Color.Black.copy(alpha = 0.04f))
            .padding(horizontal = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = foreground, modifier = Modifier.size(11.dp))
        Text(text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = foreground, maxLines = 1)
    }
}

@Composable
private fun CardActionButton(
    title: String,
    icon: ImageVector,
    background: Color,
    foreground: Color,
    bordered: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = continuousShape(14.dp)
    Row(
        modifier = modifier
            .height(38.dp)
            .clip(shape)
            .background(background)
            .then(if (bordered) Modifier.border(1.dp, Color.Black.copy(alpha = 0.08f), shape) else Modifier)
            .clickable(enabled = enabled, onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = foreground, modifier = Modifier.size(13.dp))
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = foreground, maxLines = 1)
    }
}

/** `playerNoun(count:)` - the Russian branch keeps the original wording verbatim. */
fun playerNoun(count: Int): String {
    if (LocaleStore.current == AppLocale.EN) return "$count ${if (count == 1) "player" else "players"}"
    return if (count == 1) "1 игрока" else "$count игроков"
}

fun responseWord(count: Int): String {
    if (LocaleStore.current == AppLocale.EN) return if (count == 1) "response" else "responses"
    return when (count) {
        1 -> "отклик"
        2, 3, 4 -> "отклика"
        else -> "откликов"
    }
}

fun peopleWord(count: Int): String {
    if (LocaleStore.current == AppLocale.EN) return if (count == 1) "player" else "players"
    return when (count) {
        1 -> "игрок"
        2, 3, 4 -> "игрока"
        else -> "игроков"
    }
}
