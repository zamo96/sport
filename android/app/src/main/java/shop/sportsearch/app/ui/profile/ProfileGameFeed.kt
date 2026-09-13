package shop.sportsearch.app.ui.profile

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
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.ReportPhotoGalleryItem
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct ProfileGameFeedSection`. */
@Composable
fun ProfileGameFeedSection(
    items: List<ProfileGameFeedItem>,
    currentUserId: String?,
    isLoading: Boolean,
    gameError: String?,
    visitError: String?,
    onRetryGames: () -> Unit,
    onRetryVisits: () -> Unit,
    onOpenGallery: (ReportPhotoGalleryItem) -> Unit,
) {
    ProfileDarkPanel {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(L10n.string("Game feed", "Лента игр"), style = AppText.headlineBold, color = Color.White)
                    Text(
                        L10n.string(
                            "Games and your personal visit reports",
                            "Игры и фотоотчёты твоих личных визитов",
                        ),
                        style = AppText.captionSemibold,
                        color = Color.White.copy(alpha = 0.58f),
                    )
                }
                Spacer(Modifier.weight(1f))
                if (isLoading) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                } else if (items.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(AppTheme.court.copy(alpha = 0.14f))
                            .padding(horizontal = 9.dp, vertical = 5.dp),
                    ) {
                        Text("${items.size}", style = AppText.captionBold, color = AppTheme.court)
                    }
                }
            }

            gameError?.let { SourceError(it, isLoading, onRetryGames) }
            visitError?.let { SourceError(it, isLoading, onRetryVisits) }

            if (items.isEmpty() && !isLoading && gameError == null && visitError == null) {
                Text(
                    L10n.string(
                        "Completed games and photo reports from your personal visits will appear here.",
                        "Здесь появятся завершённые игры и фотоотчёты твоих личных визитов.",
                    ),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.62f),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(continuousShape(18.dp))
                        .background(Color.White.copy(alpha = 0.055f))
                        .padding(14.dp),
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items.forEach { item ->
                    ProfileGameFeedRow(item = item, currentUserId = currentUserId, onOpenGallery = onOpenGallery)
                }
            }
        }
    }
}

@Composable
private fun SourceError(message: String, isLoading: Boolean, onRetry: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(message, style = AppText.caption, color = Color.White.copy(alpha = 0.75f))
        Text(
            L10n.string("Try again", "Повторить"),
            style = AppText.subheadlineSemibold,
            color = AppTheme.court,
            modifier = Modifier
                .height(44.dp)
                .clickable(enabled = !isLoading, onClick = onRetry)
                .padding(vertical = 12.dp),
        )
    }
}

/** Port of `struct ProfileGameFeedRow`. */
@Composable
private fun ProfileGameFeedRow(
    item: ProfileGameFeedItem,
    currentUserId: String?,
    onOpenGallery: (ReportPhotoGalleryItem) -> Unit,
) {
    val sport = when (item) {
        is ProfileGameFeedItem.Game -> item.request.sport
        is ProfileGameFeedItem.Visit -> item.activity.sport
    }
    val photoPaths = when (item) {
        is ProfileGameFeedItem.Game -> item.request.report?.photoUrls.orEmpty()
        is ProfileGameFeedItem.Visit -> item.activity.photoUrls
    }
    val dateTitle = when (item) {
        is ProfileGameFeedItem.Game -> item.request.proposedDatetime.formattedDateTime()
        is ProfileGameFeedItem.Visit -> item.activity.scheduledAt.formattedDateTime()
    }
    val details = when (item) {
        is ProfileGameFeedItem.Game -> listOfNotNull(
            item.request.proposedCourt?.name,
            item.request.participantNamesLine(currentUserId),
        ).filter { it.isNotEmpty() }.joinToString(" · ")
        is ProfileGameFeedItem.Visit -> listOfNotNull(
            L10n.string("Personal visit", "Личный визит"),
            item.activity.court?.name,
        ).joinToString(" · ")
    }
    val statusTitle = when (item) {
        is ProfileGameFeedItem.Game -> item.request.report?.statusTitle ?: item.request.outcomeLabel.orEmpty()
        is ProfileGameFeedItem.Visit -> L10n.string("Visit photo report", "Фотоотчёт визита")
    }
    val statusColor = when (item) {
        is ProfileGameFeedItem.Game ->
            if (item.request.report?.status?.lowercase()?.let { it != "confirmed" } == true) {
                Color(0xFFFF9800)
            } else {
                AppTheme.court
            }
        is ProfileGameFeedItem.Visit -> AppTheme.court
    }
    val comment = when (item) {
        is ProfileGameFeedItem.Game -> item.request.report?.comment
        is ProfileGameFeedItem.Visit -> item.activity.reportComment
    }

    fun openPhoto(index: Int) {
        if (photoPaths.isEmpty()) return
        onOpenGallery(
            ReportPhotoGalleryItem(
                photoPaths = photoPaths,
                initialIndex = index,
                title = L10n.string("Photo report", "Фотоотчёт"),
                subtitle = "${sport.title} · $dateTitle · $statusTitle",
                comment = comment,
            ),
        )
    }

    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.055f))
            .border(1.dp, Color.White.copy(alpha = 0.07f), shape)
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        ProfileGameFeedPreview(allPhotoPaths = photoPaths, sport = sport, onOpenPhoto = ::openPhoto)

        Column(
            modifier = Modifier
                .weight(1f)
                .clickable(enabled = photoPaths.isNotEmpty()) { openPhoto(0) },
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SportIconView(sport = sport, color = AppTheme.court, size = 16.dp)
                Text(
                    "${sport.title} · $dateTitle",
                    style = AppText.subheadlineSemibold,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                details,
                style = AppText.captionSemibold,
                color = Color.White.copy(alpha = 0.62f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(statusTitle, style = AppText.captionBold, color = statusColor)
            if (photoPaths.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.PhotoLibrary,
                        null,
                        tint = Color.White.copy(alpha = 0.72f),
                        modifier = Modifier.size(12.dp),
                    )
                    Text(
                        L10n.string("${photoPaths.size} photos", "${photoPaths.size} фото"),
                        style = AppText.captionBold,
                        color = Color.White.copy(alpha = 0.72f),
                    )
                }
            }
        }
    }
}

/** Port of `struct ProfileGameFeedPreview` - a 1/2/3/4-up collage. */
@Composable
private fun ProfileGameFeedPreview(allPhotoPaths: List<String>, sport: Sport, onOpenPhoto: (Int) -> Unit) {
    val photoPaths = allPhotoPaths.take(4)
    val extra = maxOf(allPhotoPaths.size - 4, 0)
    val shape = continuousShape(16.dp)

    Box(
        modifier = Modifier.size(76.dp).clip(shape).background(AppTheme.court.copy(alpha = 0.16f)),
        contentAlignment = Alignment.Center,
    ) {
        when (photoPaths.size) {
            0 -> SportIconView(sport = sport, color = AppTheme.court, size = 24.dp)

            1 -> PhotoTile(photoPaths[0], 0, extra > 0, extra, sport, onOpenPhoto, Modifier.fillMaxSize())

            2 -> Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                PhotoTile(photoPaths[0], 0, false, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxSize())
                PhotoTile(photoPaths[1], 1, extra > 0, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxSize())
            }

            3 -> Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                PhotoTile(photoPaths[0], 0, false, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxSize())
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    PhotoTile(photoPaths[1], 1, false, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxWidth())
                    PhotoTile(photoPaths[2], 2, extra > 0, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxWidth())
                }
            }

            else -> Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(modifier = Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    PhotoTile(photoPaths[0], 0, false, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxSize())
                    PhotoTile(photoPaths[1], 1, false, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxSize())
                }
                Row(modifier = Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    PhotoTile(photoPaths[2], 2, false, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxSize())
                    PhotoTile(photoPaths[3], 3, extra > 0, extra, sport, onOpenPhoto, Modifier.weight(1f).fillMaxSize())
                }
            }
        }
    }
}

@Composable
private fun PhotoTile(
    path: String,
    index: Int,
    showsMoreOverlay: Boolean,
    extraCount: Int,
    sport: Sport,
    onOpenPhoto: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.clickable { onOpenPhoto(index) }, contentAlignment = Alignment.Center) {
        val url = resolveAppRemoteUrl(path)
        if (url != null) {
            AsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            SportIconView(sport = sport, color = AppTheme.court, size = 20.dp)
        }

        if (showsMoreOverlay) {
            Box(
                modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)),
                contentAlignment = Alignment.Center,
            ) {
                Text("+$extraCount", fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.White)
            }
        }
    }
}

/** Port of `struct ProfileCompletenessCard`. */
@Composable
fun ProfileCompletenessCard(percent: Int, missingSteps: List<String>, hasVideoBonus: Boolean) {
    ProfileDarkPanel {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        L10n.string("Profile completion", "Заполненность профиля"),
                        style = AppText.headlineBold,
                        color = Color.White,
                    )
                    Text(
                        if (missingSteps.isEmpty()) {
                            L10n.string("Profile is ready to be shown", "Профиль готов к показу")
                        } else {
                            L10n.string(
                                "Steps remaining: ${missingSteps.size}",
                                "Осталось шагов: ${missingSteps.size}",
                            )
                        },
                        style = AppText.captionSemibold,
                        color = Color.White.copy(alpha = 0.58f),
                    )
                }
                Spacer(Modifier.weight(1f))
                Text("$percent%", style = AppText.title2Bold, color = AppTheme.mint)
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(7.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.09f)),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(percent / 100f)
                        .height(7.dp)
                        .clip(CircleShape)
                        .background(
                            androidx.compose.ui.graphics.Brush.horizontalGradient(
                                listOf(AppTheme.court, Color(0xFF4CAF50)),
                            ),
                        ),
                )
            }

            if (missingSteps.isEmpty()) {
                Text(
                    L10n.string("All required steps are complete", "Все обязательные шаги выполнены"),
                    style = AppText.subheadlineSemibold,
                    color = AppTheme.mint,
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    missingSteps.forEach { step ->
                        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.Top) {
                            Box(
                                modifier = Modifier
                                    .padding(top = 4.dp)
                                    .size(8.dp)
                                    .clip(CircleShape)
                                    .border(1.5.dp, AppTheme.mint, CircleShape),
                            )
                            Text(
                                step,
                                style = AppText.captionSemibold,
                                color = Color.White.copy(alpha = 0.72f),
                            )
                        }
                    }
                }
            }

            Text(
                if (hasVideoBonus) {
                    L10n.string("Video added as a profile bonus", "Видео добавлено как бонус к карточке")
                } else {
                    L10n.string(
                        "Video is a bonus and does not affect completion",
                        "Видео: бонус, который не влияет на заполненность",
                    )
                },
                style = AppText.captionSemibold,
                color = if (hasVideoBonus) AppTheme.mint else Color.White.copy(alpha = 0.52f),
            )
        }
    }
}
