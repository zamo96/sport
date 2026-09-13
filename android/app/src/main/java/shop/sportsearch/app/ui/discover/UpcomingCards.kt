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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PersonAddAlt1
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.ReportPhotoGalleryItem
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.maps.RunningRoutePreviewMapView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import shop.sportsearch.app.ui.theme.statusTintColor
import java.time.Instant

private val mint = Color(red = 0.63f, green = 0.93f, blue = 0.75f)

/** Port of `struct UpcomingGameCard` in ios/TennisSearchIOS/Views/DiscoverView.swift. */
@Composable
fun UpcomingGameCard(
    request: MatchGameRequest,
    displayName: String,
    avatarUrl: String?,
    currentUserId: String?,
    isUpdating: Boolean,
    isAddingToCalendar: Boolean,
    onSelectParticipant: (DiscoverUser) -> Unit,
    onOpenChat: (() -> Unit)?,
    onOpenDetails: (() -> Unit)?,
    onOpenCourt: (() -> Unit)?,
    onShare: (() -> Unit)?,
    onAddToCalendar: (() -> Unit)?,
    onAccept: (() -> Unit)?,
    onCancel: (() -> Unit)?,
    onMarkOutcome: ((String) -> Unit)?,
    onAddPhotoReport: (() -> Unit)?,
    onConfirmReport: ((String) -> Unit)?,
    onProposeNext: (() -> Unit)?,
    onOpenGallery: (ReportPhotoGalleryItem) -> Unit,
) {
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp
    val isCompactScreen = screenWidth <= 430.dp
    val heroHeight = if (isCompactScreen) 104.dp else 118.dp
    val avatarSize = if (isCompactScreen) 44.dp else 52.dp
    val titleSize = if (isCompactScreen) 18.sp else 22.sp
    val outerPadding = if (isCompactScreen) 8.dp else 10.dp
    val innerPadding = if (isCompactScreen) 10.dp else 12.dp

    val statusTint = request.statusTintColor
    val visibleParticipants = request.visibleParticipants(currentUserId)
    val courtLabel = request.proposedCourt?.name
        ?: request.runningRoute?.trim()
        ?: request.sport.venuePendingTitle

    val shape = continuousShape(28.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .appShadow(statusTint.copy(alpha = 0.14f), radius = 18.dp, offsetY = 10.dp, shape = shape)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        Color(red = 0.10f, green = 0.10f, blue = 0.11f),
                        Color(red = 0.05f, green = 0.05f, blue = 0.06f),
                    ),
                ),
            )
            .border(1.6.dp, statusTint.copy(alpha = 0.9f), shape)
            .clickable(enabled = onOpenDetails != null) { onOpenDetails?.invoke() }
            .padding(outerPadding),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // heroSection - the SwiftUI card draws the identity block over the photo.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(heroHeight)
                .clip(continuousShape(24.dp)),
        ) {
            val hasRouteMap = request.sport.isRouteSport && request.runningRoutePoints.size >= 2
            if (hasRouteMap) {
                RunningRoutePreviewMapView(
                    points = request.runningRoutePoints,
                    followsRoads = request.sport.routeFollowsRoads,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                listOf(
                                    Color(red = 0.16f, green = 0.19f, blue = 0.16f),
                                    Color(red = 0.10f, green = 0.11f, blue = 0.10f),
                                ),
                            ),
                        ),
                )
            }
            Box(
                modifier = Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = 0.08f),
                            Color.Black.copy(alpha = 0.54f),
                            Color.Black.copy(alpha = 0.88f),
                        ),
                    ),
                ),
            )

            Row(
                modifier = Modifier.fillMaxSize().padding(innerPadding),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RemoteAvatarView(
                    name = displayName,
                    path = avatarUrl,
                    size = avatarSize,
                    modifier = Modifier.border(
                        1.dp,
                        Color.White.copy(alpha = 0.16f),
                        continuousShape(avatarSize * 0.34f),
                    ),
                )

                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        displayName,
                        fontSize = titleSize,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        "${request.sport.title} · ${request.effectiveFormatTitle}",
                        fontSize = if (isCompactScreen) 13.sp else 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.78f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (!isCompactScreen) {
                        request.comment?.takeIf { it.isNotEmpty() }?.let { comment ->
                            Text(
                                comment,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color.White.copy(alpha = 0.68f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }

                AppInlineChip(text = request.statusLabel, tint = statusTint, foreground = Color.White)
            }
        }

        Column(
            modifier = Modifier.padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // infoRow
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CompactInfoBlock(
                    icon = Icons.Filled.CalendarMonth,
                    title = request.proposedDatetime.formattedDateTime(),
                    subtitle = null,
                    isCompactScreen = isCompactScreen,
                    modifier = Modifier.weight(1f),
                ) {
                    // `TimelineView(.periodic(by: 30))` - a ticking countdown.
                    var countdown by remember(request.id) { mutableStateOf(request.startsInMinutesText()) }
                    LaunchedEffect(request.id) {
                        while (true) {
                            delay(30_000)
                            countdown = request.startsInMinutesText()
                        }
                    }
                    countdown?.let {
                        Text(
                            it,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color(red = 1.0f, green = 0.70f, blue = 0.30f),
                            maxLines = 1,
                        )
                    }
                }

                Box(Modifier.width(1.dp).height(52.dp).background(Color.White.copy(alpha = 0.08f)))

                CompactInfoBlock(
                    icon = Icons.Filled.SportsTennis,
                    title = request.sport.venueFieldTitle,
                    subtitle = courtLabel,
                    isCompactScreen = isCompactScreen,
                    modifier = Modifier
                        .weight(1f)
                        .then(
                            if (onOpenCourt != null && request.proposedCourt != null) {
                                Modifier.clickable(onClick = onOpenCourt)
                            } else {
                                Modifier
                            },
                        ),
                ) {
                    if (onOpenCourt != null && request.proposedCourt != null) {
                        Text(
                            L10n.string("Open club", "Открыть клуб"),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = mint,
                            maxLines = 1,
                        )
                    }
                }
            }

            Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))

            // footerRow
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Row(horizontalArrangement = Arrangement.spacedBy((-8).dp)) {
                        if (visibleParticipants.isEmpty()) {
                            RemoteAvatarView(name = displayName, path = avatarUrl, size = 36.dp)
                        } else {
                            visibleParticipants.take(2).forEach { participant ->
                                RemoteAvatarView(
                                    name = participant.displayName,
                                    path = participant.avatarUrl,
                                    size = 36.dp,
                                    modifier = Modifier
                                        .border(1.5.dp, Color(red = 0.10f, green = 0.10f, blue = 0.11f), CircleShape)
                                        .clickable { onSelectParticipant(participant) },
                                )
                            }
                            val overflow = maxOf(request.participantCount - 2, 0)
                            if (overflow > 0) {
                                Box(
                                    modifier = Modifier
                                        .size(36.dp)
                                        .clip(CircleShape)
                                        .background(Color.White.copy(alpha = 0.12f))
                                        .border(1.5.dp, Color(red = 0.10f, green = 0.10f, blue = 0.11f), CircleShape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        "+$overflow",
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White.copy(alpha = 0.86f),
                                    )
                                }
                            }
                        }
                    }

                    Text(
                        "${request.participantCount} ${participantsCountWord(request.participantCount)}",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.62f),
                        maxLines = 1,
                    )
                }

                Spacer(Modifier.weight(1f))

                onOpenChat?.let {
                    CircleActionButton(Icons.AutoMirrored.Filled.Message, AppTheme.court, Color.White, 44.dp, false, it)
                }
                onAccept?.let {
                    CircleActionButton(Icons.Filled.Check, AppTheme.court, Color.White, 40.dp, isUpdating, it)
                }
                if (onShare != null && !request.isRegularOccurrence) {
                    CircleActionButton(
                        Icons.Filled.PersonAddAlt1,
                        Color.White.copy(alpha = 0.08f),
                        Color.White,
                        40.dp,
                        false,
                        onShare,
                    )
                }
                onAddToCalendar?.let {
                    CircleActionButton(
                        Icons.Filled.EditCalendar,
                        Color.White.copy(alpha = 0.08f),
                        Color.White,
                        40.dp,
                        isAddingToCalendar,
                        it,
                    )
                }
                onOpenDetails?.let {
                    CircleActionButton(
                        Icons.Filled.MoreHoriz,
                        Color.White.copy(alpha = 0.08f),
                        Color.White,
                        40.dp,
                        false,
                        it,
                    )
                }
            }

            val report = request.report
            when {
                report != null -> GameReportCompactSummary(
                    report = report,
                    isUpdating = isUpdating,
                    onOpenGallery = onOpenGallery,
                )

                (request.canAddPhotoReport || request.needsOutcomeReview) && onMarkOutcome != null ->
                    GameOutcomePrompt(
                        isUpdating = isUpdating,
                        onAddPhotoReport = onAddPhotoReport,
                        onPlayed = { onMarkOutcome("played") },
                        onMissed = { onMarkOutcome("not_played") },
                        onProposeNext = onProposeNext,
                    )

                request.outcome != null -> GameOutcomeSummary(
                    label = request.outcomeLabel ?: L10n.string("Result saved", "Итог сохранён"),
                    onProposeNext = onProposeNext,
                )
            }

            onCancel?.let { cancel ->
                SecondaryActionButton(
                    title = if (request.createdByUserId == currentUserId) {
                        L10n.string("Cancel", "Отменить")
                    } else {
                        L10n.string("I can't make it", "Не смогу")
                    },
                    onClick = cancel,
                    tint = Color.Red.copy(alpha = 0.8f),
                    enabled = !isUpdating,
                )
            }
        }
    }
}

