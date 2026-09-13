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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.ChatReceiptLabel
import shop.sportsearch.app.ui.components.chatReceiptRow
import shop.sportsearch.app.ui.components.rememberChatReceipts
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.ChatAttachmentsGrid
import shop.sportsearch.app.ui.components.ChatMediaViewer
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PendingChatPhoto
import shop.sportsearch.app.ui.components.PendingPhotosRail
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.components.rememberChatPhotoPicker
import shop.sportsearch.app.ui.detailedMessage
import shop.sportsearch.app.ui.isCancellationLike
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `struct SearchLobbySheet` in ios/TennisSearchIOS/Views/SearchesView.swift:
 * the shared space for one search - roster, group chat, and (for a regular
 * one-on-one search) proposing or voting on recurring slots.
 */
@Composable
fun SearchLobbyScreen(
    appModel: AppViewModel,
    searchId: String,
    onDismiss: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    var lobby by remember { mutableStateOf<SearchLobbyGameSearch?>(null) }
    var lobbyLoadError by remember { mutableStateOf<String?>(null) }
    var courts by remember { mutableStateOf<List<Court>>(emptyList()) }
    var messageText by remember { mutableStateOf("") }
    var isSendingMessage by remember { mutableStateOf(false) }
    var isScheduling by remember { mutableStateOf(false) }
    var isVoting by remember { mutableStateOf(false) }
    var isCourtPickerOpen by remember { mutableStateOf(false) }
    var pendingPhotos by remember { mutableStateOf<List<PendingChatPhoto>>(emptyList()) }
    var viewerPath by remember { mutableStateOf<String?>(null) }

    // Slot-proposal draft state
    var proposedCourtId by remember { mutableStateOf("") }
    var selectedSlotDateKeys by remember { mutableStateOf<Set<String>>(emptySet()) }
    var selectedSlotTimes by remember { mutableStateOf(setOf("19:00")) }
    var selectedSlotTimeRange by remember { mutableStateOf(TimeRange.EVENING) }
    var slotComment by remember { mutableStateOf("") }
    var selectedVoteOptionIDs by remember { mutableStateOf<Set<String>>(emptySet()) }
    var reloadTick by remember { mutableIntStateOf(0) }

    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()
    val currentUserId = appModel.currentUser?.id
    val receiptTracker = rememberChatReceipts(
        repository = appModel.repository,
        searchId = searchId,
        incomingIds = lobby?.messages.orEmpty().filter { currentUserId != null && it.senderUserId != currentUserId }.map { it.id },
        conversationVisible = !isCourtPickerOpen && viewerPath == null,
    )

    suspend fun loadLobby(showErrors: Boolean = true) {
        if (showErrors) lobbyLoadError = null
        runCatching { appModel.repository.fetchSearchLobby(searchId) }
            .onSuccess {
                val previous = lobby?.messages.orEmpty().associateBy { message -> message.id }
                lobby = it.gameSearch.copy(messages = it.gameSearch.messages.map { message ->
                    message.copy(receipt = mergeChatReceipt(previous[message.id]?.receipt, message.receipt))
                })
                lobbyLoadError = null
            }
            .onFailure { error ->
                if (error.isCancellationLike) return
                if (showErrors) {
                    lobbyLoadError = error.detailedMessage
                    appModel.present(error)
                }
            }
    }

    // The composer hides the tab bar the same way; the lobby is a sheet on iOS too.
    DisposableEffect(Unit) {
        appModel.bottomBarDisplayMode = BottomBarDisplayMode.HIDDEN
        onDispose { appModel.bottomBarDisplayMode = BottomBarDisplayMode.EXPANDED }
    }

    LaunchedEffect(searchId, reloadTick) {
        loadLobby()
        courts = runCatching { appModel.repository.fetchCourts() }.getOrDefault(emptyList())
    }

    // Seed the day selection with the first offered date. Without this the rail
    // would highlight a day that is not actually in `selectedSlotDateKeys`, and
    // tapping a second day would silently replace it instead of adding to it.
    LaunchedEffect(lobby?.id) {
        val current = lobby ?: return@LaunchedEffect
        if (selectedSlotDateKeys.isEmpty()) {
            slotDateOptions(current).firstOrNull()?.let { selectedSlotDateKeys = setOf(dateKey(it)) }
        }
    }

    // `updateSearchLobbyPresence` - tells the backend this lobby is open.
    DisposableEffect(searchId) {
        val job = scope.launch {
            runCatching { appModel.repository.setActiveSearchLobby(searchId, true) }
        }
        onDispose {
            job.cancel()
            scope.launch { runCatching { appModel.repository.setActiveSearchLobby(searchId, false) } }
        }
    }

    // `runRealtimeLobbyUpdates`: poll every 2.5s, refreshing presence every 30s.
    LaunchedEffect(searchId) {
        var sincePresence = 0
        while (isActive) {
            delay(2500)
            sincePresence += 2500
            if (sincePresence >= 30_000) {
                sincePresence = 0
                runCatching { appModel.repository.setActiveSearchLobby(searchId, true) }
            }
            loadLobby(showErrors = false)
        }
    }

    val current = lobby
    val approved = current?.responses?.filter { it.status == "approved" }.orEmpty()
    val pending = current?.responses?.filter { it.status == "pending" }.orEmpty()
    val isCreator = current?.createdByUserId == appModel.currentUser?.id

    val canProposeSlots = current != null && isCreator &&
        current.searchType == SearchType.REGULAR && current.playersNeeded <= 1 && approved.isNotEmpty()
    val canVoteForSlots = current != null &&
        current.searchType == SearchType.REGULAR && current.playersNeeded <= 1 && current.activeSlotProposal != null

    val availableCourts = courts.filter { court ->
        val sports = court.supportedSports
        sports.isEmpty() || current == null || sports.contains(current.sport)
    }
    val selectedCourtName = availableCourts.firstOrNull { it.id == proposedCourtId }?.name
        ?: current?.preferredCourt?.name
        ?: L10n.string("No club", "Без клуба")

    val openedPath = viewerPath
    if (openedPath != null) {
        ChatMediaViewer(
            repository = appModel.repository,
            path = openedPath,
            onDismiss = { viewerPath = null },
        )
        return
    }

    if (isCourtPickerOpen) {
        SearchClubPickerSheet(
            sport = current?.sport ?: Sport.TENNIS,
            courts = availableCourts,
            selectedCourtId = proposedCourtId.takeIf { it.isNotEmpty() },
            onSelect = { court ->
                proposedCourtId = court?.id.orEmpty()
                isCourtPickerOpen = false
            },
            onDismiss = { isCourtPickerOpen = false },
        )
        return
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.White)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 16.dp)
                .padding(top = 12.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SheetHeader(title = L10n.string("Search lobby", "Лобби поиска"), onClose = onDismiss)

            when {
                current != null -> {
                    RosterOverviewCard(lobby = current, approvedCount = approved.size)

                    SectionCard(
                        title = L10n.string("Participants", "Участники"),
                        subtitle = L10n.string(
                            "Confirmed players are on the roster; pending players haven't been accepted yet.",
                            "Подтвержденные игроки уже в составе, ожидающие пока не приняты.",
                        ),
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            approved.forEach { response ->
                                ParticipantRow(
                                    response = response,
                                    title = L10n.string("On roster", "В составе"),
                                    tint = AppTheme.court,
                                )
                            }
                            pending.forEach { response ->
                                ParticipantRow(
                                    response = response,
                                    title = L10n.string("Awaiting response", "Ожидаем ответ"),
                                    tint = Color(0xFFFFB34D),
                                )
                            }
                            if (approved.isEmpty() && pending.isEmpty()) {
                                Text(
                                    L10n.string("Nobody has responded yet.", "Откликов пока нет."),
                                    style = AppText.footnote,
                                    color = AppTheme.ink.copy(alpha = 0.58f),
                                )
                            }
                        }
                    }

                    if (canProposeSlots) {
                        SlotProposalSection(
                            lobby = current,
                            selectedCourtName = selectedCourtName,
                            selectedDateKeys = selectedSlotDateKeys,
                            selectedTimes = selectedSlotTimes,
                            selectedRange = selectedSlotTimeRange,
                            comment = slotComment,
                            isScheduling = isScheduling,
                            onToggleDate = { key ->
                                selectedSlotDateKeys = if (selectedSlotDateKeys.contains(key) && selectedSlotDateKeys.size > 1) {
                                    selectedSlotDateKeys - key
                                } else {
                                    selectedSlotDateKeys + key
                                }
                            },
                            onSelectRange = { selectedSlotTimeRange = it },
                            onToggleTime = { time ->
                                selectedSlotTimes = if (selectedSlotTimes.contains(time)) {
                                    selectedSlotTimes - time
                                } else {
                                    selectedSlotTimes + time
                                }
                            },
                            onCommentChange = { slotComment = it },
                            onOpenCourtPicker = { isCourtPickerOpen = true },
                            onSubmit = {
                                val dates = resolveSlotDates(current, selectedSlotDateKeys)
                                val options = dates.flatMap { date ->
                                    selectedSlotTimes.sorted().map { time ->
                                        SearchSlotProposalDraftOption(
                                            scheduledAt = scheduledInstant(date, time),
                                            proposedCourtId = proposedCourtId.takeIf { it.isNotEmpty() },
                                            durationMinutes = current.durationMinutes ?: 90,
                                        )
                                    }
                                }
                                if (options.isEmpty()) return@SlotProposalSection

                                isScheduling = true
                                scope.launch {
                                    runCatching {
                                        appModel.repository.createSearchSlotProposal(
                                            searchId = searchId,
                                            options = options,
                                            comment = slotComment.trim().takeIf { it.isNotEmpty() },
                                        )
                                    }.onFailure { if (!it.isCancellationLike) appModel.present(it) }
                                    slotComment = ""
                                    isScheduling = false
                                    reloadTick++
                                }
                            },
                        )
                    } else if (canVoteForSlots) {
                        val activeProposal = requireNotNull(current.activeSlotProposal)
                        SlotVotingSection(
                            proposal = activeProposal,
                            fallbackCourtName = selectedCourtName,
                            selectedIds = selectedVoteOptionIDs,
                            isVoting = isVoting,
                            onToggle = { id ->
                                selectedVoteOptionIDs = if (selectedVoteOptionIDs.contains(id)) {
                                    selectedVoteOptionIDs - id
                                } else {
                                    selectedVoteOptionIDs + id
                                }
                            },
                            onSubmit = {
                                isVoting = true
                                scope.launch {
                                    runCatching {
                                        appModel.repository.voteSearchSlotProposal(
                                            searchId = searchId,
                                            proposalId = activeProposal.id,
                                            optionIds = selectedVoteOptionIDs.toList(),
                                        )
                                    }.onFailure { if (!it.isCancellationLike) appModel.present(it) }
                                    isVoting = false
                                    reloadTick++
                                }
                            },
                        )
                    }

                    SectionCard(
                        title = L10n.string("Group chat", "Общий чат"),
                        subtitle = L10n.string(
                            "Use this chat to agree on the roster, district, and expectations before the final game.",
                            "Здесь удобно договориться по составу, району и ожиданиям до финальной игры.",
                        ),
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            if (current.messages.isEmpty()) {
                                Text(
                                    L10n.string("No messages yet.", "Сообщений пока нет."),
                                    style = AppText.footnote,
                                    color = AppTheme.ink.copy(alpha = 0.58f),
                                )
                            }
                            current.messages.forEach { message ->
                                LobbyBubble(
                                    modifier = Modifier.chatReceiptRow(receiptTracker, message.id),
                                    message = message,
                                    isMine = message.senderUserId == appModel.currentUser?.id,
                                    repository = appModel.repository,
                                    onOpenAttachment = { viewerPath = it.url },
                                )
                            }
                        }

                        LobbyComposer(
                            value = messageText,
                            isSending = isSendingMessage,
                            pendingPhotos = pendingPhotos,
                            onValueChange = { messageText = it },
                            onPickPhotos = { pendingPhotos = it },
                            onRemovePhoto = { photo -> pendingPhotos = pendingPhotos - photo },
                            onSend = {
                                val trimmed = messageText.trim()
                                val photos = pendingPhotos
                                if (trimmed.isEmpty() && photos.isEmpty()) return@LobbyComposer
                                isSendingMessage = true
                                haptics.selection()
                                messageText = ""
                                pendingPhotos = emptyList()
                                scope.launch {
                                    runCatching {
                                        val attachmentIds = photos.map { photo ->
                                            appModel.repository
                                                .uploadChatMedia(photo.bytes, photo.fileName, photo.mimeType).id
                                        }
                                        appModel.repository
                                            .sendSearchLobbyMessage(searchId, trimmed, attachmentIds)
                                    }.onSuccess { sent ->
                                        lobby = current.copy(messages = current.messages + sent)
                                    }.onFailure {
                                        if (!it.isCancellationLike) appModel.present(it)
                                    }
                                    isSendingMessage = false
                                }
                            },
                        )
                    }
                }

                lobbyLoadError != null -> SectionCard(
                    title = L10n.string("Roster and group chat", "Состав и общий чат"),
                    subtitle = L10n.string("Could not load search details.", "Не удалось загрузить детали поиска."),
                ) {
                    Text(lobbyLoadError.orEmpty(), style = AppText.footnote, color = AppTheme.ink.copy(alpha = 0.68f))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(46.dp)
                            .clip(continuousShape(16.dp))
                            .background(AppTheme.ink)
                            .clickable { reloadTick++ },
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(
                            L10n.string("Try again", "Повторить"),
                            style = AppText.subheadlineSemibold,
                            color = Color.White,
                        )
                    }
                }

                else -> SectionCard(
                    title = L10n.string("Roster and group chat", "Состав и общий чат"),
                    subtitle = L10n.string("Loading search details.", "Загружаем детали поиска."),
                ) {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = AppTheme.court, strokeWidth = 3.dp)
                    }
                }
            }
        }
    }
}

