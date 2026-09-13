package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.CropPortrait
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import shop.sportsearch.app.core.*
import shop.sportsearch.app.core.DiscoverUser
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.LatLng
import shop.sportsearch.app.core.SimilarPlayersDistrictLayout
import shop.sportsearch.app.core.SimilarPlayersMapData
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.displayName
import shop.sportsearch.app.core.districtAreasById
import shop.sportsearch.app.core.profileHeroImagePath
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.maps.DiscoverPlayerMapItem
import shop.sportsearch.app.ui.maps.DiscoverPlayersMap
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape

private val mint = Color(red = 0.63f, green = 0.93f, blue = 0.75f)

/** Port of `private enum SimilarPlayersDisplayMode`. */
enum class SimilarPlayersDisplayMode {
    CARDS, GRID;

    val title: String
        get() = if (this == CARDS) L10n.string("Card", "Карточка") else L10n.string("Grid", "Сетка")
}

/** Port of `struct SwipeHintBar`. */
@Composable
fun SwipeHintBar(
    leftTitle: String = L10n.string("Left — skip", "Влево — пропустить"),
    rightTitle: String = L10n.string("Right — ready to play", "Вправо — можно сыграть"),
    isHighlighted: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val weight = if (isHighlighted) FontWeight.Bold else FontWeight.SemiBold
    Row(
        modifier = modifier.fillMaxWidth().padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val leftColor = if (isHighlighted) {
            Color(red = 1.0f, green = 0.34f, blue = 0.38f)
        } else {
            Color.White.copy(alpha = 0.38f)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = leftColor, modifier = Modifier.size(12.dp))
            Text(leftTitle, style = AppText.caption.copy(fontWeight = weight), color = leftColor, maxLines = 1)
        }

        Spacer(Modifier.weight(1f))

        val rightColor = if (isHighlighted) {
            Color(red = 0.55f, green = 0.92f, blue = 0.38f)
        } else {
            Color.White.copy(alpha = 0.38f)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(rightTitle, style = AppText.caption.copy(fontWeight = weight), color = rightColor, maxLines = 1)
            Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = rightColor, modifier = Modifier.size(12.dp))
        }
    }
}

/** Port of `struct SimilarPlayersModeControl`. */
@Composable
fun SimilarPlayersModeControl(
    mode: SimilarPlayersDisplayMode,
    isEnabled: Boolean,
    onSelect: (SimilarPlayersDisplayMode) -> Unit,
) {
    Row(
        modifier = Modifier
            .clip(continuousShape(16.dp))
            .background(Color.White.copy(alpha = 0.07f)),
    ) {
        SimilarPlayersDisplayMode.entries.forEach { option ->
            val isSelected = mode == option
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .padding(4.dp)
                    .clip(continuousShape(13.dp))
                    .background(if (isSelected) mint else Color.Transparent)
                    .clickable(enabled = isEnabled) { onSelect(option) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (option == SimilarPlayersDisplayMode.CARDS) {
                        Icons.Filled.CropPortrait
                    } else {
                        Icons.Filled.GridView
                    },
                    contentDescription = option.title,
                    tint = if (isSelected) Color.Black else Color.White.copy(alpha = 0.7f),
                    modifier = Modifier.size(17.dp),
                )
            }
        }
    }
}

/** Port of `struct SimilarPlayerGridTile`. */
@Composable
fun SimilarPlayerGridTile(
    user: DiscoverUser,
    selectedSport: Sport?,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val sports = selectedSport?.let { listOf(it) } ?: user.preferredSports.take(2)
    val sportSummary = if (sports.isEmpty()) {
        L10n.string("Sport not specified", "Спорт не указан")
    } else {
        val summary = sports.joinToString("\n") { sport ->
            val level = user.sportLevels[sport.wire] ?: if (sport == Sport.TENNIS) user.tennisLevel else null
            sport.title + (level?.let { " · $it/10" } ?: "")
        }
        val remaining = if (selectedSport == null) maxOf(0, user.preferredSports.size - sports.size) else 0
        summary + if (remaining > 0) " · +$remaining" else ""
    }

    val location = listOfNotNull(user.city, user.nearby?.distanceLabel ?: user.districtDisplayNames.firstOrNull())
        .filter { it.isNotEmpty() }
        .joinToString(" · ")
        .ifEmpty { L10n.string("Location not specified", "Место не указано") }

    val shape = continuousShape(22.dp)

    Column(
        modifier = modifier
            .clip(shape)
            .background(Color(0xFF141414))
            .border(
                if (isSelected) 2.dp else 1.dp,
                if (isSelected) mint else Color.White.copy(alpha = 0.09f),
                shape,
            )
            .clickable(onClick = onClick),
    ) {
        Box(modifier = Modifier.fillMaxWidth().aspectRatio(1.05f)) {
            SubcomposeAsyncImage(
                model = resolveAppRemoteUrl(user.profileHeroImagePath),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                error = { InitialFallback(user.displayName) },
                loading = { InitialFallback(user.displayName) },
            )
        }

        Column(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Text(user.displayName, style = AppText.headline, color = Color.White, maxLines = 2)
            Text(sportSummary, style = AppText.captionSemibold, color = mint, maxLines = 2)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Top) {
                Icon(
                    Icons.Filled.Place,
                    null,
                    tint = Color.White.copy(alpha = 0.6f),
                    modifier = Modifier.size(12.dp),
                )
                Text(location, style = AppText.caption, color = Color.White.copy(alpha = 0.6f), maxLines = 2)
            }
        }
    }
}

