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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.*
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import shop.sportsearch.app.ui.theme.statusSurfaceColor
import shop.sportsearch.app.ui.theme.statusTintColor

private data class ChatMessageAction(
    val title: String,
    val icon: ImageVector,
    val target: AppNavigationTarget,
)

private data class ChatMessagePresentation(val text: String, val action: ChatMessageAction?)

private fun extractPathID(text: String, marker: String): String? {
    val index = text.indexOf(marker)
    if (index < 0) return null
    val suffix = text.substring(index + marker.length)
    val raw = suffix.takeWhile { !it.isWhitespace() && it != '.' && it != ',' && it != ')' && it != ']' }
    return raw.trim().ifEmpty { null }
}

private fun cleanActionLinkText(text: String): String {
    var result = text
    for (label in listOf("Открыть игру:", "Открыть поиск:")) {
        val index = result.indexOf(label)
        if (index >= 0) {
            result = result.substring(0, index)
            break
        }
    }
    return result.trim().trim('.', ' ', '\n')
}

private fun chatMessagePresentation(message: ChatMessage): ChatMessagePresentation {
    val openGame = L10n.string("Open game", "Открыть игру")

    message.gameRequestId?.let { id ->
        return ChatMessagePresentation(
            cleanActionLinkText(message.text),
            ChatMessageAction(
                openGame,
                Icons.Filled.CalendarMonth,
                AppNavigationTarget.Discover(DiscoverTab.UPCOMING, highlightedGameRequestID = id),
            ),
        )
    }

    extractPathID(message.text, "/play/games/")?.let { id ->
        return ChatMessagePresentation(
            cleanActionLinkText(message.text),
            ChatMessageAction(
                openGame,
                Icons.Filled.CalendarMonth,
                AppNavigationTarget.Discover(DiscoverTab.UPCOMING, highlightedGameRequestID = id),
            ),
        )
    }

    extractPathID(message.text, "/play/searches/")?.let { id ->
        return ChatMessagePresentation(
            cleanActionLinkText(message.text),
            ChatMessageAction(
                L10n.string("Open search", "Открыть поиск"),
                Icons.Filled.Search,
                AppNavigationTarget.Discover(DiscoverTab.HOT, highlightedSearchID = id),
            ),
        )
    }

    return ChatMessagePresentation(message.text, null)
}

/** Port of `ChatMessage.isGameReportSystemEvent` / `gameReportSystemTitle`. */
private val ChatMessage.isGameReportSystemEvent: Boolean
    get() = text.lowercase().let { it.contains("фотоотчёт") || it.contains("фотоотчет") }

private val ChatMessage.gameReportSystemTitle: String
    get() {
        val normalized = text.lowercase()
        return if (normalized.contains("добав") || normalized.contains("загруж")) {
            L10n.string("Photo report uploaded", "Фотоотчёт загружен")
        } else {
            text
        }
    }

private fun isInactive(request: MatchGameRequest): Boolean =
    request.status.lowercase() in setOf("declined", "rejected", "withdrawn", "canceled", "cancelled") ||
        request.statusLabel == "Игра закончилась"