@Composable
private fun CompactInfoBlock(
    icon: ImageVector,
    title: String,
    subtitle: String?,
    isCompactScreen: Boolean,
    modifier: Modifier = Modifier,
    accessory: @Composable () -> Unit = {},
) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(continuousShape(10.dp))
                .background(Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = mint, modifier = Modifier.size(14.dp))
        }

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                title,
                fontSize = if (isCompactScreen) 14.sp else 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            subtitle?.let {
                Text(
                    it,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.62f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            accessory()
        }
    }
}

@Composable
private fun CircleActionButton(
    icon: ImageVector,
    background: Color,
    foreground: Color,
    size: Dp,
    isBusy: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(background)
            .clickable(enabled = !isBusy, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (isBusy) {
            CircularProgressIndicator(color = foreground, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
        } else {
            Icon(icon, null, tint = foreground, modifier = Modifier.size(size * 0.38f))
        }
    }
}

/** Port of `struct GameReportCompactSummary`. */
@Composable
fun GameReportCompactSummary(
    report: GameReport,
    isUpdating: Boolean,
    onOpenGallery: (ReportPhotoGalleryItem) -> Unit,
) {
    val confirmed = report.status.lowercase() == "confirmed"
    val tint = if (confirmed) AppTheme.court else Color(0xFFFF9800)
    val shape = continuousShape(22.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.07f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                if (confirmed) Icons.Filled.CheckCircle else Icons.Filled.Schedule,
                null,
                tint = tint,
                modifier = Modifier.size(15.dp),
            )
            Text(report.statusTitle, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = tint)
            Spacer(Modifier.weight(1f))
            Text(
                L10n.string("${report.photoUrls.size} photos", "${report.photoUrls.size} фото"),
                style = AppText.captionSemibold,
                color = Color.White.copy(alpha = 0.58f),
            )
        }

        val previewUrls = report.photoUrls.take(4)
        if (previewUrls.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                previewUrls.forEachIndexed { index, path ->
                    GameReportThumbnail(
                        path = path,
                        modifier = Modifier.weight(1f).clickable {
                            onOpenGallery(
                                ReportPhotoGalleryItem(
                                    photoPaths = report.photoUrls,
                                    initialIndex = index,
                                    title = L10n.string("Game photo report", "Фотоотчёт об игре"),
                                    subtitle = report.statusTitle,
                                    comment = report.comment,
                                ),
                            )
                        },
                    )
                }
            }
        }

        report.comment?.takeIf { it.isNotEmpty() }?.let {
            Text(
                it,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.74f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Text(
            L10n.string(
                "The report was saved without additional confirmation.",
                "Отчёт сохранён без дополнительного подтверждения.",
            ),
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.56f),
        )
    }
}