// MARK: - Roster overview

@Composable
private fun RosterOverviewCard(lobby: SearchLobbyGameSearch, approvedCount: Int) {
    SectionCard(
        title = L10n.string("Roster and group chat", "Состав и общий чат"),
        subtitle = L10n.string(
            "This is the shared space for this search. The roster and discussion are visible here before the final game.",
            "Это общее пространство по этому поиску. Здесь видно состав и обсуждение до финальной игры.",
        ),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AppInlineChip(
                text = L10n.string(
                    "$approvedCount of ${maxOf(lobby.playersNeeded, 1)} confirmed",
                    "$approvedCount из ${maxOf(lobby.playersNeeded, 1)} подтверждено",
                ),
                tint = AppTheme.mint,
                foreground = AppTheme.court,
            )
            AppInlineChip(
                text = lobby.sport.formatTitle(lobby.format, lobby.playersNeeded),
                tint = AppTheme.cream,
                foreground = AppTheme.ink,
            )
        }

        lobby.comment?.trim()?.takeIf { it.isNotEmpty() }?.let { comment ->
            Text(comment, style = AppText.footnote, color = AppTheme.ink.copy(alpha = 0.72f))
        }
    }
}

/** Port of `lobbyParticipantRow`. */
@Composable
private fun ParticipantRow(response: SearchResponse, title: String, tint: Color) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.72f))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RemoteAvatarView(
            name = response.responderUser.displayName,
            path = response.responderUser.avatarUrl,
            size = 40.dp,
        )

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                response.responderUser.displayName,
                style = AppText.subheadlineSemibold,
                color = AppTheme.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(title, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.58f))
        }

        AppInlineChip(text = title, tint = tint.copy(alpha = 0.14f), foreground = tint)
    }
}