/** Port of `struct ChatView` in ios/TennisSearchIOS/Views/MatchesView.swift. */
@Composable
fun ChatScreen(
    appModel: AppViewModel,
    match: MatchSummary,
    onBack: () -> Unit,
    onBlocked: () -> Unit = {},
) {
    DismissOnSystemBack(onBack)
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp

    var currentMatch by remember(match.id) { mutableStateOf(match) }
    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var gameRequests by remember { mutableStateOf<List<MatchGameRequest>>(emptyList()) }
    var selectedGameRequestID by remember { mutableStateOf<String?>(null) }
    var draft by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var isUpdatingRequest by remember { mutableStateOf(false) }
    var pendingPhotos by remember { mutableStateOf<List<PendingChatPhoto>>(emptyList()) }
    var viewerPath by remember { mutableStateOf<String?>(null) }
    var avatarPreview by remember { mutableStateOf<Pair<String, String?>?>(null) }
    var selectedGameReport by remember { mutableStateOf<GameReport?>(null) }
    var isProfilePresented by remember { mutableStateOf(false) }
    var proposalContext by remember { mutableStateOf(ProposalSheetContext.NEW) }
    var isProposalPresented by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()
    val currentUserId = appModel.currentUser?.id
    val receiptTracker = rememberChatReceipts(
        repository = appModel.repository,
        matchId = currentMatch.id,
        incomingIds = messages.filter { currentUserId != null && it.senderUserId != currentUserId }.map { it.id },
        conversationVisible = !isProfilePresented && !isProposalPresented && selectedGameReport == null &&
            viewerPath == null && avatarPreview == null,
    )

    val chatGameRequests = remember(gameRequests, currentMatch.latestGameRequest) {
        val byId = linkedMapOf<String, MatchGameRequest>()
        gameRequests.forEach { byId[it.id] = it }
        currentMatch.latestGameRequest?.let { byId[it.id] = it }
        byId.values.sortedWith(
            compareBy<MatchGameRequest> { isInactive(it) }
                .thenByDescending { it.proposedDate ?: Instant.EPOCH },
        )
    }
    val selectedRequest = chatGameRequests.firstOrNull { it.id == selectedGameRequestID }
        ?: chatGameRequests.firstOrNull()

    suspend fun refreshChatState(showErrors: Boolean = true) {
        runCatching { appModel.repository.fetchMessages(currentMatch.id) }
            .onSuccess { fetched ->
                val previous = messages.associateBy { it.id }
                messages = fetched.map { it.copy(receipt = mergeChatReceipt(previous[it.id]?.receipt, it.receipt)) }
            }
            .onFailure { if (showErrors) appModel.present(it) }

        runCatching { appModel.repository.fetchMatches() }
            .onSuccess { fresh -> fresh.firstOrNull { it.id == currentMatch.id }?.let { currentMatch = it } }
            .onFailure { if (showErrors) appModel.present(it) }

        runCatching { appModel.repository.fetchMyGameRequests() }
            .onSuccess { requests -> gameRequests = requests.filter { it.matchId == currentMatch.id } }
            .onFailure { if (showErrors) appModel.present(it) }
    }

    // `ChatView` sets `bottomBarDisplayMode = .hidden` on appear; the chat and its
    // media viewer own the whole screen.
    DisposableEffect(Unit) {
        appModel.bottomBarDisplayMode = BottomBarDisplayMode.HIDDEN
        onDispose {
            appModel.bottomBarDisplayMode = BottomBarDisplayMode.EXPANDED
            scope.launch { runCatching { appModel.repository.setActiveChat(match.id, null, false) } }
        }
    }

    LaunchedEffect(currentMatch.id) {
        runCatching { appModel.repository.markInboxSeen() }
        runCatching { appModel.repository.setActiveChat(currentMatch.id, null, true) }
        refreshChatState()
    }

    // `runRealtimeChatUpdates()` - poll every 2.5 s, refresh presence every 30 s.
    LaunchedEffect(currentMatch.id) {
        var lastPresenceRefresh = Instant.now()
        while (true) {
            delay(2500)
            if (java.time.Duration.between(lastPresenceRefresh, Instant.now()).seconds > 30) {
                runCatching { appModel.repository.setActiveChat(currentMatch.id, null, true) }
                lastPresenceRefresh = Instant.now()
            }
            refreshChatState(showErrors = false)
        }
    }

    LaunchedEffect(chatGameRequests) {
        val available = chatGameRequests.map { it.id }.toSet()
        if (selectedGameRequestID == null || selectedGameRequestID !in available) {
            selectedGameRequestID = chatGameRequests.firstOrNull()?.id
        }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
    }

    // Full-screen destinations.
    if (isProfilePresented) {
        HideBottomBarWhileVisible(appModel)
        MatchPlayerSheet(
            appModel = appModel,
            match = currentMatch,
            onDismiss = { isProfilePresented = false },
            onOpenChat = { isProfilePresented = false },
            onProposeGame = {
                isProfilePresented = false
                proposalContext = ProposalSheetContext.NEW
                isProposalPresented = true
            },
            onBlocked = {
                isProfilePresented = false
                onBack()
            },
        )
        return
    }

    if (isProposalPresented) {
        GameProposalSheet(
            appModel = appModel,
            match = currentMatch,
            context = proposalContext,
            seedRequest = selectedRequest,
            onDismiss = { isProposalPresented = false },
            onCreated = {
                refreshChatState()
                isProposalPresented = false
            },
        )
        return
    }

    selectedGameReport?.let { report ->
        HideBottomBarWhileVisible(appModel)
        GameReportViewerSheet(
            repository = appModel.repository,
            report = report,
            onDismiss = { selectedGameReport = null },
        )
        return
    }

    fun openProposal(context: ProposalSheetContext) {
        haptics.selection()
        proposalContext = context
        isProposalPresented = true
    }

    fun updateRequest(request: MatchGameRequest, status: String) {
        scope.launch {
            isUpdatingRequest = true
            runCatching { appModel.repository.updateGameRequestStatus(request.id, status) }
                .onSuccess {
                    if (status == "accepted") haptics.success() else haptics.warning()
                    refreshChatState()
                }
                .onFailure(appModel::present)
            isUpdatingRequest = false
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Color.Black).statusBarsPadding()) {
        ChatTopHeader(
            appModel = appModel,
            other = currentMatch.otherUser,
            lastIncomingMessageId = messages.lastOrNull { it.senderUserId == currentMatch.otherUser.id }?.id,
            onBack = onBack,
            onOpenAvatar = {
                haptics.selection()
                avatarPreview = currentMatch.otherUser.displayName to currentMatch.otherUser.avatarUrl
            },
            onOpenProfile = {
                haptics.selection()
                isProfilePresented = true
            },
            onBlocked = {
                onBlocked()
                onBack()
            },
        )

        Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))

        // `chatAgreementHeaderSection`
        Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            if (chatGameRequests.isNotEmpty()) {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()).padding(2.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    chatGameRequests.forEach { request ->
                        CompactGameRequestCard(
                            request = request,
                            isSelected = selectedRequest?.id == request.id,
                            maxWidth = minOf(screenWidth - 48.dp, 360.dp),
                            onClick = {
                                selectedGameRequestID = request.id
                                haptics.selection()
                            },
                        )
                    }
                }
            } else {
                ProposalPromptCard(
                    maxWidth = minOf(screenWidth - 48.dp, 280.dp),
                    onClick = { openProposal(ProposalSheetContext.NEW) },
                )
            }
        }

        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(messages.size, key = { messages[it].id }) { index ->
                val message = messages[index]
                val isMine = message.senderUserId == currentUserId

                if (message.isGameReportSystemEvent) {
                    val report = message.gameRequestId
                        ?.let { id -> gameRequests.firstOrNull { it.id == id }?.report }
                        ?: gameRequests.mapNotNull { it.report }.maxByOrNull { it.createdAt }

                    ChatSystemEventRow(
                        modifier = Modifier.chatReceiptRow(receiptTracker, message.id),
                        title = message.gameReportSystemTitle,
                        timestamp = message.createdAt.formattedDateTime(),
                        onTap = report?.let { { selectedGameReport = it } },
                    )
                } else {
                    val presentation = chatMessagePresentation(message)
                    ChatBubble(
                        modifier = Modifier.chatReceiptRow(receiptTracker, message.id),
                        receipt = message.receipt,
                        repository = appModel.repository,
                        text = presentation.text,
                        attachments = message.attachments,
                        timestamp = message.createdAt.formattedDateTime(),
                        sender = message.senderUser?.name ?: currentMatch.otherUser.displayName,
                        avatarPath = if (isMine) {
                            null
                        } else {
                            message.senderUser?.avatarUrl ?: currentMatch.otherUser.avatarUrl
                        },
                        isMine = isMine,
                        action = presentation.action,
                        onAction = { presentation.action?.let { appModel.navigate(it.target) } },
                        onAvatarTap = if (isMine) {
                            null
                        } else {
                            {
                                avatarPreview = (message.senderUser?.name ?: currentMatch.otherUser.displayName) to
                                    (message.senderUser?.avatarUrl ?: currentMatch.otherUser.avatarUrl)
                            }
                        },
                        onAttachmentTap = { viewerPath = it.url },
                    )
                }
            }
        }

        selectedRequest?.let { request ->
            Box(Modifier.padding(horizontal = 16.dp).fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))

            ChatActionsBar(
                request = request,
                currentUserId = currentUserId,
                isUpdating = isUpdatingRequest,
                onNewGame = { openProposal(ProposalSheetContext.NEW) },
                onConfirm = { updateRequest(request, "accepted") },
                onDecline = { updateRequest(request, "declined") },
                onReschedule = { openProposal(ProposalSheetContext.RESCHEDULE) },
                onEdit = { openProposal(ProposalSheetContext.EDIT) },
                onCancel = { updateRequest(request, "canceled") },
            )

            Box(Modifier.padding(horizontal = 16.dp).fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))
        }

        if (pendingPhotos.isNotEmpty()) {
            PendingPhotosRail(
                photos = pendingPhotos,
                onRemove = { photo -> pendingPhotos = pendingPhotos.filterNot { it.id == photo.id } },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                thumbnailSize = 74.dp,
            )
        }

        ChatComposer(
            value = draft,
            onValueChange = { draft = it },
            isSending = isSending,
            canSend = draft.isNotBlank() || pendingPhotos.isNotEmpty(),
            onPickPhotos = rememberChatPhotoPicker { picked ->
                pendingPhotos = (pendingPhotos + picked).take(4)
            },
            onSend = {
                if (isSending) return@ChatComposer
                val trimmed = draft.trim()
                val photos = pendingPhotos
                if (trimmed.isEmpty() && photos.isEmpty()) return@ChatComposer

                scope.launch {
                    isSending = true
                    runCatching {
                        val attachmentIds = photos.map {
                            appModel.repository.uploadChatMedia(it.bytes, it.fileName, it.mimeType).id
                        }
                        appModel.repository.sendMessage(currentMatch.id, trimmed, attachmentIds)
                    }.onSuccess { message ->
                        if (messages.none { it.id == message.id }) messages = messages + message
                        draft = ""
                        pendingPhotos = emptyList()
                        haptics.selection()
                    }.onFailure(appModel::present)
                    isSending = false
                }
            },
        )
    }

    viewerPath?.let { path ->
        ChatMediaViewer(
            repository = appModel.repository,
            path = path,
            onDismiss = { viewerPath = null },
        )
    }

    avatarPreview?.let { (name, path) ->
        AvatarPreviewSheet(name = name, path = path, onDismiss = { avatarPreview = null })
    }
}