@Composable
private fun InitialFallback(name: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(listOf(AppTheme.court.copy(alpha = 0.75f), Color.Black)),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            name.take(1).uppercase(),
            style = AppText.largeTitleBlack,
            color = Color.White.copy(alpha = 0.9f),
        )
    }
}

/** Port of `struct SimilarPlayersFilteredEmptyState`. */
@Composable
fun SimilarPlayersFilteredEmptyState(onShowAllSports: () -> Unit) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            L10n.string("No players for this sport", "Нет игроков по этому виду спорта"),
            style = AppText.headlineBold,
            color = Color.White,
        )
        Text(
            L10n.string(
                "Try another sport or clear the filter.",
                "Попробуй другой вид спорта или сбрось фильтр.",
            ),
            style = AppText.subheadline,
            color = Color.White.copy(alpha = 0.58f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        PrimaryActionButton(
            title = L10n.string("Show all sports", "Все виды спорта"),
            tint = AppTheme.court,
            onClick = onShowAllSports,
        )
    }
}

/** Port of `private struct SimilarPlayersMapGrid`. */
@Composable
fun SimilarPlayersMapGrid(
    users: List<DiscoverUser>,
    layoutUsers: List<DiscoverUser>,
    availableSports: List<Sport>,
    selectedSport: Sport?,
    selectedPlayerId: String?,
    isEnabled: Boolean,
    onSelectSport: (Sport?) -> Unit,
    onSelectMapPlayer: (String) -> Unit,
    onShowCards: () -> Unit,
    onOpenPlayer: (DiscoverUser) -> Unit,
) {
    val mapItems = remember(users, layoutUsers, selectedSport) {
        val positions = SimilarPlayersDistrictLayout.positions(
            SimilarPlayersMapData.memberships(layoutUsers),
        ) { area ->
            val district = area.districtId?.let { districtAreasById[it] } ?: return@positions null
            SimilarPlayersDistrictLayout.validatedPolygon(
                area,
                district.city.wire,
                district.polygon.map { LatLng(it.first, it.second) },
            )
        }

        SimilarPlayersMapData.memberships(users, selectedSport).map { membership ->
            val user = membership.user
            val area = membership.area
            val levels = user.sportLevels.toMutableMap()
            if (levels[Sport.TENNIS.wire] == null) {
                user.tennisLevel?.let { levels[Sport.TENNIS.wire] = it }
            }
            val sports = selectedSport
                ?.let { chosen -> listOf(chosen) + user.preferredSports.filter { it != chosen } }
                ?: user.preferredSports

            DiscoverPlayerMapItem(
                id = membership.id,
                userID = user.id,
                areaID = area.mapID,
                anchorCoordinate = LatLng(area.latitude, area.longitude),
                coordinate = positions[membership.id] ?: LatLng(area.latitude, area.longitude),
                areaLabel = if (area.kind == "city") area.cityName else "${area.cityName} · ${area.label}",
                displayName = user.displayName,
                avatarPath = user.profileHeroImagePath,
                sports = sports,
                sportLevels = levels,
            )
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SimilarPlayersSportChip(null, selectedSport, isEnabled, onSelectSport)
            availableSports.forEach { sport ->
                SimilarPlayersSportChip(sport, selectedSport, isEnabled, onSelectSport)
            }
        }

        // `SimilarPlayersPlayerMap`
        val mapShape = continuousShape(22.dp)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(400.dp)
                .clip(mapShape)
                .border(1.dp, Color.White.copy(alpha = 0.09f), mapShape),
            contentAlignment = Alignment.Center,
        ) {
            if (mapItems.isEmpty()) {
                Column(
                    modifier = Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.06f)),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
                ) {
                    Icon(
                        Icons.Filled.Map,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.7f),
                        modifier = Modifier.size(24.dp),
                    )
                    Text(
                        L10n.string("No players to show on the map yet", "Пока нет игроков на карте"),
                        fontFamily = appFontFamily,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.7f),
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        L10n.string(
                            "Players choose whether to appear on the map.",
                            "Игроки сами выбирают, показываться ли на карте.",
                        ),
                        fontFamily = appFontFamily,
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.7f),
                        textAlign = TextAlign.Center,
                    )
                }
            } else {
                DiscoverPlayersMap(
                    items = mapItems,
                    selectedPlayerID = selectedPlayerId,
                    isEnabled = isEnabled,
                    modifier = Modifier.fillMaxSize(),
                    onSelect = onSelectMapPlayer,
                )
            }
        }

        Text(
            L10n.string("${users.size} players on the map", "Игроков на карте: ${users.size}"),
            fontFamily = appFontFamily,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
        )
        Text(
            L10n.string(
                "Cards are placed schematically in convenient areas for playing.",
                "Карточки размещены условно в удобных районах для игры.",
            ),
            fontFamily = appFontFamily,
            fontSize = 12.sp,
            color = Color.White.copy(alpha = 0.6f),
        )

        if (users.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    L10n.string(
                        "No players on the map for this selection yet",
                        "По этому выбору пока нет игроков на карте",
                    ),
                    fontFamily = appFontFamily,
                    fontSize = 15.sp,
                    color = Color.White.copy(alpha = 0.75f),
                    textAlign = TextAlign.Center,
                )
                Text(
                    L10n.string("Open player cards", "Открыть карточки игроков"),
                    modifier = Modifier
                        .heightIn(min = 44.dp)
                        .clickable(enabled = isEnabled, onClick = onShowCards)
                        .padding(top = 12.dp),
                    fontFamily = appFontFamily,
                    fontSize = 15.sp,
                    color = AppTheme.court,
                )
            }
        }
    }
}