/** Port of `searchLobbyBubble`. */
@Composable
private fun LobbyBubble(
    modifier: Modifier = Modifier,
    message: SearchLobbyMessage,
    isMine: Boolean,
    repository: shop.sportsearch.app.data.TennisRepository,
    onOpenAttachment: (ChatMediaAttachment) -> Unit,
) {
    val shape = continuousShape(24.dp)

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        if (isMine) {
            Spacer(Modifier.width(48.dp))
        } else {
            RemoteAvatarView(
                name = message.senderUser?.name ?: L10n.string("Player", "Игрок"),
                path = message.senderUser?.avatarUrl,
                size = 34.dp,
            )
        }

        Column(
            modifier = Modifier
                .weight(1f, fill = false)
                .clip(shape)
                .background(
                    if (isMine) {
                        Brush.linearGradient(listOf(AppTheme.court, AppTheme.ink))
                    } else {
                        Brush.verticalGradient(
                            listOf(Color.White.copy(alpha = 0.94f), AppTheme.creamLight.copy(alpha = 0.96f)),
                        )
                    },
                )
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (!isMine) {
                Text(
                    message.senderUser?.name ?: L10n.string("Player", "Игрок"),
                    style = AppText.captionSemibold,
                    color = AppTheme.ink.copy(alpha = 0.58f),
                )
            }
            ChatAttachmentsGrid(
                repository = repository,
                attachments = message.attachments,
                onOpen = onOpenAttachment,
            )

            if (message.text.isNotEmpty()) {
                Text(message.text, style = AppText.body, color = if (isMine) Color.White else AppTheme.ink)
            }
            if (isMine) ChatReceiptLabel(message.receipt, group = true)
            Text(
                message.createdAt.formattedDateTime(),
                style = AppText.caption2,
                color = if (isMine) Color.White.copy(alpha = 0.72f) else AppTheme.ink.copy(alpha = 0.42f),
            )
        }

        if (!isMine) Spacer(Modifier.width(48.dp))
    }
}