@Composable
private fun ChatTopHeader(
    appModel: AppViewModel,
    other: DiscoverUser,
    lastIncomingMessageId: String?,
    onBack: () -> Unit,
    onOpenAvatar: () -> Unit,
    onOpenProfile: () -> Unit,
    onBlocked: () -> Unit,
) {
    val primarySport = other.preferredSports.firstOrNull() ?: Sport.TENNIS

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(top = 6.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.width(32.dp).height(44.dp).clickable(onClick = onBack),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = Color.White, modifier = Modifier.size(24.dp))
        }

        Box(modifier = Modifier.clickable(onClick = onOpenAvatar)) {
            RemoteAvatarView(name = other.displayName, path = other.avatarUrl, size = 48.dp)
            if (other.isOnline) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .size(11.dp)
                        .clip(CircleShape)
                        .background(Color(red = 0.22f, green = 0.82f, blue = 0.45f))
                        .border(2.dp, Color.Black, CircleShape),
                )
            }
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    other.displayName,
                    fontSize = 21.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Box(
                    modifier = Modifier
                        .height(24.dp)
                        .clip(continuousShape(8.dp))
                        .background(
                            if (other.isOnline) {
                                Color(red = 0.05f, green = 0.25f, blue = 0.16f)
                            } else {
                                Color.White.copy(alpha = 0.08f)
                            },
                        )
                        .padding(horizontal = 7.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        other.presenceLabel,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (other.isOnline) {
                            Color(red = 0.38f, green = 0.93f, blue = 0.62f)
                        } else {
                            Color.White.copy(alpha = 0.62f)
                        },
                        maxLines = 1,
                    )
                }
            }

            Text(
                L10n.string(
                    "Looking for a ${primarySport.localizedPurposeTitle} partner",
                    "Ищет партнера для ${primarySport.purposeTitle}",
                ),
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.78f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Column(
            modifier = Modifier.clickable(onClick = onOpenProfile),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Box(
                modifier = Modifier.size(36.dp).clip(CircleShape).border(1.dp, Color.White.copy(alpha = 0.16f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Person, null, tint = Color.White.copy(alpha = 0.82f), modifier = Modifier.size(17.dp))
            }
            Text(
                L10n.string("Profile", "Профиль"),
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.82f),
            )
        }

        UserSafetyMenuButton(
            appModel = appModel,
            userId = other.id,
            displayName = other.displayName,
            context = UserSafetyContext.chat(lastIncomingMessageId),
            onBlocked = onBlocked,
        )
    }
}

