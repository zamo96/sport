package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.Image
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.MatchGameRequest
import shop.sportsearch.app.core.PersonalActivity
import shop.sportsearch.app.core.PersonalActivityUpdateDraft
import shop.sportsearch.app.core.formattedDateTime
import shop.sportsearch.app.core.venuePendingTitle
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.PendingChatPhoto
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.components.rememberChatPhotoPicker
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct GameReportComposerSheet` in ios/TennisSearchIOS/Views/DiscoverView.swift. */
@Composable
fun GameReportComposerSheet(
    appModel: AppViewModel,
    request: MatchGameRequest,
    onDismiss: () -> Unit,
    onSubmitted: suspend () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    HideBottomBarWhileVisible(appModel)
    val scope = rememberCoroutineScope()

    var photos by remember { mutableStateOf<List<PendingChatPhoto>>(emptyList()) }
    var comment by remember { mutableStateOf("") }
    var visibility by remember { mutableStateOf("profile") }
    var isSubmitting by remember { mutableStateOf(false) }

    val pickPhotos = rememberChatPhotoPicker { picked -> photos = (photos + picked).take(5) }

    ReportComposerScaffold(
        title = L10n.string("Add photo report", "Добавить фотоотчёт"),
        photos = photos,
        maxPhotos = 5,
        onPick = pickPhotos,
        onRemove = { photo -> photos = photos.filterNot { it.id == photo.id } },
        comment = comment,
        onCommentChange = { comment = it },
        commentPlaceholder = L10n.string(
            "Great game, thanks for the match!",
            "Хорошая игра, спасибо за матч!",
        ),
        visibility = visibility,
        onVisibilityChange = { visibility = it },
        isSubmitting = isSubmitting,
        submitTitle = L10n.string("Send to partner", "Отправить партнёру"),
        onDismiss = onDismiss,
        onSubmit = {
            if (photos.isEmpty() || isSubmitting) return@ReportComposerScaffold
            scope.launch {
                isSubmitting = true
                runCatching {
                    val urls = photos.map {
                        appModel.repository.uploadGameReportPhoto(request.id, it.bytes, it.fileName, it.mimeType)
                    }
                    appModel.repository.createGameReport(request.id, urls, comment, visibility)
                }.onSuccess {
                    onDismiss()
                    onSubmitted()
                }.onFailure(appModel::present)
                isSubmitting = false
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(24.dp))
                .background(Color.White.copy(alpha = 0.06f))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                L10n.string("Game", "Игра").uppercase(),
                style = AppText.captionBold.copy(letterSpacing = 1.2.sp),
                color = Color.White.copy(alpha = 0.5f),
            )
            Text(
                "${request.sport.title} · ${request.proposedDatetime.formattedDateTime()}",
                style = AppText.headlineBold,
                color = Color.White,
            )
            val venue = request.proposedCourt?.name ?: request.sport.venuePendingTitle
            val duration = request.durationMinutes ?: 90
            Text(
                L10n.string("$venue · $duration min", "$venue · $duration мин"),
                style = AppText.subheadline,
                color = Color.White.copy(alpha = 0.62f),
            )
        }
    }
}

/** Port of `struct PersonalActivityReportComposerSheet`. */
@Composable
fun PersonalActivityReportComposerSheet(
    appModel: AppViewModel,
    activity: PersonalActivity,
    onDismiss: () -> Unit,
    onSubmitted: suspend () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    HideBottomBarWhileVisible(appModel)
    val scope = rememberCoroutineScope()

    var photos by remember { mutableStateOf<List<PendingChatPhoto>>(emptyList()) }
    var comment by remember { mutableStateOf(activity.reportComment.orEmpty()) }
    var isSubmitting by remember { mutableStateOf(false) }

    val pickPhotos = rememberChatPhotoPicker { picked -> photos = (photos + picked).take(5) }

    ReportComposerScaffold(
        title = L10n.string("Visit photo report", "Фотоотчёт визита"),
        photos = photos,
        maxPhotos = 5,
        onPick = pickPhotos,
        onRemove = { photo -> photos = photos.filterNot { it.id == photo.id } },
        comment = comment,
        onCommentChange = { comment = it },
        commentPlaceholder = L10n.string(
            "For example: a good session, 40 minutes on the track",
            "Например: хорошая тренировка, 40 минут на дорожке",
        ),
        visibility = null,
        onVisibilityChange = {},
        isSubmitting = isSubmitting,
        submitTitle = L10n.string("Save report", "Сохранить отчёт"),
        onDismiss = onDismiss,
        onSubmit = {
            if (photos.isEmpty() || isSubmitting) return@ReportComposerScaffold
            scope.launch {
                isSubmitting = true
                runCatching {
                    val urls = photos.map {
                        appModel.repository.uploadPersonalActivityPhoto(
                            activity.id,
                            it.bytes,
                            it.fileName,
                            it.mimeType,
                        )
                    }
                    appModel.repository.updatePersonalActivity(
                        activity.id,
                        PersonalActivityUpdateDraft(
                            status = "completed",
                            reportComment = comment,
                            photoUrls = urls,
                        ),
                    )
                }.onSuccess {
                    onDismiss()
                    onSubmitted()
                }.onFailure(appModel::present)
                isSubmitting = false
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(24.dp))
                .background(Color.White.copy(alpha = 0.06f))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                L10n.string("Visit", "Визит").uppercase(),
                style = AppText.captionBold.copy(letterSpacing = 1.2.sp),
                color = Color.White.copy(alpha = 0.5f),
            )
            Text(
                "${activity.sport.title} · ${activity.scheduledAt.formattedDateTime()}",
                style = AppText.headlineBold,
                color = Color.White,
            )
            activity.court?.name?.let {
                Text(it, style = AppText.subheadline, color = Color.White.copy(alpha = 0.62f))
            }
        }
    }
}

@Composable
private fun ReportComposerScaffold(
    title: String,
    photos: List<PendingChatPhoto>,
    maxPhotos: Int,
    onPick: () -> Unit,
    onRemove: (PendingChatPhoto) -> Unit,
    comment: String,
    onCommentChange: (String) -> Unit,
    commentPlaceholder: String,
    visibility: String?,
    onVisibilityChange: (String) -> Unit,
    isSubmitting: Boolean,
    submitTitle: String,
    onDismiss: () -> Unit,
    onSubmit: () -> Unit,
    gameSection: @Composable () -> Unit,
) {
    val haptics = rememberAppHaptics()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .navigationBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 18.dp, bottom = 34.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    null,
                    tint = Color.White,
                    modifier = Modifier.size(18.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            Text(title, style = AppText.headlineBold, color = Color.White)
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(38.dp))
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(24.dp))
                .background(Color.White.copy(alpha = 0.06f))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(L10n.string("Photo", "Фото"), style = AppText.headlineBold, color = Color.White)

            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                photos.forEach { photo ->
                    Box {
                        Image(
                            bitmap = photo.preview,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.size(74.dp).clip(continuousShape(16.dp)),
                        )
                        Box(
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(5.dp)
                                .size(20.dp)
                                .clip(CircleShape)
                                .background(Color.Black.copy(alpha = 0.7f))
                                .clickable { onRemove(photo) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(10.dp))
                        }
                    }
                }

                Column(
                    modifier = Modifier
                        .size(74.dp)
                        .clip(continuousShape(16.dp))
                        .background(Color.White.copy(alpha = 0.08f))
                        .border(1.dp, Color.White.copy(alpha = 0.16f), continuousShape(16.dp))
                        .clickable(enabled = !isSubmitting, onClick = onPick),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
                ) {
                    Icon(Icons.Filled.Add, null, tint = Color.White, modifier = Modifier.size(22.dp))
                    Text(
                        "${photos.size}/$maxPhotos",
                        style = AppText.captionSemibold,
                        color = Color.White,
                    )
                }
            }
        }

        gameSection()

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(L10n.string("Comment", "Комментарий"), style = AppText.headlineBold, color = Color.White)
            OutlinedTextField(
                value = comment,
                onValueChange = onCommentChange,
                modifier = Modifier.fillMaxWidth().height(110.dp),
                placeholder = {
                    Text(commentPlaceholder, color = Color.White.copy(alpha = 0.38f), style = AppText.subheadline)
                },
                textStyle = AppText.subheadline.copy(color = Color.White),
                shape = continuousShape(18.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.White.copy(alpha = 0.08f),
                    unfocusedContainerColor = Color.White.copy(alpha = 0.08f),
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    cursorColor = AppTheme.court,
                ),
            )
        }

        if (visibility != null) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    L10n.string("Who can see the report", "Кто видит отчёт"),
                    style = AppText.headlineBold,
                    color = Color.White,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    VisibilityButton(
                        L10n.string("On profile", "В профиле"),
                        L10n.string("Everyone", "Все"),
                        "profile",
                        visibility,
                        Modifier.weight(1f),
                    ) {
                        haptics.selection()
                        onVisibilityChange(it)
                    }
                    VisibilityButton(
                        L10n.string("Participants", "Участникам"),
                        L10n.string("Game only", "Только игра"),
                        "participants",
                        visibility,
                        Modifier.weight(1f),
                    ) {
                        haptics.selection()
                        onVisibilityChange(it)
                    }
                    VisibilityButton(
                        L10n.string("Private", "Приватно"),
                        L10n.string("Not in feed", "Без ленты"),
                        "private",
                        visibility,
                        Modifier.weight(1f),
                    ) {
                        haptics.selection()
                        onVisibilityChange(it)
                    }
                }
            }
        }

        Box {
            PrimaryActionButton(
                title = if (isSubmitting) L10n.string("Sending...", "Отправляем...") else submitTitle,
                tint = AppTheme.court,
                enabled = photos.isNotEmpty() && !isSubmitting,
                onClick = onSubmit,
            )
            if (isSubmitting) {
                Box(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

@Composable
private fun VisibilityButton(
    title: String,
    subtitle: String,
    value: String,
    selected: String,
    modifier: Modifier = Modifier,
    onSelect: (String) -> Unit,
) {
    val isSelected = selected == value
    val shape = continuousShape(16.dp)
    Column(
        modifier = modifier
            .clip(shape)
            .background(if (isSelected) AppTheme.court else Color.White.copy(alpha = 0.08f))
            .border(
                1.dp,
                if (isSelected) AppTheme.court.copy(alpha = 0.5f) else Color.White.copy(alpha = 0.1f),
                shape,
            )
            .clickable { onSelect(value) }
            .padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            title,
            style = AppText.captionBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        Text(
            subtitle,
            style = AppText.caption2Semibold,
            color = Color.White.copy(alpha = if (isSelected) 0.72f else 0.45f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}
