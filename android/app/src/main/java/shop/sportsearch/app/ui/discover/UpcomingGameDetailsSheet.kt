package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.SportsTennis
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.DiscoverUser
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.MatchGameRequest
import shop.sportsearch.app.core.SearchLobbyGameSearch
import shop.sportsearch.app.core.SearchResponse
import shop.sportsearch.app.core.applying
import shop.sportsearch.app.core.displayName
import shop.sportsearch.app.core.formattedDateTime
import shop.sportsearch.app.core.nextStepLabel
import shop.sportsearch.app.core.startsInMinutesText
import shop.sportsearch.app.core.statusLabel
import shop.sportsearch.app.core.statusTintColor
import shop.sportsearch.app.core.venuePendingTitle
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape
import shop.sportsearch.app.ui.theme.statusTintColor as requestStatusTintColor

/** `Color(red: 0.63, green: 0.93, blue: 0.75)` — the sheet's accent. */
private val SheetAccent = Color(0xFFA1EDBF)

/** `Color(red: 1.0, green: 0.47, blue: 0.43)` — the destructive tint. */
private val DangerTint = Color(0xFFFF786E)

/** `Color(red: 1.0, green: 0.70, blue: 0.30)` — "awaiting". */
private val PendingTint = Color(0xFFFFB34D)

/** Port of `private struct GameParticipantStatus`. */
data class GameParticipantStatus(val label: String, val tint: Color)

/** Port of `private struct GameParticipantStatusRow`. */
private data class GameParticipantStatusRow(val user: DiscoverUser, val status: GameParticipantStatus)