@Composable
private fun CompactGameRequestCard(
    request: MatchGameRequest,
    isSelected: Boolean,
    maxWidth: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
) {
    val shape = continuousShape(24.dp)
    val summary = listOf(
        request.sport.title,
        request.proposedDate?.formattedWeekdayDayMonth() ?: request.proposedDatetime,
        request.proposedDate?.formattedHourMinute() ?: request.proposedDatetime,
        request.proposedCourt?.name ?: request.sport.venueUnspecifiedTitle,
    ).filter { it.isNotEmpty() }.joinToString(" · ")

    Row(
        modifier = Modifier
            .width(maxWidth)
            .height(62.dp)
            .appShadow(
                if (isSelected) AppTheme.court.copy(alpha = 0.16f) else Color.Transparent,
                radius = 14.dp,
                offsetY = 8.dp,
                shape = shape,
            )
            .clip(shape)
            .background(
                Brush.horizontalGradient(
                    if (isSelected) {
                        listOf(
                            Color(red = 0.06f, green = 0.21f, blue = 0.14f),
                            Color(red = 0.04f, green = 0.12f, blue = 0.09f),
                        )
                    } else {
                        listOf(Color.White.copy(alpha = 0.07f), Color.White.copy(alpha = 0.035f))
                    },
                ),
            )
            .border(
                if (isSelected) 1.4.dp else 1.dp,
                if (isSelected) AppTheme.court.copy(alpha = 0.72f) else Color.White.copy(alpha = 0.10f),
                shape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .clip(continuousShape(11.dp))
                .background(
                    Brush.linearGradient(
                        listOf(AppTheme.court.copy(alpha = 0.74f), AppTheme.court.copy(alpha = 0.32f)),
                    ),
                ),
            contentAlignment = Alignment.Center,
        ) {
            SportIconView(sport = request.sport, color = Color.White, size = 18.dp)
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                summary,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                request.statusLabel.localizedMatchesText,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = request.statusTintColor,
                maxLines = 1,
            )
        }

        if (isSelected) {
            Icon(Icons.Filled.CheckCircle, null, tint = AppTheme.court, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
private fun ProposalPromptCard(maxWidth: androidx.compose.ui.unit.Dp, onClick: () -> Unit) {
    val shape = continuousShape(22.dp)
    Row(
        modifier = Modifier
            .width(maxWidth)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.035f))
            .border(1.2.dp, AppTheme.court.copy(alpha = 0.82f), shape)
            .clickable(onClick = onClick)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(58.dp)
                .clip(continuousShape(14.dp))
                .background(
                    Brush.linearGradient(
                        listOf(AppTheme.court.copy(alpha = 0.42f), AppTheme.court.copy(alpha = 0.16f)),
                    ),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.EditCalendar,
                null,
                tint = Color(red = 0.50f, green = 0.95f, blue = 0.72f),
                modifier = Modifier.size(24.dp),
            )
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                L10n.string("Propose a game", "Предложить игру"),
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
            Text(
                L10n.string(
                    "Choose a date, time, and venue, then send your proposal.",
                    "Выберите дату, время, корт и отправьте предложение",
                ),
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.58f),
                maxLines = 3,
            )
        }

        Icon(
            Icons.Filled.ChevronRight,
            null,
            tint = Color(red = 0.36f, green = 0.92f, blue = 0.62f),
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun ChatActionsBar(
    request: MatchGameRequest,
    currentUserId: String?,
    isUpdating: Boolean,
    onNewGame: () -> Unit,
    onConfirm: () -> Unit,
    onDecline: () -> Unit,
    onReschedule: () -> Unit,
    onEdit: () -> Unit,
    onCancel: () -> Unit,
) {
    val declineTint = Color(red = 0.25f, green = 0.10f, blue = 0.10f)
    val declineForeground = Color(red = 1.0f, green = 0.47f, blue = 0.43f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CheckCircle, null, tint = AppTheme.court, modifier = Modifier.size(13.dp))
            val day = request.proposedDate?.formattedWeekdayDayMonthLong() ?: request.proposedDatetime.formattedDateTime()
            val time = request.proposedDate?.formattedHourMinute() ?: ""
            Text(
                L10n.string("Selected: $day, $time", "Выбрана: $day, $time"),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.58f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ChatQuickActionButton(
                L10n.string("New game", "Новая игра"),
                Icons.Filled.EditCalendar,
                AppTheme.court,
                Color.White,
                onClick = onNewGame,
            )

            if (request.isPendingForRecipient(currentUserId)) {
                ChatQuickActionButton(
                    L10n.string("Confirm", "Подтвердить"),
                    Icons.Filled.CheckCircle,
                    AppTheme.court,
                    Color.White,
                    isUpdating = isUpdating,
                    onClick = onConfirm,
                )
                ChatQuickActionButton(
                    L10n.string("Decline", "Отклонить"),
                    Icons.Filled.Close,
                    declineTint,
                    declineForeground,
                    isUpdating = isUpdating,
                    onClick = onDecline,
                )
            } else if (!isInactive(request)) {
                ChatQuickActionButton(
                    L10n.string("Suggest a time", "Предложить время"),
                    Icons.Filled.Schedule,
                    Color.White.copy(alpha = 0.06f),
                    Color.White,
                    onClick = onReschedule,
                )
                ChatQuickActionButton(
                    L10n.string("Edit game", "Изменить игру"),
                    Icons.Filled.Tune,
                    Color.White.copy(alpha = 0.06f),
                    Color.White,
                    onClick = onEdit,
                )
                ChatQuickActionButton(
                    L10n.string("Cancel game", "Отмена игры"),
                    Icons.Filled.Close,
                    declineTint,
                    declineForeground,
                    isUpdating = isUpdating,
                    onClick = onCancel,
                )
            }
        }
    }
}

@Composable
private fun ChatQuickActionButton(
    title: String,
    icon: ImageVector,
    tint: Color,
    foreground: Color,
    isUpdating: Boolean = false,
    onClick: () -> Unit,
) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .height(48.dp)
            .clip(shape)
            .background(tint)
            .border(1.dp, Color.White.copy(alpha = 0.12f), shape)
            .clickable(enabled = !isUpdating, onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isUpdating) {
            CircularProgressIndicator(color = foreground, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
        } else {
            Icon(icon, null, tint = foreground, modifier = Modifier.size(18.dp))
        }
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = foreground, maxLines = 1)
    }
}

