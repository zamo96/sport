package shop.sportsearch.app.ui.courts

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

private val sheetBackground = Brush.verticalGradient(
    listOf(Color.Black, Color(red = 4 / 255f, green = 13 / 255f, blue = 13 / 255f), Color.Black),
)

/** Port of `struct CourtDetailSheet` in ios/TennisSearchIOS/Views/CourtsView.swift. */
@Composable
fun CourtDetailSheet(
    court: Court,
    isSaved: Boolean,
    accessLabel: String?,
    onDismiss: () -> Unit,
    onToggleSave: () -> Unit,
    onToggleMembership: suspend () -> Unit,
    onProposeGame: () -> Unit,
    onPlanPersonalVisit: () -> Unit,
    onProposeToPlayer: (DiscoverUser) -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()
    val androidContext = LocalContext.current
    var isUpdatingMembership by remember { mutableStateOf(false) }
    var selectedPlayerProfile by remember { mutableStateOf<DiscoverUser?>(null) }

    fun open(url: String?) {
        val target = url ?: return
        runCatching { androidContext.startActivity(Intent(Intent.ACTION_VIEW, target.toUri())) }
        haptics.selection()
    }

    selectedPlayerProfile?.let { player ->
        CourtPlayerProfileSheet(
            player = player,
            court = court,
            onDismiss = { selectedPlayerProfile = null },
            onProposeGame = {
                selectedPlayerProfile = null
                onProposeToPlayer(player)
            },
        )
        return
    }

    val activeSearchPeopleCount =
        if (court.activeSearchPlayersCount > 0) court.activeSearchPlayersCount else court.activeSearchesCount

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(sheetBackground)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(horizontal = 18.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // compactHeader
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(22.dp))
                .background(Color.White.copy(alpha = 0.055f))
                .border(1.dp, DarkStroke, continuousShape(22.dp))
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.Top,
        ) {
            CourtImageTile(court, 118.dp)

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                    Text(
                        court.name,
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.07f))
                            .clickable {
                                onToggleSave()
                                haptics.selection()
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            if (isSaved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                            null,
                            tint = Color.White,
                            modifier = Modifier.size(17.dp),
                        )
                    }
                }

                Text(
                    court.sportsTitle(null),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = CourtAccent,
                    maxLines = 1,
                )
                Text(
                    listOfNotNull(court.metroDisplayName, accessLabel ?: court.distanceLabel).joinToString(" · "),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.7f),
                    maxLines = 2,
                )
                Text(
                    court.displayAddress,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.52f),
                    maxLines = 2,
                )
            }
        }

        // compactContactRail
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            CompactCourtAction(
                L10n.string("Book", "Бронь"),
                Icons.Filled.EditCalendar,
                court.bookingLinkUrl != null,
            ) { open(court.bookingLinkUrl) }
            CompactCourtAction(
                L10n.string("Website", "Сайт"),
                Icons.Filled.Language,
                court.websiteLinkUrl != null,
            ) { open(court.websiteLinkUrl) }
            CompactCourtAction(
                L10n.string("Call", "Позвонить"),
                Icons.Filled.Call,
                court.dialUri != null,
            ) { open(court.dialUri) }
            CompactCourtAction(
                court.messengerTitle,
                Icons.AutoMirrored.Filled.Send,
                court.messengerLinkUrl != null,
            ) { open(court.messengerLinkUrl) }
        }

        // compactSummaryBlock
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(20.dp))
                .background(Color.White.copy(alpha = 0.045f))
                .border(1.dp, Color.White.copy(alpha = 0.08f), continuousShape(20.dp))
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                court.workingHours?.takeIf { it.isNotEmpty() }?.let {
                    CourtInfoPill(Icons.Filled.Schedule, it)
                }
                court.priceRange?.takeIf { it.isNotEmpty() }?.let {
                    CourtInfoPill(Icons.Filled.CreditCard, it)
                }
            }

            Text(
                court.detailDescription,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.66f),
                lineHeight = 20.sp,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )

            if (court.displayTags.isNotEmpty()) {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    court.displayTags.take(6).forEach { CourtAmenityPill(it) }
                }
            }
        }

        // compactActivityBlock
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(64.dp)
                .clip(continuousShape(18.dp))
                .background(Color.White.copy(alpha = 0.045f))
                .border(1.dp, Color.White.copy(alpha = 0.08f), continuousShape(18.dp))
                .padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(9.dp)
                    .clip(CircleShape)
                    .background(if (activeSearchPeopleCount > 0) CourtAccent else Color.White.copy(alpha = 0.28f)),
            )

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (activeSearchPeopleCount > 0) {
                        activeSearchText(activeSearchPeopleCount)
                    } else {
                        L10n.string("No active searches yet", "Активных поисков пока нет")
                    },
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    if (activeSearchPeopleCount > 0) {
                        L10n.string("Respond or create your own game", "Можно откликнуться или создать свою игру")
                    } else {
                        L10n.string("Create a search at this club", "Создайте поиск в этом клубе")
                    },
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.54f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            CourtActiveSearchAvatars(
                users = court.activeSearchPreviewUsers,
                overflowCount = maxOf(activeSearchPeopleCount - court.activeSearchPreviewUsers.size, 0),
                size = 32.dp,
            )
        }

        // membershipBlock
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(18.dp))
                .background(Color.White.copy(alpha = if (court.isMember) 0.09f else 0.055f))
                .border(
                    1.dp,
                    if (court.isMember) CourtAccent.copy(alpha = 0.42f) else Color.White.copy(alpha = 0.1f),
                    continuousShape(18.dp),
                )
                .clickable(enabled = !isUpdatingMembership) {
                    scope.launch {
                        isUpdatingMembership = true
                        onToggleMembership()
                        isUpdatingMembership = false
                    }
                }
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier.size(48.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.075f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (court.isMember) Icons.Filled.CheckCircle else Icons.Filled.SportsTennis,
                    null,
                    tint = if (court.isMember) CourtAccent else Color.White.copy(alpha = 0.86f),
                    modifier = Modifier.size(22.dp),
                )
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    if (court.isMember) {
                        L10n.string("You play here", "Вы ходите сюда")
                    } else {
                        L10n.string("I play here", "Я хожу сюда")
                    },
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                Text(
                    L10n.string(
                        "Players will see you in the club list and can invite you to a game.",
                        "Игроки увидят вас в списке клуба и смогут предложить игру.",
                    ),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.58f),
                    maxLines = 2,
                )
            }

            if (isUpdatingMembership) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            } else {
                Icon(
                    if (court.isMember) Icons.Filled.Remove else Icons.Filled.Add,
                    null,
                    tint = Color.White.copy(alpha = 0.62f),
                    modifier = Modifier.size(20.dp),
                )
            }
        }

        // compactPlayersBlock
        if (court.members.isNotEmpty() || court.memberCount > 0) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(20.dp))
                    .background(Color.White.copy(alpha = 0.045f))
                    .border(1.dp, Color.White.copy(alpha = 0.08f), continuousShape(20.dp))
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L10n.string("Club players", "Игроки клуба"),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                    Spacer(Modifier.weight(1f))
                    if (court.memberCount > 0) {
                        Box(
                            modifier = Modifier
                                .height(24.dp)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.08f))
                                .padding(horizontal = 9.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "${court.memberCount}",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = CourtAccent,
                            )
                        }
                    }
                }

                if (court.members.isEmpty()) {
                    Text(
                        if (court.isMember) {
                            L10n.string(
                                "You are the first to check in at this club.",
                                "Вы первый отметились в этом клубе.",
                            )
                        } else {
                            L10n.string("Check in if you play here.", "Отметьтесь, если ходите сюда.")
                        },
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.54f),
                        maxLines = 2,
                    )
                } else {
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        court.members.take(8).forEach { player ->
                            Column(
                                modifier = Modifier
                                    .clip(continuousShape(16.dp))
                                    .background(Color.White.copy(alpha = 0.055f))
                                    .clickable {
                                        haptics.selection()
                                        selectedPlayerProfile = player
                                    }
                                    .padding(horizontal = 6.dp, vertical = 8.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                RemoteAvatarView(name = player.displayName, path = player.avatarUrl, size = 44.dp)
                                Text(
                                    player.displayName,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White.copy(alpha = 0.82f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.width(64.dp),
                                )
                            }
                        }
                    }
                }
            }
        }

        // compactFooterActions
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FooterAction(
                title = L10n.string("Visit", "Визит"),
                icon = Icons.AutoMirrored.Filled.DirectionsRun,
                background = Color.White.copy(alpha = 0.08f),
                foreground = Color.White,
                bordered = true,
                modifier = Modifier.weight(1f),
                onClick = onPlanPersonalVisit,
            )
            FooterAction(
                title = L10n.string("Find a game", "Найти игру"),
                icon = Icons.Filled.EditCalendar,
                background = CourtAccent,
                foreground = Color.Black,
                bordered = false,
                modifier = Modifier.weight(1f),
                onClick = onProposeGame,
            )
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(16.dp))
                .background(Color.White.copy(alpha = 0.05f))
                .clickable(onClick = onDismiss)
                .padding(vertical = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                L10n.string("Close", "Закрыть"),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.7f),
            )
        }
    }
}

