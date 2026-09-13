package shop.sportsearch.app.ui.searches

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.discover.DiscoverParticipantSheet
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `private enum SearchResponsesFilter`. */
private enum class SearchResponsesFilter {
    ALL, PENDING, APPROVED, REJECTED;

    val title: String
        get() = when (this) {
            ALL -> L10n.string("All", "Все")
            PENDING -> L10n.string("New", "Новые")
            APPROVED -> L10n.string("Approved", "Одобрены")
            REJECTED -> L10n.string("Rejected", "Отклонены")
        }

    fun count(responses: List<SearchResponse>): Int = when (this) {
        ALL -> responses.size
        PENDING -> responses.count { it.status == "pending" }
        APPROVED -> responses.count { it.status == "approved" }
        REJECTED -> responses.count { it.status == "rejected" }
    }
}

/** Port of `TimeRange.detailTitle` in SearchesView.swift. */
private val TimeRange.detailTitle: String
    get() = when (this) {
        TimeRange.MORNING -> L10n.string("Morning", "Утро")
        TimeRange.DAY -> L10n.string("Afternoon", "День")
        TimeRange.EVENING -> L10n.string("Evening (after 6 PM)", "Вечер (после 18:00)")
    }

/** Port of `struct SearchResponsesSheet`. */
@Composable
fun SearchResponsesSheet(
    appModel: AppViewModel,
    search: GameSearch,
    updatingResponseID: String?,
    isFinalizingRoster: Boolean,
    onDismiss: () -> Unit,
    onUpdateResponseStatus: (String, String) -> Unit,
    onShareInviteLink: () -> Unit,
    onFinalizeRoster: () -> Unit,
    onOpenLobby: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    var selectedFilter by remember { mutableStateOf(SearchResponsesFilter.ALL) }
    var selectedPlayer by remember { mutableStateOf<DiscoverUser?>(null) }

    selectedPlayer?.let { player ->
        DiscoverParticipantSheet(
            appModel = appModel,
            user = player,
            onDismiss = { selectedPlayer = null },
        )
        return
    }

    val filteredResponses = when (selectedFilter) {
        SearchResponsesFilter.ALL -> search.responses
        SearchResponsesFilter.PENDING -> search.responses.filter { it.status == "pending" }
        SearchResponsesFilter.APPROVED -> search.responses.filter { it.status == "approved" }
        SearchResponsesFilter.REJECTED -> search.responses.filter { it.status == "rejected" }
    }

    val approvedCount = search.responses.count { it.status == "approved" }
    val pendingCount = search.responses.count { it.status == "pending" }
    val canApproveMore = search.status != "matched" && approvedCount < maxOf(search.playersNeeded, 1)
    val shouldShowLobbyShortcut = search.playersNeeded > 1 && approvedCount > 0

    Column(modifier = Modifier.fillMaxSize().background(Color.White).statusBarsPadding()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier.size(44.dp).clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    null,
                    tint = AppTheme.ink,
                    modifier = Modifier.size(18.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            AppInlineChip(
                text = L10n.string(
                    "${search.responses.size} responses · $pendingCount new",
                    "${search.responses.size} откликов · $pendingCount новых",
                ),
                tint = AppTheme.mint,
                foreground = AppTheme.court,
            )
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(44.dp))
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = 16.dp)
                .padding(top = 16.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SearchSummaryCard(search)

            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                SearchResponsesFilter.entries.forEach { filter ->
                    val selected = selectedFilter == filter
                    Row(
                        modifier = Modifier
                            .height(40.dp)
                            .clip(CircleShape)
                            .background(if (selected) AppTheme.court else Color.White)
                            .border(
                                1.dp,
                                if (selected) AppTheme.court else Color.Black.copy(alpha = 0.08f),
                                CircleShape,
                            )
                            .clickable { selectedFilter = filter }
                            .padding(horizontal = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            filter.title,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (selected) Color.White else AppTheme.ink,
                        )
                        Text(
                            "${filter.count(search.responses)}",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (selected) {
                                Color.White.copy(alpha = 0.92f)
                            } else {
                                AppTheme.ink.copy(alpha = 0.58f)
                            },
                        )
                    }
                }
            }

            filteredResponses.forEach { response ->
                SearchResponseActionRow(
                    response = response,
                    canApprove = canApproveMore,
                    updatingResponseID = updatingResponseID,
                    onUpdateResponseStatus = onUpdateResponseStatus,
                    onOpenPlayer = { selectedPlayer = it },
                )
            }

            if (shouldShowLobbyShortcut) {
                Box {
                    PrimaryActionButton(
                        title = if (approvedCount >= maxOf(search.playersNeeded, 1)) {
                            L10n.string("Open roster", "Перейти к составу")
                        } else {
                            L10n.string("Finish without a full roster", "Завершить без полного добора")
                        },
                        tint = AppTheme.ink,
                        enabled = !isFinalizingRoster,
                        onClick = {
                            if (approvedCount >= maxOf(search.playersNeeded, 1)) onOpenLobby() else onFinalizeRoster()
                        },
                    )
                    if (isFinalizingRoster) {
                        Box(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(
                                color = Color.White,
                                strokeWidth = 2.dp,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                }
            }

            SecondaryActionButton(
                title = L10n.string("Invite more players", "Пригласить ещё игроков"),
                onClick = onShareInviteLink,
                tint = AppTheme.court,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

@Composable
private fun SearchSummaryCard(search: GameSearch) {
    val shape = continuousShape(24.dp)
    val min = search.desiredLevelMin
    val max = search.desiredLevelMax

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(42.dp).clip(CircleShape).background(AppTheme.mint),
                contentAlignment = Alignment.Center,
            ) {
                SportIconView(sport = search.sport, color = AppTheme.court, size = 18.dp)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "${search.sport.title} · ${search.sport.formatTitle(search.format, search.playersNeeded)}",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppTheme.ink,
                )
                Text(
                    if (min != null && max != null) {
                        L10n.string(
                            "Looking for ${search.playersNeeded} player(s), level $min–$max",
                            "Ищу ${search.playersNeeded} игроков уровня $min–$max",
                        )
                    } else {
                        L10n.string(
                            "Looking for ${search.playersNeeded} player(s)",
                            "Ищу ${search.playersNeeded} игроков",
                        )
                    },
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            CompactMetaRow(
                search.preferredDays.mapNotNull { DayOfWeek.from(it)?.shortTitle }.joinToString(", "),
            )
            CompactMetaRow(
                search.preferredTimeRanges.mapNotNull { TimeRange.from(it)?.detailTitle }.joinToString(" · "),
            )
        }

        CompactMetaRow(
            listOfNotNull(
                search.preferredDistricts.mapNotNull(::localizedDistrictName).joinToString(", "),
                search.preferredCourt?.name,
            ).filter { it.isNotEmpty() }.joinToString(" · "),
        )
    }
}

@Composable
private fun CompactMetaRow(text: String) {
    Text(
        text.ifEmpty { L10n.string("Not specified", "Не указано") },
        fontSize = 15.sp,
        fontWeight = FontWeight.Medium,
        color = AppTheme.ink.copy(alpha = 0.82f),
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
    )
}

/** Port of `struct SearchResponseActionRow`. */
@Composable
private fun SearchResponseActionRow(
    response: SearchResponse,
    canApprove: Boolean,
    updatingResponseID: String?,
    onUpdateResponseStatus: (String, String) -> Unit,
    onOpenPlayer: (DiscoverUser) -> Unit,
) {
    val user = response.responderUser
    val levelLine = (user.sportLevels["tennis"] ?: user.tennisLevel)?.let { "%.1f".format(it.toDouble()) }
    val shape = continuousShape(24.dp)
    val defaultSubtitle = when (response.status) {
        "approved" -> L10n.string("Player is already on the roster", "Игрок уже в составе")
        "rejected" -> L10n.string("The response was rejected", "Отклик был отклонён")
        else -> L10n.string("Wants to join the game", "Хочет присоединиться к игре")
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier.weight(1f).clickable { onOpenPlayer(user) },
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RemoteAvatarView(name = user.displayName, path = user.avatarUrl, size = 56.dp)

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        user.displayName,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = AppTheme.ink,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    levelLine?.let {
                        Text(it, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = AppTheme.ink.copy(alpha = 0.58f))
                    }
                    Spacer(Modifier.weight(1f))
                    when (response.status) {
                        "approved" -> AppInlineChip(
                            text = L10n.string("APPROVED", "ОДОБРЕН"),
                            tint = AppTheme.mint,
                            foreground = AppTheme.court,
                        )
                        "rejected" -> AppInlineChip(
                            text = L10n.string("REJECTED", "ОТКЛОНЁН"),
                            tint = Color.Red.copy(alpha = 0.12f),
                            foreground = Color.Red.copy(alpha = 0.9f),
                        )
                    }
                }

                Text(
                    user.bio?.trim()?.takeIf { it.isNotEmpty() } ?: defaultSubtitle,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppTheme.ink.copy(alpha = 0.68f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )

                (user.districtLabel ?: user.district)?.let { district ->
                    Text(
                        localizedDistrictName(district) ?: district,
                        style = AppText.footnote,
                        color = AppTheme.ink.copy(alpha = 0.5f),
                    )
                }
            }
        }

        if (response.status == "pending") {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (canApprove) {
                    CircleAction(
                        icon = Icons.Filled.Check,
                        tint = AppTheme.court,
                        foreground = Color.White,
                        isUpdating = updatingResponseID == response.id,
                    ) { onUpdateResponseStatus(response.id, "approved") }
                } else {
                    Box(
                        modifier = Modifier
                            .height(44.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.05f))
                            .padding(horizontal = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            L10n.string("Roster complete", "Состав собран"),
                            style = AppText.captionBold,
                            color = AppTheme.ink.copy(alpha = 0.54f),
                        )
                    }
                }

                CircleAction(
                    icon = Icons.Filled.Close,
                    tint = Color.Black.copy(alpha = 0.06f),
                    foreground = AppTheme.ink,
                    isUpdating = updatingResponseID == response.id,
                ) { onUpdateResponseStatus(response.id, "rejected") }
            }
        } else {
            Icon(
                Icons.Filled.ChevronRight,
                null,
                tint = AppTheme.ink.copy(alpha = 0.24f),
                modifier = Modifier.size(13.dp),
            )
        }
    }
}

@Composable
private fun CircleAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tint: Color,
    foreground: Color,
    isUpdating: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(tint)
            .clickable(enabled = !isUpdating, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (isUpdating) {
            CircularProgressIndicator(color = foreground, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        } else {
            Icon(icon, null, tint = foreground, modifier = Modifier.size(19.dp))
        }
    }
}