/** Port of `struct ChatSystemEventRow`. */
@Composable
private fun ChatSystemEventRow(title: String, timestamp: String, onTap: (() -> Unit)?, modifier: Modifier = Modifier) {
    Row(modifier = modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
        Row(
            modifier = Modifier
                .padding(horizontal = 24.dp)
                .clip(CircleShape)
                .background(AppTheme.mint)
                .border(1.dp, AppTheme.court.copy(alpha = if (onTap == null) 0.28f else 0.46f), CircleShape)
                .clickable(enabled = onTap != null) { onTap?.invoke() }
                .padding(horizontal = 13.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.PhotoLibrary, null, tint = AppTheme.court, modifier = Modifier.size(13.dp))

            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = AppText.captionBold, color = AppTheme.ink)
                Text(timestamp, style = AppText.caption2, color = AppTheme.ink.copy(alpha = 0.52f))
            }

            if (onTap != null) {
                Icon(
                    Icons.Filled.ChevronRight,
                    null,
                    tint = AppTheme.court.copy(alpha = 0.8f),
                    modifier = Modifier.size(12.dp),
                )
            }
        }
    }
}

/** Port of `struct ChatBubble`. */
@Composable
private fun ChatBubble(
    modifier: Modifier = Modifier,
    receipt: ChatReceipt? = null,
    repository: shop.sportsearch.app.data.TennisRepository,
    text: String,
    attachments: List<ChatMediaAttachment>,
    timestamp: String,
    sender: String,
    avatarPath: String?,
    isMine: Boolean,
    action: ChatMessageAction?,
    onAction: () -> Unit,
    onAvatarTap: (() -> Unit)?,
    onAttachmentTap: (ChatMediaAttachment) -> Unit,
) {
    val shape = continuousShape(24.dp)

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        if (isMine) {
            Spacer(Modifier.width(48.dp))
        } else {
            RemoteAvatarView(
                name = sender,
                path = avatarPath,
                size = 42.dp,
                modifier = Modifier
                    .border(1.5.dp, AppTheme.court.copy(alpha = 0.72f), CircleShape)
                    .then(if (onAvatarTap != null) Modifier.clickable(onClick = onAvatarTap) else Modifier),
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
                .border(1.dp, Color.White.copy(alpha = if (isMine) 0.12f else 0.82f), shape)
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (attachments.isNotEmpty()) {
                ChatAttachmentsGrid(
                    repository = repository,
                    attachments = attachments,
                    onOpen = onAttachmentTap,
                )
            }

            if (text.isNotEmpty()) {
                Text(text, style = AppText.body, color = if (isMine) Color.White else AppTheme.ink)
            }

            if (action != null) {
                Row(
                    modifier = Modifier
                        .height(36.dp)
                        .clip(CircleShape)
                        .background(if (isMine) Color.White.copy(alpha = 0.92f) else AppTheme.court)
                        .clickable(onClick = onAction)
                        .padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val foreground = if (isMine) Color.Black.copy(alpha = 0.88f) else Color.White
                    Icon(action.icon, null, tint = foreground, modifier = Modifier.size(14.dp))
                    Text(action.title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = foreground)
                }
            }

            if (isMine) ChatReceiptLabel(receipt)
            Text(
                timestamp,
                style = AppText.caption2,
                color = if (isMine) Color.White.copy(alpha = 0.72f) else AppTheme.ink.copy(alpha = 0.42f),
            )
        }

        if (!isMine) Spacer(Modifier.width(48.dp))
    }
}

