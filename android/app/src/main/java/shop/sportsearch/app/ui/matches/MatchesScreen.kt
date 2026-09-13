package shop.sportsearch.app.ui.matches

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.*
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import shop.sportsearch.app.ui.theme.statusTintColor
import java.time.LocalDate
import java.time.ZoneId

/** Port of `private enum MatchListFilter` in MatchesView.swift. */
private enum class MatchListFilter {
    ALL, NEW, ACTION, WITH_GAME, ARCHIVE;

    val localizedTitle: String
        get() = when (this) {
            ALL -> L10n.string("All", "Все")
            NEW -> L10n.string("New", "Новые")
            ACTION -> L10n.string("Action needed", "Нужно действие")
            WITH_GAME -> L10n.string("Confirmed", "Подтверждены")
            ARCHIVE -> L10n.string("Archive", "Архив")
        }

    val badgeTint: Color
        get() = when (this) {
            ALL -> AppTheme.court
            NEW -> Color(red = 0.29f, green = 0.48f, blue = 0.95f)
            ACTION -> Color(red = 0.94f, green = 0.58f, blue = 0.18f)
            WITH_GAME -> AppTheme.court
            ARCHIVE -> Color.White.copy(alpha = 0.62f)
        }

    fun matches(match: MatchSummary, currentUserId: String?): Boolean {
        val request = match.latestGameRequest
        return when (this) {
            ALL -> true
            NEW -> request == null
            ACTION -> request?.isPendingForRecipient(currentUserId) == true
            WITH_GAME -> request != null && request.status.lowercase() in setOf("accepted", "approved")
            ARCHIVE -> request != null &&
                (
                    request.status.lowercase() in setOf("declined", "rejected", "withdrawn", "canceled", "cancelled") ||
                        request.statusLabel == "Игра закончилась"
                    )
        }
    }

    /** Incoming likes only count toward the filters that actually show them. */
    fun showsIncomingLikes(): Boolean = this == ALL || this == NEW || this == ACTION

    fun count(matches: List<MatchSummary>, incomingLikesCount: Int, currentUserId: String?): Int =
        matches.count { matches(it, currentUserId) } + if (showsIncomingLikes()) incomingLikesCount else 0
}

private data class AvatarPreviewItem(val name: String, val path: String?)