/** Port of `struct GameReportThumbnail`. */
@Composable
fun GameReportThumbnail(path: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .height(58.dp)
            .clip(continuousShape(12.dp))
            .background(Color.White.copy(alpha = 0.08f)),
        contentAlignment = Alignment.Center,
    ) {
        val url = resolveAppRemoteUrl(path)
        if (url != null) {
            AsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Icon(
                Icons.Filled.PhotoCamera,
                null,
                tint = Color.White.copy(alpha = 0.46f),
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

/** Port of `struct GameOutcomePrompt`. */
@Composable
fun GameOutcomePrompt(
    isUpdating: Boolean,
    onAddPhotoReport: (() -> Unit)?,
    onPlayed: () -> Unit,
    onMissed: () -> Unit,
    onProposeNext: (() -> Unit)?,
) {
    val shape = continuousShape(22.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.07f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                L10n.string("The game has ended", "Игра закончилась").uppercase(),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.4.sp,
                color = mint,
            )
            Text(
                L10n.string("Did you play?", "Удалось сыграть?"),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
            if (onAddPhotoReport != null) {
                Text(
                    L10n.string(
                        "Save the session to your profile: add 1–5 photos and a short comment.",
                        "Сохрани тренировку в профиль: добавь 1-5 фото и короткий комментарий.",
                    ),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.62f),
                )
            }
        }

        onAddPhotoReport?.let {
            PrimaryActionButton(
                title = L10n.string("Add photo report", "Добавить фотоотчёт"),
                tint = AppTheme.court,
                enabled = !isUpdating,
                onClick = it,
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutcomeButton(
                title = if (onAddPhotoReport == null) {
                    L10n.string("Yes, we played", "Да, сыграли")
                } else {
                    L10n.string("No photo", "Без фото")
                },
                icon = Icons.Filled.CheckCircle,
                tint = if (onAddPhotoReport == null) AppTheme.court else Color.White.copy(alpha = 0.10f),
                isUpdating = isUpdating,
                modifier = Modifier.weight(1f),
                onClick = onPlayed,
            )
            OutcomeButton(
                title = L10n.string("Did not happen", "Не состоялась"),
                icon = Icons.Filled.Cancel,
                tint = Color(red = 0.63f, green = 0.22f, blue = 0.20f),
                isUpdating = isUpdating,
                modifier = Modifier.weight(1f),
                onClick = onMissed,
            )
        }

        onProposeNext?.let {
            SecondaryActionButton(
                title = L10n.string("Schedule another", "Назначить следующую"),
                onClick = it,
                tint = AppTheme.ink,
                enabled = !isUpdating,
            )
        }
    }
}

@Composable
private fun OutcomeButton(
    title: String,
    icon: ImageVector,
    tint: Color,
    isUpdating: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = modifier
            .height(46.dp)
            .clip(shape)
            .background(tint)
            .border(1.dp, Color.White.copy(alpha = 0.12f), shape)
            .clickable(enabled = !isUpdating, onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isUpdating) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
        } else {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(15.dp))
        }
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1)
    }
}