@Composable
private fun LobbyComposer(
    value: String,
    isSending: Boolean,
    pendingPhotos: List<PendingChatPhoto>,
    onValueChange: (String) -> Unit,
    onPickPhotos: (List<PendingChatPhoto>) -> Unit,
    onRemovePhoto: (PendingChatPhoto) -> Unit,
    onSend: () -> Unit,
) {
    val pickPhotos = rememberChatPhotoPicker(onPicked = onPickPhotos)

    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
    PendingPhotosRail(photos = pendingPhotos, onRemove = onRemovePhoto)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(
            modifier = Modifier
                .size(width = 40.dp, height = 50.dp)
                .clickable(enabled = !isSending, onClick = pickPhotos),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.PhotoLibrary,
                contentDescription = L10n.string("Add photo", "Добавить фото"),
                tint = AppTheme.court,
                modifier = Modifier.size(20.dp),
            )
        }

        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = {
                Text(
                    L10n.string("Message the roster…", "Сообщение для состава..."),
                    color = AppTheme.ink.copy(alpha = 0.4f),
                )
            },
            maxLines = 4,
            shape = continuousShape(22.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = AppTheme.creamLight,
                unfocusedContainerColor = AppTheme.creamLight,
                focusedTextColor = AppTheme.ink,
                unfocusedTextColor = AppTheme.ink,
                cursorColor = AppTheme.court,
                focusedIndicatorColor = AppTheme.court.copy(alpha = 0.4f),
                unfocusedIndicatorColor = AppTheme.court.copy(alpha = 0.16f),
            ),
            modifier = Modifier.weight(1f),
        )

        val enabled = !isSending && (value.isNotBlank() || pendingPhotos.isNotEmpty())
        Box(
            modifier = Modifier
                .size(50.dp)
                .clip(continuousShape(18.dp))
                .background(if (enabled) AppTheme.ink else AppTheme.ink.copy(alpha = 0.3f))
                .clickable(enabled = enabled, onClick = onSend),
            contentAlignment = Alignment.Center,
        ) {
            if (isSending) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            } else {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    contentDescription = L10n.string("Send", "Отправить"),
                    tint = Color.White,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
    }
}