@Composable
private fun ChatComposer(
    value: String,
    onValueChange: (String) -> Unit,
    isSending: Boolean,
    canSend: Boolean,
    onPickPhotos: () -> Unit,
    onSend: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Black)
            .navigationBarsPadding()
            .imePadding()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(
            modifier = Modifier
                .width(46.dp)
                .height(58.dp)
                .clickable(enabled = !isSending, onClick = onPickPhotos),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.PhotoLibrary, null, tint = AppTheme.court, modifier = Modifier.size(18.dp))
        }

        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.weight(1f),
            placeholder = {
                Text(
                    L10n.string("Write a message...", "Написать сообщение..."),
                    color = Color.White.copy(alpha = 0.38f),
                    style = AppText.subheadline,
                )
            },
            textStyle = AppText.body.copy(color = Color.White),
            maxLines = 4,
            shape = continuousShape(22.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.White.copy(alpha = 0.07f),
                unfocusedContainerColor = Color.White.copy(alpha = 0.07f),
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                cursorColor = AppTheme.court,
            ),
        )

        Box(
            modifier = Modifier
                .size(58.dp)
                .clip(CircleShape)
                .background(AppTheme.court)
                .clickable(enabled = !isSending && canSend, onClick = onSend),
            contentAlignment = Alignment.Center,
        ) {
            if (isSending) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
            } else {
                Icon(Icons.AutoMirrored.Filled.Send, null, tint = Color.White, modifier = Modifier.size(16.dp))
            }
        }
    }
}