/** Port of `struct GameOutcomeSummary`. */
@Composable
fun GameOutcomeSummary(label: String, onProposeNext: (() -> Unit)?) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .clip(continuousShape(18.dp))
            .background(Color.White.copy(alpha = 0.06f))
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Verified, null, tint = AppTheme.court, modifier = Modifier.size(16.dp))
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        Spacer(Modifier.weight(1f))
        onProposeNext?.let {
            Text(
                L10n.string("Next", "Следующая"),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppTheme.court,
                modifier = Modifier.clickable(onClick = it),
            )
        }
    }
}

/** Port of `struct PersonalActivityUpcomingCard`. */
@Composable
fun PersonalActivityUpcomingCard(
    activity: PersonalActivity,
    isUpdating: Boolean,
    onAddPhotoReport: (() -> Unit)?,
    onCompleteWithoutPhoto: (() -> Unit)?,
    onCancel: (() -> Unit)?,
    onOpenCourt: () -> Unit,
    onOpenGallery: (ReportPhotoGalleryItem) -> Unit,
) {
    val statusTitle = when (activity.status.lowercase()) {
        "completed" -> if (activity.photoUrls.isEmpty()) {
            L10n.string("Completed", "Завершено")
        } else {
            L10n.string("Photo report saved", "Фотоотчёт сохранён")
        }
        "canceled" -> L10n.string("Canceled", "Отменено")
        else -> if (activity.hasEnded) {
            L10n.string("Visit completed", "Визит завершён")
        } else {
            L10n.string("Scheduled", "Запланировано")
        }
    }
    val statusColor = when (activity.status.lowercase()) {
        "completed" -> AppTheme.court
        "canceled" -> Color.Red.copy(alpha = 0.78f)
        else -> if (activity.hasEnded) Color(0xFFFF9800) else Color.White.copy(alpha = 0.62f)
    }

    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(listOf(Color.White.copy(alpha = 0.08f), Color.White.copy(alpha = 0.045f))),
            )
            .border(1.dp, Color.White.copy(alpha = 0.1f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier.size(48.dp).clip(CircleShape).background(AppTheme.court),
                contentAlignment = Alignment.Center,
            ) {
                SportIconView(sport = activity.sport, color = Color.Black, size = 24.dp)
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(activity.sport.title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text(
                    activity.scheduledAt.formattedDateTime(),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.68f),
                )
                Row(
                    modifier = Modifier.clickable(onClick = onOpenCourt),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Outlined.Place,
                        null,
                        tint = Color.White.copy(alpha = 0.58f),
                        modifier = Modifier.size(13.dp),
                    )
                    Text(
                        activity.court?.name ?: L10n.string("Club", "Клуб"),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.58f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            Box(
                modifier = Modifier
                    .height(28.dp)
                    .clip(CircleShape)
                    .background(statusColor.copy(alpha = 0.14f))
                    .padding(horizontal = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(statusTitle, style = AppText.captionBold, color = statusColor, maxLines = 1)
            }
        }

        activity.comment?.takeIf { it.isNotEmpty() }?.let {
            Text(
                it,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.58f),
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
        }

        if (activity.photoUrls.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                activity.photoUrls.take(4).forEachIndexed { index, path ->
                    GameReportThumbnail(
                        path = path,
                        modifier = Modifier.weight(1f).clickable {
                            onOpenGallery(
                                ReportPhotoGalleryItem(
                                    photoPaths = activity.photoUrls,
                                    initialIndex = index,
                                    title = activity.sport.title,
                                    subtitle = L10n.string(
                                        "Personal visit photo report",
                                        "Фотоотчёт личного визита",
                                    ),
                                    comment = activity.reportComment,
                                ),
                            )
                        },
                    )
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            onAddPhotoReport?.let {
                Box(modifier = Modifier.weight(1f)) {
                    PrimaryActionButton(
                        title = if (activity.photoUrls.isEmpty()) {
                            L10n.string("Add photo report", "Добавить фотоотчёт")
                        } else {
                            L10n.string("Edit report", "Изменить отчёт")
                        },
                        tint = AppTheme.court,
                        enabled = !isUpdating,
                        onClick = it,
                    )
                }
            }

            if (onCompleteWithoutPhoto != null && activity.photoUrls.isEmpty()) {
                Box(modifier = Modifier.weight(1f)) {
                    SecondaryActionButton(
                        title = L10n.string("No photo", "Без фото"),
                        onClick = onCompleteWithoutPhoto,
                        tint = Color.White,
                        enabled = !isUpdating,
                    )
                }
            }

            if (onCancel != null && !activity.hasEnded) {
                Box(
                    modifier = Modifier
                        .size(42.dp)
                        .clip(continuousShape(14.dp))
                        .background(Color.Red.copy(alpha = 0.14f))
                        .clickable(enabled = !isUpdating, onClick = onCancel),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Close, null, tint = Color.Red, modifier = Modifier.size(14.dp))
                }
            }
        }
    }
}

/** Port of `struct UpcomingEmptyState`. */
@Composable
fun UpcomingEmptyState(onCreateSearch: () -> Unit) {
    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(horizontal = 18.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier.size(68.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.CalendarMonth, null, tint = AppTheme.court, modifier = Modifier.size(34.dp))
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                L10n.string("No upcoming games yet", "Ближайших игр пока нет"),
                style = AppText.headlineBold,
                color = Color.White,
            )
            Text(
                L10n.string(
                    "Create an urgent search to quickly organize a game. It will appear here after confirmation.",
                    "Создай срочный поиск, чтобы быстро собрать игру и увидеть её здесь после подтверждения.",
                ),
                style = AppText.subheadline,
                color = Color.White.copy(alpha = 0.58f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }

        Row(
            modifier = Modifier
                .height(46.dp)
                .clip(CircleShape)
                .background(AppTheme.court)
                .clickable(onClick = onCreateSearch)
                .padding(horizontal = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Add, null, tint = Color.White, modifier = Modifier.size(15.dp))
            Text(
                L10n.string("Create search", "Создать поиск"),
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }
    }
}