/** Port of `struct UpcomingGameDetailsSheet`. */
@Composable
fun UpcomingGameDetailsSheet(
    appModel: AppViewModel,
    request: MatchGameRequest,
    displayName: String,
    avatarUrl: String?,
    isUpdating: Boolean,
    canEdit: Boolean,
    canCancel: Boolean,
    cancelTitle: String,
    onDismiss: () -> Unit,
    onEdit: (() -> Unit)?,
    onCancel: (suspend () -> Unit)?,
    onOpenCourt: ((Court) -> Unit)?,
    onParticipantsChanged: suspend () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()
    val statusTint = request.requestStatusTintColor

    var lobby by remember { mutableStateOf<SearchLobbyGameSearch?>(null) }
    var isLoadingLobby by remember { mutableStateOf(false) }
    var updatingResponseId by remember { mutableStateOf<String?>(null) }

    suspend fun loadSearchLobbyIfNeeded() {
        val searchLobbyId = request.searchLobbyId ?: return
        isLoadingLobby = true
        runCatching { appModel.repository.fetchSearchLobby(searchLobbyId).gameSearch }
            .onSuccess { lobby = it }
            .onFailure(appModel::present)
        isLoadingLobby = false
    }

    LaunchedEffect(request.searchLobbyId) { loadSearchLobbyIfNeeded() }

    val participantRows = remember(request) { participantRows(request) }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        // `sheetBackground` - a status-tinted glow from the top-right corner.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(statusTint.copy(alpha = 0.26f), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(Float.POSITIVE_INFINITY, 0f),
                        radius = 360f * 2.75f,
                    ),
                )
                .background(
                    Brush.verticalGradient(listOf(Color(0xFF080A0A), Color.Black)),
                ),
        )

        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(top = 6.dp), contentAlignment = Alignment.Center) {
                    Box(
                        modifier = Modifier
                            .width(46.dp)
                            .height(5.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.22f)),
                    )
                }
            }

            item {
                DetailsHeader(
                    request = request,
                    displayName = displayName,
                    avatarUrl = avatarUrl,
                    statusTint = statusTint,
                    onDismiss = onDismiss,
                )
            }

            if (canEdit || canCancel) {
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (canEdit && onEdit != null) {
                            DetailsActionButton(
                                title = L10n.string("Edit game", "Изменить игру"),
                                icon = Icons.Filled.EditCalendar,
                                foreground = Color.White,
                                background = AppTheme.court,
                                borderTint = null,
                                modifier = Modifier.weight(1f),
                                onClick = onEdit,
                            )
                        }

                        if (canCancel && onCancel != null) {
                            DetailsActionButton(
                                title = cancelTitle,
                                icon = Icons.Filled.Cancel,
                                foreground = DangerTint,
                                background = Color.White.copy(alpha = 0.06f),
                                borderTint = DangerTint.copy(alpha = 0.34f),
                                isBusy = isUpdating,
                                modifier = Modifier.weight(1f),
                                onClick = { scope.launch { onCancel() } },
                            )
                        }
                    }
                }
            }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    DetailRow(
                        icon = Icons.Filled.CalendarMonth,
                        title = request.proposedDatetime.formattedDateTime(),
                        subtitle = request.startsInMinutesText(),
                    )

                    val court = request.proposedCourt
                    if (court != null && onOpenCourt != null) {
                        DetailRow(
                            icon = Icons.Filled.SportsTennis,
                            title = court.name,
                            subtitle = court.address,
                            accessory = L10n.string("Open club", "Открыть клуб"),
                            modifier = Modifier.clickable {
                                haptics.selection()
                                onOpenCourt(court)
                            },
                        )
                    } else {
                        DetailRow(
                            icon = Icons.Filled.SportsTennis,
                            title = court?.name ?: request.sport.venuePendingTitle,
                            subtitle = court?.address,
                        )
                    }

                    DetailRow(
                        icon = Icons.Filled.CheckCircle,
                        title = request.statusLabel,
                        subtitle = request.nextStepLabel,
                    )

                    DetailRow(
                        icon = Icons.AutoMirrored.Filled.HelpOutline,
                        title = request.effectiveFormatTitle,
                        subtitle = request.sport.title,
                    )
                }
            }

            if (participantRows.isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        SectionCaption(L10n.string("Participants", "Участники"))

                        participantRows.take(8).forEach { row ->
                            ParticipantRow(row)
                        }
                    }
                }
            }

            // `searchResponseApprovalSection`
            if (isLoadingLobby) {
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(continuousShape(20.dp))
                            .background(Color.White.copy(alpha = 0.055f))
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(color = AppTheme.court, modifier = Modifier.size(18.dp))
                        Text(
                            L10n.string("Loading responses", "Загружаем отклики"),
                            fontFamily = appFontFamily,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White.copy(alpha = 0.68f),
                        )
                    }
                }
            } else {
                val responses = lobby?.responses.orEmpty()
                if (responses.isNotEmpty()) {
                    val pending = responses.filter { it.status == "pending" }
                    val approved = responses.filter { it.status == "approved" }
                    val shape = continuousShape(20.dp)

                    item {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(shape)
                                .background(Color.White.copy(alpha = 0.055f))
                                .border(
                                    1.dp,
                                    AppTheme.court.copy(alpha = if (pending.isEmpty()) 0.12f else 0.28f),
                                    shape,
                                )
                                .padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                SectionCaption(
                                    L10n.string("Search responses", "Отклики на поиск"),
                                    modifier = Modifier.weight(1f),
                                )
                                Text(
                                    L10n.string("${approved.size} joined", "${approved.size} в составе"),
                                    fontFamily = appFontFamily,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = AppTheme.court,
                                )
                            }

                            (if (pending.isEmpty()) approved else pending).take(6).forEach { response ->
                                PendingResponseRow(
                                    response = response,
                                    isUpdating = updatingResponseId == response.id,
                                    isLocked = updatingResponseId != null,
                                ) { status ->
                                    scope.launch {
                                        updatingResponseId = response.id
                                        runCatching {
                                            appModel.repository.updateSearchResponseStatus(response.id, status)
                                        }.onSuccess { result ->
                                            lobby = lobby?.applying(result)
                                            if (status == "approved") haptics.success() else haptics.warning()
                                            loadSearchLobbyIfNeeded()
                                            lobby = lobby?.applying(result)
                                            onParticipantsChanged()
                                            appModel.refreshActivitySummary()
                                        }.onFailure(appModel::present)
                                        updatingResponseId = null
                                    }
                                }
                            }
                        }
                    }
                }
            }

            val comment = request.comment?.trim()
            if (!comment.isNullOrEmpty()) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(continuousShape(20.dp))
                            .background(Color.White.copy(alpha = 0.06f))
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        SectionCaption(L10n.string("Comment", "Комментарий"))
                        Text(
                            comment,
                            fontFamily = appFontFamily,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.78f),
                        )
                    }
                }
            }
        }
    }
}

