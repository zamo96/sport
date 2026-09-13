package shop.sportsearch.app.ui.profile

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlin.math.ceil
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `private struct ProfileVideoTrimEditorSheet` in
 * ios/TennisSearchIOS/Views/ProfileView.swift.
 */
@OptIn(UnstableApi::class)
@Composable
fun ProfileVideoTrimEditorSheet(
    draft: ProfileVideoTrimDraft,
    isUploading: Boolean,
    onCancel: () -> Unit,
    onConfirm: (Double) -> Unit,
) {
    DismissOnSystemBack(onCancel)

    val context = LocalContext.current
    var startTime by remember(draft.sourceFile) { mutableStateOf(0.0) }
    var didSubmit by remember(draft.sourceFile) { mutableStateOf(false) }

    val maxStartTime = maxOf(draft.duration - PROFILE_VIDEO_CLIP_SECONDS, 0.0)
    val isProcessing = isUploading || didSubmit
    val selectedDuration = minOf(PROFILE_VIDEO_CLIP_SECONDS, maxOf(draft.duration - startTime, 0.0))
    val endTime = minOf(startTime + selectedDuration, draft.duration)

    val player = remember(draft.sourceFile) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(draft.sourceFile)))
            volume = 0f
            repeatMode = ExoPlayer.REPEAT_MODE_ONE
            prepare()
            playWhenReady = true
        }
    }

    DisposableEffect(player) {
        onDispose { player.release() }
    }

    // `.onChange(of: startTime) { seekPlayer(to: $0) }`
    LaunchedEffect(startTime) {
        player.seekTo((startTime * 1000).toLong())
    }

    // `.onChange(of: isUploading) { if !$0 { didSubmit = false } }`
    LaunchedEffect(isUploading) {
        if (!isUploading) didSubmit = false
    }

    LaunchedEffect(isProcessing) {
        if (isProcessing) player.pause()
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 18.dp)
                .padding(top = 22.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        L10n.string("Trim video", "Обрезать видео"),
                        style = AppText.title2Bold,
                        color = Color.White,
                    )
                    Text(
                        L10n.string("Choose a clip up to 10 seconds", "Выберите фрагмент до 10 секунд"),
                        style = AppText.subheadlineSemibold,
                        color = Color.White.copy(alpha = 0.58f),
                    )
                }

                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.1f))
                        .clickable(onClick = onCancel),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Close, contentDescription = null, tint = Color.White)
                }
            }

            AndroidView(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(360.dp)
                    .clip(continuousShape(24.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), continuousShape(24.dp)),
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        useController = false
                        setShutterBackgroundColor(android.graphics.Color.BLACK)
                        this.player = player
                    }
                },
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(20.dp))
                    .background(Color.White.copy(alpha = 0.06f))
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${formatClipTime(startTime)} - ${formatClipTime(endTime)}",
                        style = AppText.headlineBold,
                        color = Color.White,
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        L10n.string(
                            "${ceil(selectedDuration).toInt()} sec",
                            "${ceil(selectedDuration).toInt()} сек",
                        ),
                        style = AppText.captionBold,
                        color = AppTheme.mint,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(AppTheme.court.copy(alpha = 0.28f))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                }

                TrimTimeline(
                    duration = draft.duration,
                    startTime = startTime,
                    selectedDuration = selectedDuration,
                )

                Slider(
                    value = startTime.toFloat(),
                    onValueChange = { startTime = it.toDouble() },
                    valueRange = 0f..maxStartTime.toFloat().coerceAtLeast(0.0001f),
                    enabled = maxStartTime > 0 && !isProcessing,
                    colors = SliderDefaults.colors(
                        thumbColor = AppTheme.mint,
                        activeTrackColor = AppTheme.mint,
                        inactiveTrackColor = Color.White.copy(alpha = 0.22f),
                    ),
                )

                Text(
                    if (maxStartTime <= 0) {
                        L10n.string(
                            "The video is under 10 seconds and can be uploaded in full.",
                            "Видео короче 10 секунд, можно загрузить целиком.",
                        )
                    } else {
                        L10n.string(
                            "Move the slider to choose the start of the 10-second clip.",
                            "Передвиньте шкалу, чтобы выбрать начало 10-секундного фрагмента.",
                        )
                    },
                    style = AppText.caption,
                    color = Color.White.copy(alpha = 0.56f),
                )
            }

            PrimaryActionButton(
                title = if (isProcessing) {
                    L10n.string("Preparing video...", "Готовим видео...")
                } else {
                    L10n.string("Use clip", "Использовать фрагмент")
                },
                tint = AppTheme.court,
                enabled = !isProcessing,
                onClick = {
                    if (isProcessing) return@PrimaryActionButton
                    didSubmit = true
                    player.pause()
                    onConfirm(startTime)
                },
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.weight(1f))
        }

        if (isProcessing) {
            ProfileMediaProgressOverlay(
                title = L10n.string("Uploading video", "Видео загружается"),
                subtitle = L10n.string(
                    "Saving the selected clip to your profile.",
                    "Сохраняем выбранный фрагмент в карточку.",
                ),
            )
        }
    }
}

/** Port of `private var trimTimeline`. */
@Composable
private fun TrimTimeline(duration: Double, startTime: Double, selectedDuration: Double) {
    val total = maxOf(duration, 0.1)
    BoxWithConstraints(
        modifier = Modifier.fillMaxWidth().height(20.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        val width = maxWidth
        val selectedWidth = width * (selectedDuration / total).toFloat()
        val selectedOffset = width * (startTime / total).toFloat()

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(16.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.22f)),
        )

        Box(
            modifier = Modifier
                .offset(x = minOf(selectedOffset, maxOf(width - selectedWidth, 0.dp)))
                .width(maxOf(selectedWidth, 22.dp))
                .height(16.dp)
                .clip(CircleShape)
                .background(AppTheme.mint),
        )
    }
}

/** Port of `formatTime(_:)` - `m:ss`, floored. */
private fun formatClipTime(seconds: Double): String {
    val total = maxOf(seconds.toInt(), 0)
    return "%d:%02d".format(total / 60, total % 60)
}