@Composable
private fun FooterAction(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    background: Color,
    foreground: Color,
    bordered: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = continuousShape(16.dp)
    Row(
        modifier = modifier
            .height(52.dp)
            .clip(shape)
            .background(background)
            .then(if (bordered) Modifier.border(1.dp, DarkStroke, shape) else Modifier)
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = foreground, modifier = Modifier.size(17.dp))
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = foreground, maxLines = 1)
    }
}

/** Port of `struct CourtPlayerProfileSheet`, nested inside `CourtDetailSheet`. */
@Composable
private fun CourtPlayerProfileSheet(
    player: DiscoverUser,
    court: Court,
    onDismiss: () -> Unit,
    onProposeGame: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val haptics = rememberAppHaptics()
    val courtSports = court.supportedSports.ifEmpty { player.preferredSports }
    val commonSports = player.preferredSports.filter { it in courtSports.toSet() }
        .ifEmpty { courtSports.take(4) }
    val primarySport = commonSports.firstOrNull() ?: court.primarySport
        ?: player.preferredSports.firstOrNull() ?: Sport.TENNIS
    val levelSummary = (player.sportLevels[primarySport.wire] ?: player.tennisLevel)
        ?.let { "$it/10" } ?: L10n.string("level not provided", "уровень не указан")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(horizontal = 16.dp)
            .padding(top = 18.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(26.dp))
                .background(Color.White.copy(alpha = 0.06f))
                .border(1.dp, DarkStroke, continuousShape(26.dp))
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
                RemoteAvatarView(name = player.displayName, path = player.avatarUrl, size = 86.dp)

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        player.displayName,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        listOfNotNull(
                            player.age?.let { L10n.string("$it years old", "$it лет") },
                            player.city,
                        ).joinToString(", "),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.62f),
                    )
                    Text(
                        player.districtDisplaySummary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppTheme.court,
                        maxLines = 2,
                    )
                }
            }

            player.bio?.takeIf { it.isNotEmpty() }?.let { bio ->
                Text(
                    bio,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.68f),
                    lineHeight = 21.sp,
                )
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(26.dp))
                .background(Color.White.copy(alpha = 0.045f))
                .border(1.dp, Color.White.copy(alpha = 0.08f), continuousShape(26.dp))
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                L10n.string("At this club", "В этом клубе"),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(20.dp))
                    .background(Color.White.copy(alpha = 0.05f))
                    .padding(14.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier.size(42.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.08f)),
                    contentAlignment = Alignment.Center,
                ) {
                    SportIconView(sport = primarySport, color = AppTheme.court, size = 20.dp)
                }

                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        court.name,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 2,
                    )
                    Text(
                        "${commonSports.joinToString(" · ") { it.title }} · $levelSummary",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.58f),
                        maxLines = 2,
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp)
                    .clip(continuousShape(20.dp))
                    .background(AppTheme.court)
                    .clickable {
                        haptics.impactMedium()
                        onProposeGame()
                    },
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.EditCalendar, null, tint = Color.White, modifier = Modifier.size(18.dp))
                Text(
                    L10n.string("Invite to a game here", "Предложить игру здесь"),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(16.dp))
                .background(Color.White.copy(alpha = 0.05f))
                .clickable(onClick = onDismiss)
                .padding(vertical = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                L10n.string("Close", "Закрыть"),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.7f),
            )
        }
    }
}