/** `participantRows` - participants first, then invitees, de-duplicated by id. */
private fun participantRows(request: MatchGameRequest): List<GameParticipantStatusRow> {
    val rows = mutableListOf<GameParticipantStatusRow>()
    val seen = mutableSetOf<String>()

    fun append(user: DiscoverUser, status: GameParticipantStatus) {
        if (!seen.add(user.id)) return
        rows += GameParticipantStatusRow(user, status)
    }

    request.participants.forEach { append(it, participantStatus(request, it)) }
    request.invitees.forEach {
        append(it.user, GameParticipantStatus(it.statusLabel, it.statusTintColor))
    }

    return rows
}

private fun participantStatus(request: MatchGameRequest, participant: DiscoverUser): GameParticipantStatus {
    request.invitees.firstOrNull { it.user.id == participant.id }?.let {
        return GameParticipantStatus(it.statusLabel, it.statusTintColor)
    }

    if (participant.id == request.createdByUserId) {
        return GameParticipantStatus(L10n.string("Organizer", "Организатор"), SheetAccent)
    }

    if (participant.id == request.matchedUserId) {
        return primaryRecipientStatus(request)
    }

    return GameParticipantStatus(
        L10n.string("Participant", "Участник"),
        Color.White.copy(alpha = 0.64f),
    )
}

private fun primaryRecipientStatus(request: MatchGameRequest): GameParticipantStatus =
    when (request.status.lowercase()) {
        "accepted", "approved" -> GameParticipantStatus(L10n.string("Accepted", "Принял"), AppTheme.court)
        "declined", "rejected" ->
            GameParticipantStatus(L10n.string("Declined", "Отклонил"), Color.Red.copy(alpha = 0.88f))
        "canceled", "cancelled", "withdrawn" ->
            GameParticipantStatus(L10n.string("Canceled", "Отменено"), Color.Gray.copy(alpha = 0.82f))
        else -> GameParticipantStatus(L10n.string("Awaiting response", "Ожидаем ответ"), PendingTint)
    }