/** Port of `struct MatchesView`. */
@Composable
fun MatchesScreen(appModel: AppViewModel) {
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()

    var matches by remember { mutableStateOf<List<MatchSummary>>(emptyList()) }
    var incomingLikes by remember { mutableStateOf<List<DiscoverUser>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var selectedFilter by remember { mutableStateOf(MatchListFilter.ALL) }
    var updatingRequestIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var updatingIncomingLikeIds by remember { mutableStateOf<Set<String>>(emptySet()) }

    var openChatMatch by remember { mutableStateOf<MatchSummary?>(null) }
    var profileMatch by remember { mutableStateOf<MatchSummary?>(null) }
    var proposalMatch by remember { mutableStateOf<MatchSummary?>(null) }
    var avatarPreview by remember { mutableStateOf<AvatarPreviewItem?>(null) }

    suspend fun loadMatches() {
        val reportsMenuLoading = matches.isEmpty()
        if (reportsMenuLoading) appModel.setTabContentLoading("matches", true)
        isLoading = true

        runCatching { appModel.repository.fetchMatches() }
            .onSuccess { matches = it }
            .onFailure(appModel::present)

        incomingLikes = if (appModel.isAuthenticated) {
            runCatching { appModel.repository.fetchDiscoverUsers(DiscoverTab.LIKES) }.getOrDefault(emptyList())
        } else {
            emptyList()
        }

        isLoading = false
        if (reportsMenuLoading) appModel.setTabContentLoading("matches", false)
    }

    fun handleBlockedUser(userId: String) {
        profileMatch = null
        matches = matches.filterNot { it.otherUser.id == userId }
        incomingLikes = incomingLikes.filterNot { it.id == userId }
        appModel.errorMessage = null
        scope.launch { loadMatches() }
    }

    LaunchedEffect(Unit) {
        runCatching { appModel.repository.markInboxSeen() }
        if (matches.isEmpty()) loadMatches()
    }

    LaunchedEffect(appModel.pendingChatMatchID, matches) {
        val pending = appModel.pendingChatMatchID ?: return@LaunchedEffect
        val found = matches.firstOrNull { it.id == pending }
            ?: runCatching { appModel.repository.fetchMatches() }
                .onSuccess { matches = it }
                .getOrNull()
                ?.firstOrNull { it.id == pending }
        if (found != null) {
            openChatMatch = found
            appModel.pendingChatMatchID = null
        }
    }

    // Full-screen destinations, matching iOS `navigationDestination` / `.sheet`.
    openChatMatch?.let { match ->
        ChatScreen(
            appModel = appModel,
            match = match,
            onBack = { openChatMatch = null },
            onBlocked = {
                handleBlockedUser(match.otherUser.id)
                openChatMatch = null
            },
        )
        return
    }

    profileMatch?.let { match ->
        HideBottomBarWhileVisible(appModel)
        MatchPlayerSheet(
            appModel = appModel,
            match = match,
            onDismiss = { profileMatch = null },
            onOpenChat = {
                profileMatch = null
                openChatMatch = match
            },
            onProposeGame = {
                profileMatch = null
                proposalMatch = match
            },
            onBlocked = { handleBlockedUser(match.otherUser.id) },
        )
        return
    }

    proposalMatch?.let { match ->
        GameProposalSheet(
            appModel = appModel,
            match = match,
            onDismiss = { proposalMatch = null },
            onCreated = {
                loadMatches()
                proposalMatch = null
                openChatMatch = match
            },
        )
        return
    }

    val currentUserId = appModel.currentUser?.id
    val filteredMatches = matches.filter { selectedFilter.matches(it, currentUserId) }
    val visibleIncomingLikes = if (selectedFilter.showsIncomingLikes()) incomingLikes else emptyList()

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                DarkScreenHeader(
                    title = L10n.string("Matches", "Мэтчи"),
                    subtitle = L10n.string("Chats and game arrangements", "Чаты и договоренности по играм"),
                )
            }

            item {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    MatchListFilter.entries.forEach { filter ->
                        val selected = selectedFilter == filter
                        val count = filter.count(matches, incomingLikes.size, currentUserId)
                        Row(
                            modifier = Modifier
                                .height(42.dp)
                                .clip(CircleShape)
                                .background(if (selected) AppTheme.court else Color.White.copy(alpha = 0.06f))
                                .clickable { selectedFilter = filter }
                                .padding(horizontal = 15.dp),
                            horizontalArrangement = Arrangement.spacedBy(7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                filter.localizedTitle,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (selected) Color.White else Color.White.copy(alpha = 0.72f),
                                maxLines = 1,
                            )
                            if (count > 0) {
                                Box(
                                    modifier = Modifier
                                        .defaultMinSize(minWidth = 20.dp, minHeight = 20.dp)
                                        .clip(CircleShape)
                                        .background(
                                            if (selected) {
                                                Color.White.copy(alpha = 0.18f)
                                            } else {
                                                filter.badgeTint.copy(alpha = 0.24f)
                                            },
                                        ),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        "$count",
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (selected) Color.White else filter.badgeTint,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if (visibleIncomingLikes.isNotEmpty()) {
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            L10n.string("Waiting for your response", "Ждут решения"),
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(AppTheme.court.copy(alpha = 0.18f))
                                .padding(horizontal = 9.dp, vertical = 5.dp),
                        ) {
                            Text(
                                "${visibleIncomingLikes.size}",
                                style = AppText.captionBold,
                                color = AppTheme.court,
                            )
                        }
                        Spacer(Modifier.weight(1f))
                    }
                }

                items(visibleIncomingLikes.size) { index ->
                    val user = visibleIncomingLikes[index]
                    IncomingLikeDecisionCard(
                        user = user,
                        isUpdating = updatingIncomingLikeIds.contains(user.id),
                        onOpenAvatar = {
                            haptics.selection()
                            avatarPreview = AvatarPreviewItem(user.displayName, user.avatarUrl)
                        },
                        onDecide = { action ->
                            if (updatingIncomingLikeIds.contains(user.id)) return@IncomingLikeDecisionCard
                            scope.launch {
                                updatingIncomingLikeIds = updatingIncomingLikeIds + user.id
                                runCatching { appModel.repository.swipe(user.id, action) }
                                    .onSuccess { createdMatchId ->
                                        incomingLikes = incomingLikes.filterNot { it.id == user.id }
                                        if (action == SwipeAction.DISLIKE) haptics.warning() else haptics.success()
                                        loadMatches()
                                        if (createdMatchId != null) {
                                            matches.firstOrNull {
                                                it.id == createdMatchId || it.otherUser.id == user.id
                                            }?.let { openChatMatch = it }
                                        }
                                    }
                                    .onFailure(appModel::present)
                                updatingIncomingLikeIds = updatingIncomingLikeIds - user.id
                            }
                        },
                    )
                }
            }

            if (filteredMatches.isEmpty() && visibleIncomingLikes.isEmpty() && !isLoading) {
                item {
                    DarkEmptyState(
                        title = L10n.string("No matches yet", "Пока нет мэтчей"),
                        subtitle = L10n.string(
                            "Like a few players in Discover. Mutual interest will automatically appear here.",
                            "Поставь несколько лайков в поиске. Взаимные интересы автоматически появятся здесь.",
                        ),
                    )
                }
            }

            if (filteredMatches.isNotEmpty()) {
                item {
                    val shape = continuousShape(24.dp)
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(shape)
                            .background(
                                Brush.linearGradient(
                                    listOf(Color.White.copy(alpha = 0.075f), Color.White.copy(alpha = 0.035f)),
                                ),
                            )
                            .border(1.dp, Color.White.copy(alpha = 0.08f), shape),
                    ) {
                        filteredMatches.forEachIndexed { index, match ->
                            MatchInboxCard(
                                match = match,
                                currentUserId = currentUserId,
                                isUpdating = match.latestGameRequest?.let { updatingRequestIds.contains(it.id) } == true,
                                onOpenAvatar = {
                                    haptics.selection()
                                    avatarPreview = AvatarPreviewItem(match.otherUser.displayName, match.otherUser.avatarUrl)
                                },
                                onOpenChat = { openChatMatch = match },
                                onOpenProfile = { profileMatch = match },
                            )

                            if (index < filteredMatches.lastIndex) {
                                Box(
                                    Modifier
                                        .padding(start = 92.dp)
                                        .fillMaxWidth()
                                        .height(1.dp)
                                        .background(Color.White.copy(alpha = 0.08f)),
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    avatarPreview?.let { item ->
        AvatarPreviewSheet(name = item.name, path = item.path, onDismiss = { avatarPreview = null })
    }
}

/** Port of `struct IncomingLikeDecisionCard`. */
@Composable
private fun IncomingLikeDecisionCard(
    user: DiscoverUser,
    isUpdating: Boolean,
    onOpenAvatar: () -> Unit,
    onDecide: (SwipeAction) -> Unit,
) {
    val primarySport = user.preferredSports.firstOrNull() ?: Sport.TENNIS
    val district = user.districtDisplayNames.firstOrNull() ?: user.districtDisplaySummary
    val reasonLine = user.explainabilityReasons.firstOrNull()?.localizedMatchesText
        ?: L10n.string(
            "This player has already said they would like to play with you.",
            "Игрок уже отметил, что хочет с вами сыграть.",
        )
    val shape = continuousShape(24.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(listOf(Color.White.copy(alpha = 0.09f), Color.White.copy(alpha = 0.045f))),
            )
            .border(1.dp, AppTheme.court.copy(alpha = 0.24f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(13.dp), verticalAlignment = Alignment.CenterVertically) {
            Box {
                RemoteAvatarView(
                    name = user.displayName,
                    path = user.avatarUrl,
                    size = 58.dp,
                    modifier = Modifier.clickable(onClick = onOpenAvatar),
                )
                if (user.isOnline) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(13.dp)
                            .clip(CircleShape)
                            .background(Color(red = 0.22f, green = 0.82f, blue = 0.45f))
                            .border(2.dp, Color.Black, CircleShape),
                    )
                }
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        user.displayName,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    AppInlineChip(
                        text = L10n.string("Wants to play", "Хочет сыграть"),
                        tint = AppTheme.court.copy(alpha = 0.18f),
                        foreground = AppTheme.mint,
                    )
                }

                Text(
                    "${primarySport.title} · $district",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color(red = 0.41f, green = 0.86f, blue = 0.56f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )

                Text(
                    reasonLine,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.62f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            DecisionButton(
                modifier = Modifier.weight(1f),
                tint = Color.White.copy(alpha = 0.12f),
                foreground = Color.White.copy(alpha = 0.82f),
                enabled = !isUpdating,
                onClick = { onDecide(SwipeAction.DISLIKE) },
            ) {
                Icon(Icons.Filled.Close, null, tint = Color.White.copy(alpha = 0.82f), modifier = Modifier.size(14.dp))
                Text(
                    L10n.string("Skip", "Пропустить"),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.82f),
                )
            }

            DecisionButton(
                modifier = Modifier.weight(1f),
                tint = AppTheme.court,
                foreground = Color.White,
                enabled = !isUpdating,
                onClick = { onDecide(SwipeAction.LIKE) },
            ) {
                if (isUpdating) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
                }
                SportIconView(sport = primarySport, color = Color.White, size = 16.dp)
                Text(
                    L10n.string("Let's play", "Можно сыграть"),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }
    }
}

@Composable
private fun DecisionButton(
    modifier: Modifier,
    tint: Color,
    foreground: Color,
    enabled: Boolean,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    Row(
        modifier = modifier
            .clip(continuousShape(14.dp))
            .background(tint)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

/** Port of `struct MatchInboxCard`. */
@Composable
private fun MatchInboxCard(
    match: MatchSummary,
    currentUserId: String?,
    isUpdating: Boolean,
    onOpenAvatar: () -> Unit,
    onOpenChat: () -> Unit,
    onOpenProfile: () -> Unit,
) {
    val other = match.otherUser
    val request = match.latestGameRequest
    val primarySport = other.preferredSports.firstOrNull() ?: Sport.TENNIS

    val timestampText = run {
        val source = match.lastMessage?.createdAt ?: request?.proposedDatetime ?: match.createdAt
        val date = parseServerInstant(source)
        when {
            date == null -> source.formattedDateTime()
            date.atZone(ZoneId.systemDefault()).toLocalDate() == LocalDate.now(ZoneId.systemDefault()) ->
                date.formattedHourMinute()
            date.atZone(ZoneId.systemDefault()).toLocalDate() == LocalDate.now(ZoneId.systemDefault()).minusDays(1) ->
                L10n.string("Yesterday", "Вчера")
            else -> date.formattedDayMonth()
        }
    }

    val statusLineText = when {
        request == null -> L10n.string("New match", "Новый мэтч")
        request.isPendingForRecipient(currentUserId) -> L10n.string("Action needed", "Нужно действие")
        else -> request.statusLabel.localizedMatchesText
    }
    val statusLineTint = if (request?.isPendingForRecipient(currentUserId) == true) {
        Color(red = 1.0f, green = 0.62f, blue = 0.18f)
    } else {
        request?.statusTintColor ?: Color(red = 0.36f, green = 0.41f, blue = 0.83f)
    }

    val upcomingGameLine = request?.let {
        "${it.sport.title} · ${it.proposedDatetime.formattedDateTime()} · " +
            (it.proposedCourt?.name ?: it.sport.venueUnspecifiedTitle)
    }
    val sportDistrictLine = "${primarySport.title} · " +
        (other.districtDisplayNames.firstOrNull() ?: other.districtDisplaySummary)

    val lastMessagePreview = match.lastMessage?.let { message ->
        val text = message.text.trim()
        val content = when {
            text.isNotEmpty() -> text
            message.attachments.size > 1 ->
                L10n.string("${message.attachments.size} photos", "${message.attachments.size} фото")
            message.attachments.isNotEmpty() -> L10n.string("Photo", "Фото")
            else -> null
        }
        content?.let {
            if (message.senderUserId == currentUserId) {
                L10n.string("You: $it", "Вы: $it")
            } else {
                "${message.senderUser?.name ?: other.displayName}: $it"
            }
        }
    }
    val conversationPreview = lastMessagePreview ?: request?.comment
        ?: L10n.string("No messages yet. Be the first to say hi.", "Сообщений пока нет. Напиши первым.")

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpenChat)
            .padding(horizontal = 16.dp, vertical = 15.dp),
        horizontalArrangement = Arrangement.spacedBy(13.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(modifier = Modifier.clickable(onClick = onOpenAvatar)) {
            RemoteAvatarView(
                name = other.displayName,
                path = other.avatarUrl,
                size = 62.dp,
                modifier = Modifier.clip(continuousShape(18.dp)),
            )
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = 2.dp, y = 2.dp)
                    .size(14.dp)
                    .clip(CircleShape)
                    .background(
                        if (other.isOnline) {
                            Color(red = 0.22f, green = 0.82f, blue = 0.45f)
                        } else {
                            Color.White.copy(alpha = 0.28f)
                        },
                    )
                    .border(2.dp, Color.Black, CircleShape),
            )
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    other.displayName,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false).clickable(onClick = onOpenProfile),
                )
                Text(
                    other.presenceLabel,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (other.isOnline) {
                        Color(red = 0.38f, green = 0.93f, blue = 0.62f)
                    } else {
                        Color.White.copy(alpha = 0.44f)
                    },
                    maxLines = 1,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    timestampText,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.52f),
                    maxLines = 1,
                )
            }

            Text(
                upcomingGameLine ?: sportDistrictLine,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.62f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            Text(
                conversationPreview,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.7f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    statusLineText,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = statusLineTint,
                    maxLines = 1,
                )

                Spacer(Modifier.weight(1f))

                if (isUpdating) {
                    CircularProgressIndicator(
                        color = Color.White.copy(alpha = 0.7f),
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(16.dp),
                    )
                } else if (request?.isPendingForRecipient(currentUserId) == true) {
                    Box(
                        modifier = Modifier
                            .size(26.dp)
                            .clip(CircleShape)
                            .background(Color(red = 0.29f, green = 0.48f, blue = 0.95f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("!", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
            }
        }
    }
}