// MARK: - Recurring slots

/** Port of `slotProposalSection`: the creator picks repeating days and times. */
@Composable
private fun SlotProposalSection(
    lobby: SearchLobbyGameSearch,
    selectedCourtName: String,
    selectedDateKeys: Set<String>,
    selectedTimes: Set<String>,
    selectedRange: TimeRange,
    comment: String,
    isScheduling: Boolean,
    onToggleDate: (String) -> Unit,
    onSelectRange: (TimeRange) -> Unit,
    onToggleTime: (String) -> Unit,
    onCommentChange: (String) -> Unit,
    onOpenCourtPicker: () -> Unit,
    onSubmit: () -> Unit,
) {
    val cardShape = continuousShape(28.dp)
    val dates = slotDateOptions(lobby)
    val effectiveDateKeys = selectedDateKeys.ifEmpty { setOfNotNull(dates.firstOrNull()?.let(::dateKey)) }
    val slotCount = effectiveDateKeys.size * selectedTimes.size

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(cardShape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), cardShape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                L10n.string("Recurring schedule", "Регулярное расписание"),
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
                textAlign = TextAlign.Center,
            )
            Text(
                L10n.string(
                    "Choose days and times that repeat every week",
                    "Выберите дни и время, которые будут повторяться каждую неделю",
                ),
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.56f),
                textAlign = TextAlign.Center,
            )
        }

        // slotSummaryCard
        val summaryShape = continuousShape(22.dp)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(summaryShape)
                .background(Color.White)
                .border(1.dp, Color.Black.copy(alpha = 0.06f), summaryShape)
                .padding(15.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier.size(36.dp).clip(CircleShape).background(AppTheme.mint),
                    contentAlignment = Alignment.Center,
                ) {
                    SportIconView(sport = lobby.sport, color = AppTheme.court, size = 18.dp)
                }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        "${lobby.sport.title} · ${lobby.sport.formatTitle(lobby.format, lobby.playersNeeded)}",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = AppTheme.ink.copy(alpha = 0.78f),
                    )
                    Text(
                        slotHeadline(lobby),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppTheme.ink,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                DetailPill(Icons.Filled.Group, lobby.preferredDistrictsLabel)
                DetailPill(Icons.Filled.Apartment, selectedCourtName)
            }
        }

        // dateOptionsRail
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            dates.forEach { date ->
                val key = dateKey(date)
                val selected = effectiveDateKeys.contains(key)
                val shape = continuousShape(20.dp)
                Column(
                    modifier = Modifier
                        .size(width = 72.dp, height = 82.dp)
                        .clip(shape)
                        .background(if (selected) AppTheme.court else Color.White)
                        .border(1.dp, if (selected) AppTheme.court else Color.Black.copy(alpha = 0.08f), shape)
                        .clickable { onToggleDate(key) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        dayShortTitle(date),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (selected) Color.White else AppTheme.ink,
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        date.dayOfMonth.toString(),
                        fontSize = 26.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (selected) Color.White else AppTheme.ink,
                    )
                }
            }
        }

        // timeOptionsCard
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    selectedRange.title,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                    modifier = Modifier.weight(1f),
                )
                Box(
                    modifier = Modifier.size(28.dp).clip(CircleShape).background(AppTheme.court),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        slotCount.toString(),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                TimeRange.entries.forEach { range ->
                    val selected = range == selectedRange
                    val shape = continuousShape(16.dp)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(44.dp)
                            .clip(shape)
                            .background(if (selected) AppTheme.mint else Color.Black.copy(alpha = 0.04f))
                            .border(
                                1.dp,
                                if (selected) AppTheme.court.copy(alpha = 0.3f) else Color.Transparent,
                                shape,
                            )
                            .clickable { onSelectRange(range) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            range.title,
                            style = AppText.subheadlineSemibold,
                            color = if (selected) AppTheme.court else AppTheme.ink.copy(alpha = 0.72f),
                        )
                    }
                }
            }

            // 3-column grid of half-hour options
            slotTimeOptions(selectedRange).chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                    row.forEach { time ->
                        val selected = selectedTimes.contains(time)
                        val shape = continuousShape(16.dp)
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(48.dp)
                                .clip(shape)
                                .background(if (selected) AppTheme.court else Color.White)
                                .border(
                                    1.dp,
                                    if (selected) AppTheme.court else Color.Black.copy(alpha = 0.07f),
                                    shape,
                                )
                                .clickable { onToggleTime(time) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                time,
                                style = AppText.subheadlineSemibold,
                                color = if (selected) Color.White else AppTheme.ink,
                            )
                        }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }

            Text(
                L10n.string(
                    "You can choose multiple days and times",
                    "Можно выбрать несколько дней и несколько времен",
                ),
                style = AppText.footnote,
                color = AppTheme.ink.copy(alpha = 0.48f),
            )
        }

        // clubSelectionCard
        val clubShape = continuousShape(18.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(clubShape)
                .background(Color.White)
                .border(1.dp, Color.Black.copy(alpha = 0.08f), clubShape)
                .clickable(onClick = onOpenCourtPicker)
                .padding(horizontal = 14.dp, vertical = 13.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    L10n.string("Club", "Клуб"),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppTheme.ink.copy(alpha = 0.52f),
                )
                Text(
                    selectedCourtName,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppTheme.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                L10n.string("Choose", "Выбрать"),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppTheme.ink.copy(alpha = 0.88f),
                modifier = Modifier
                    .clip(RoundedCornerShape(percent = 50))
                    .background(Color.Black.copy(alpha = 0.04f))
                    .padding(horizontal = 14.dp, vertical = 9.dp),
            )
        }

        // slotCommentCard
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                L10n.string("Comment (optional)", "Комментарий (необязательно)"),
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppTheme.ink,
            )
            OutlinedTextField(
                value = comment,
                onValueChange = onCommentChange,
                placeholder = {
                    Text(
                        L10n.string("Anything the roster should know", "Что важно знать составу"),
                        color = AppTheme.ink.copy(alpha = 0.38f),
                    )
                },
                minLines = 2,
                maxLines = 4,
                textStyle = AppText.subheadline,
                shape = continuousShape(18.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = AppTheme.creamLight,
                    unfocusedContainerColor = AppTheme.creamLight,
                    focusedTextColor = AppTheme.ink,
                    unfocusedTextColor = AppTheme.ink,
                    cursorColor = AppTheme.court,
                    focusedIndicatorColor = AppTheme.court.copy(alpha = 0.4f),
                    unfocusedIndicatorColor = Color.Black.copy(alpha = 0.08f),
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PrimaryActionButton(
                title = L10n.string(
                    "Suggest $slotCount ${if (slotCount == 1) "slot" else "slots"}",
                    "Предложить $slotCount ${slotWord(slotCount)}",
                ),
                onClick = onSubmit,
                tint = AppTheme.ink,
                enabled = !isScheduling && selectedTimes.isNotEmpty() && effectiveDateKeys.isNotEmpty(),
            )
            Text(
                L10n.string(
                    "Selected days and times will repeat every week",
                    "Выбранные дни и время будут повторяться каждую неделю",
                ),
                style = AppText.footnote,
                color = AppTheme.ink.copy(alpha = 0.48f),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/** Port of `slotVotingSection`. */
@Composable
private fun SlotVotingSection(
    proposal: SearchSlotProposalSummary,
    fallbackCourtName: String,
    selectedIds: Set<String>,
    isVoting: Boolean,
    onToggle: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val cardShape = continuousShape(28.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(cardShape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), cardShape)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                L10n.string("Choose recurring time slots", "Выберите регулярные слоты"),
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
            )
            Text(
                L10n.string(
                    "Select the days and times that really work every week",
                    "Отметь дни и время, которые реально подходят каждую неделю",
                ),
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = AppTheme.ink.copy(alpha = 0.56f),
            )
        }

        proposal.comment?.trim()?.takeIf { it.isNotEmpty() }?.let { comment ->
            Text(
                comment,
                style = AppText.footnote,
                color = AppTheme.ink.copy(alpha = 0.62f),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(14.dp))
                    .background(AppTheme.creamLight)
                    .padding(horizontal = 12.dp, vertical = 10.dp),
            )
        }

        proposal.options.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEach { option ->
                    val selected = selectedIds.contains(option.id)
                    val shape = continuousShape(16.dp)
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clip(shape)
                            .background(if (selected) AppTheme.mint.copy(alpha = 0.6f) else Color.White)
                            .border(
                                1.dp,
                                if (selected) AppTheme.court else Color.Black.copy(alpha = 0.07f),
                                shape,
                            )
                            .clickable { onToggle(option.id) }
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        Text(
                            option.scheduledAt.formattedDateTime(),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (selected) AppTheme.court else AppTheme.ink,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            option.proposedCourt?.name ?: fallbackCourtName,
                            style = AppText.caption,
                            color = AppTheme.ink.copy(alpha = 0.54f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Filled.Group,
                                contentDescription = null,
                                tint = AppTheme.court,
                                modifier = Modifier.size(13.dp),
                            )
                            Text(
                                option.voteCount.toString(),
                                style = AppText.captionBold,
                                color = AppTheme.court,
                            )
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }

        PrimaryActionButton(
            title = L10n.string("Submit selection", "Отправить выбор"),
            onClick = onSubmit,
            tint = AppTheme.ink,
            enabled = !isVoting && selectedIds.isNotEmpty(),
        )
    }
}