@Composable
private fun DetailsHeader(
    request: MatchGameRequest,
    displayName: String,
    avatarUrl: String?,
    statusTint: Color,
    onDismiss: () -> Unit,
) {
    val shape = continuousShape(26.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Brush.linearGradient(listOf(Color(0xFF242726), Color(0xFF0F1212))))
            .border(1.dp, statusTint.copy(alpha = 0.65f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .border(1.dp, Color.White.copy(alpha = 0.16f), continuousShape(24.dp)),
            ) {
                RemoteAvatarView(name = displayName, path = avatarUrl, size = 72.dp)
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                shop.sportsearch.app.ui.components.AutoSizeText(
                    text = displayName,
                    fontSize = 27.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 2,
                    minScale = 0.76f,
                )
                Text(
                    "${request.sport.title} · ${request.effectiveFormatTitle}",
                    fontFamily = appFontFamily,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.72f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = L10n.string("Close", "Закрыть"),
                    tint = Color.White.copy(alpha = 0.74f),
                    modifier = Modifier.size(14.dp),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AppInlineChip(request.statusLabel, statusTint, Color.White)
            AppInlineChip(request.sport.title, Color.White.copy(alpha = 0.10f), Color.White)
            AppInlineChip(request.effectiveFormatTitle, Color.White.copy(alpha = 0.10f), Color.White)
        }
    }
}

@Composable
private fun DetailsActionButton(
    title: String,
    icon: ImageVector,
    foreground: Color,
    background: Color,
    borderTint: Color?,
    modifier: Modifier = Modifier,
    isBusy: Boolean = false,
    onClick: () -> Unit,
) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = modifier
            .clip(shape)
            .background(background)
            .then(if (borderTint != null) Modifier.border(1.dp, borderTint, shape) else Modifier)
            .clickable(enabled = !isBusy, onClick = onClick)
            .padding(vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isBusy) {
            CircularProgressIndicator(color = foreground, modifier = Modifier.size(18.dp))
        } else {
            Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(16.dp))
            Text(
                title,
                fontFamily = appFontFamily,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = foreground,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun DetailRow(
    icon: ImageVector,
    title: String,
    subtitle: String?,
    accessory: String? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(continuousShape(20.dp))
            .background(Color.White.copy(alpha = 0.055f))
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(continuousShape(14.dp))
                .background(Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = SheetAccent, modifier = Modifier.size(17.dp))
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                title,
                fontFamily = appFontFamily,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (!subtitle.isNullOrEmpty()) {
                Text(
                    subtitle,
                    fontFamily = appFontFamily,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.62f),
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        if (accessory != null) {
            Text(
                accessory,
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = SheetAccent,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun SectionCaption(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        modifier = modifier,
        fontFamily = appFontFamily,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 1.8.sp,
        color = Color.White.copy(alpha = 0.58f),
    )
}

@Composable
private fun ParticipantRow(row: GameParticipantStatusRow) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(18.dp))
            .background(Color.White.copy(alpha = 0.06f))
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RemoteAvatarView(name = row.user.displayName, path = row.user.avatarUrl, size = 42.dp)

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                row.user.displayName,
                fontFamily = appFontFamily,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                row.status.label,
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = row.status.tint,
                maxLines = 1,
            )
        }

        GameParticipantStatusPill(row.status)
    }
}

/** Port of `private struct GameParticipantStatusPill`. */
@Composable
private fun GameParticipantStatusPill(status: GameParticipantStatus) {
    Text(
        status.label,
        modifier = Modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(status.tint.copy(alpha = 0.14f))
            .border(1.dp, status.tint.copy(alpha = 0.32f), RoundedCornerShape(percent = 50))
            .padding(horizontal = 9.dp, vertical = 6.dp),
        fontFamily = appFontFamily,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = status.tint,
        maxLines = 1,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun PendingResponseRow(
    response: SearchResponse,
    isUpdating: Boolean,
    isLocked: Boolean,
    onUpdate: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(16.dp))
            .background(Color.White.copy(alpha = 0.055f))
            .padding(10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RemoteAvatarView(
            name = response.responderUser.displayName,
            path = response.responderUser.avatarUrl,
            size = 40.dp,
        )

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                response.responderUser.displayName,
                fontFamily = appFontFamily,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                if (response.status == "approved") {
                    L10n.string("Already in the group", "Уже в составе")
                } else {
                    L10n.string("Awaiting decision", "Ждёт решения")
                },
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = if (response.status == "approved") AppTheme.court else PendingTint,
            )
        }

        if (response.status == "pending") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ResponseActionButton(Icons.Filled.Check, AppTheme.court, Color.White, isUpdating, isLocked) {
                    onUpdate("approved")
                }
                ResponseActionButton(Icons.Filled.Close, Color(0xFF401A1A), DangerTint, isUpdating, isLocked) {
                    onUpdate("rejected")
                }
            }
        } else {
            Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = AppTheme.court,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
private fun ResponseActionButton(
    icon: ImageVector,
    background: Color,
    foreground: Color,
    isUpdating: Boolean,
    isLocked: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(background)
            .clickable(enabled = !isLocked, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (isUpdating) {
            CircularProgressIndicator(color = foreground, modifier = Modifier.size(16.dp))
        } else {
            Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(14.dp))
        }
    }
}