/** `SimilarPlayersMapGrid.sportChip(_:)`. */
@Composable
private fun SimilarPlayersSportChip(
    sport: Sport?,
    selectedSport: Sport?,
    isEnabled: Boolean,
    onSelect: (Sport?) -> Unit,
) {
    val isSelected = selectedSport == sport
    Text(
        sport?.title ?: L10n.string("All sports", "Все виды"),
        modifier = Modifier
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(percent = 50))
            .background(if (isSelected) Color(0xFFA1EDBF) else Color.White.copy(alpha = 0.07f))
            .clickable(enabled = isEnabled) { onSelect(sport) }
            .padding(horizontal = 14.dp)
            .padding(top = 12.dp),
        fontFamily = appFontFamily,
        fontSize = 15.sp,
        fontWeight = FontWeight.SemiBold,
        color = if (isSelected) Color.Black else Color.White.copy(alpha = 0.75f),
    )
}

/** Port of `showViewedPlayersButton`. */
@Composable
fun ShowViewedPlayersButton(count: Int, isEnabled: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(AppTheme.mint.copy(alpha = 0.09f))
            .clickable(enabled = isEnabled, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            L10n.string("Viewed · $count", "Просмотренные · $count"),
            fontFamily = appFontFamily,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppTheme.mint,
            maxLines = 1,
        )
        Icon(
            Icons.Filled.ArrowDownward,
            contentDescription = null,
            tint = AppTheme.mint,
            modifier = Modifier.size(12.dp),
        )
    }
}

/** Port of `viewedPlayersTray`. */
@Composable
fun ViewedPlayersTray(
    users: List<DiscoverUser>,
    currentUserId: String?,
    isEnabled: Boolean,
    onReplay: (String) -> Unit,
) {
    Column(
        modifier = Modifier.padding(top = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Filled.History,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.8f),
                modifier = Modifier.size(13.dp),
            )
            Text(
                L10n.string("Viewed", "Просмотренные"),
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.8f),
            )
            Text(
                "${users.size}",
                fontFamily = appFontFamily,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.58f),
            )
            Spacer(Modifier.weight(1f))
            Text(
                L10n.string("Tap to view again", "Нажми, чтобы вернуться"),
                fontFamily = appFontFamily,
                fontSize = 11.sp,
                color = Color.White.copy(alpha = 0.48f),
            )
        }

        Row(
            // SwiftUI pins the ScrollView to 76pt, which fits its own text metrics;
            // here the row sizes to its content so the names are never clipped.
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(vertical = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            users.forEach { user ->
                val isCurrent = currentUserId == user.id
                Column(
                    modifier = Modifier
                        .width(70.dp)
                        .clickable(enabled = isEnabled) { onReplay(user.id) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    // 46pt avatar; SwiftUI draws the ring on an overlay inset by -2,
                    // which does not add to the row's height.
                    Box(
                        modifier = Modifier
                            .size(46.dp)
                            .border(
                                if (isCurrent) 2.dp else 1.dp,
                                if (isCurrent) AppTheme.mint else Color.White.copy(alpha = 0.18f),
                                continuousShape(17.dp),
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        RemoteAvatarView(name = user.displayName, path = user.profileHeroImagePath, size = 46.dp)
                    }
                    Text(
                        user.displayName,
                        fontFamily = appFontFamily,
                        fontSize = 11.sp,
                        lineHeight = 15.sp,
                        fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (isCurrent) AppTheme.mint else Color.White.copy(alpha = 0.72f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}