@Composable
private fun DetailPill(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = AppTheme.ink.copy(alpha = 0.82f), modifier = Modifier.size(12.dp))
        Text(
            text,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = AppTheme.ink.copy(alpha = 0.82f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// MARK: - Slot helpers ported from SearchLobbySheet

/** `timeOptions(for:)`. */
private fun slotTimeOptions(range: TimeRange): List<String> = when (range) {
    TimeRange.MORNING -> listOf("08:00", "08:30", "09:00", "09:30", "10:00", "10:30")
    TimeRange.DAY -> listOf("12:00", "12:30", "13:00", "13:30", "14:00", "14:30", "15:00", "15:30", "16:00", "16:30", "17:00")
    TimeRange.EVENING -> listOf("18:00", "18:30", "19:00", "19:30", "20:00", "20:30", "21:00", "21:30", "22:00")
}

/**
 * `dateOptions`: the next 14 days, keeping only the weekdays the search prefers
 * and only the first occurrence of each weekday.
 */
private fun slotDateOptions(lobby: SearchLobbyGameSearch): List<LocalDate> {
    val preferred = lobby.preferredDays.mapNotNull(DayOfWeek::from).toSet()
    val seen = mutableSetOf<DayOfWeek>()
    val today = LocalDate.now()
    val result = mutableListOf<LocalDate>()

    for (offset in 0 until 14) {
        val date = today.plusDays(offset.toLong())
        val weekday = weekdayOf(date)
        if ((preferred.isEmpty() || preferred.contains(weekday)) && seen.add(weekday)) {
            result.add(date)
        }
    }
    return result.ifEmpty { listOf(today) }
}

private fun weekdayOf(date: LocalDate): DayOfWeek = when (date.dayOfWeek) {
    java.time.DayOfWeek.MONDAY -> DayOfWeek.MONDAY
    java.time.DayOfWeek.TUESDAY -> DayOfWeek.TUESDAY
    java.time.DayOfWeek.WEDNESDAY -> DayOfWeek.WEDNESDAY
    java.time.DayOfWeek.THURSDAY -> DayOfWeek.THURSDAY
    java.time.DayOfWeek.FRIDAY -> DayOfWeek.FRIDAY
    java.time.DayOfWeek.SATURDAY -> DayOfWeek.SATURDAY
    java.time.DayOfWeek.SUNDAY -> DayOfWeek.SUNDAY
}

/** `dateKey(for:)` - "yyyy-M-d". */
private fun dateKey(date: LocalDate): String = "${date.year}-${date.monthValue}-${date.dayOfMonth}"

private fun dayShortTitle(date: LocalDate): String = weekdayOf(date).shortTitle

private fun resolveSlotDates(lobby: SearchLobbyGameSearch, keys: Set<String>): List<LocalDate> {
    val options = slotDateOptions(lobby)
    val selected = options.filter { keys.contains(dateKey(it)) }
    return selected.ifEmpty { options.take(1) }
}

private fun scheduledInstant(date: LocalDate, time: String): Instant {
    val hour = time.substringBefore(":").toIntOrNull() ?: 19
    val minute = time.substringAfter(":", "0").toIntOrNull() ?: 0
    return date.atTime(LocalTime.of(hour, minute)).atZone(ZoneId.systemDefault()).toInstant()
}

/** `slotHeadline(for:)`. */
private fun slotHeadline(lobby: SearchLobbyGameSearch): String {
    val min = lobby.desiredLevelMin
    val max = lobby.desiredLevelMax
    return if (min != null && max != null) {
        L10n.string(
            "Looking for ${lobby.playersNeeded} player(s), level $min–$max",
            "Ищу ${lobby.playersNeeded} игроков уровня $min–$max",
        )
    } else {
        L10n.string("Looking for ${lobby.playersNeeded} player(s)", "Ищу ${lobby.playersNeeded} игроков")
    }
}

/** `slotWord(_:)` - Russian plural agreement for "слот". */
private fun slotWord(count: Int): String {
    if (count % 10 == 1 && count % 100 != 11) return "слот"
    if (count % 10 in 2..4 && count % 100 !in 12..14) return "слота"
    return "слотов"
}
