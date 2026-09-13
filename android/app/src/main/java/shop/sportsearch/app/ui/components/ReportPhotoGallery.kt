package shop.sportsearch.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.ui.theme.AppText

/** Port of `struct ReportPhotoGalleryItem` in ios/.../ReportPhotoGallery.swift. */
data class ReportPhotoGalleryItem(
    val photoPaths: List<String>,
    val initialIndex: Int = 0,
    val title: String,
    val subtitle: String? = null,
    val comment: String? = null,
) {
    val clampedInitialIndex: Int
        get() = initialIndex.coerceIn(0, maxOf(photoPaths.size - 1, 0))
}

/** Port of `struct ReportPhotoGallerySheet`. */
@Composable
fun ReportPhotoGallerySheet(item: ReportPhotoGalleryItem, onDismiss: () -> Unit) {
    DismissOnSystemBack(onDismiss)
    val pagerState = rememberPagerState(
        initialPage = item.clampedInitialIndex,
        pageCount = { item.photoPaths.size },
    )
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier.fillMaxSize().background(Color.Black).statusBarsPadding(),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(item.title, style = AppText.headline, color = Color.White)
                item.subtitle?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = AppText.caption, color = Color.White.copy(alpha = 0.7f))
                }
            }

            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.1f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(17.dp))
            }
        }

        if (item.photoPaths.isEmpty()) {
            Box(modifier = Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                ReportGalleryUnavailableView()
            }
        } else {
            HorizontalPager(state = pagerState, modifier = Modifier.fillMaxWidth().weight(1f)) { page ->
                Box(
                    modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    SubcomposeAsyncImage(
                        model = resolveAppRemoteUrl(item.photoPaths[page]),
                        contentDescription = L10n.string(
                            "Photo ${page + 1} of ${item.photoPaths.size}",
                            "Фото ${page + 1} из ${item.photoPaths.size}",
                        ),
                        contentScale = ContentScale.Fit,
                        loading = {
                            Text(
                                L10n.string("Loading photo", "Загружаем фото"),
                                style = AppText.subheadline,
                                color = Color.White.copy(alpha = 0.7f),
                            )
                        },
                        error = { ReportGalleryUnavailableView() },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (item.photoPaths.isNotEmpty()) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    GalleryArrow(Icons.AutoMirrored.Filled.KeyboardArrowLeft, pagerState.currentPage > 0) {
                        scope.launch { pagerState.animateScrollToPage(maxOf(0, pagerState.currentPage - 1)) }
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        "${pagerState.currentPage + 1} / ${item.photoPaths.size}",
                        style = AppText.subheadlineSemibold,
                        color = Color.White,
                    )
                    Spacer(Modifier.weight(1f))
                    GalleryArrow(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        pagerState.currentPage < item.photoPaths.lastIndex,
                    ) {
                        scope.launch {
                            pagerState.animateScrollToPage(
                                minOf(item.photoPaths.lastIndex, pagerState.currentPage + 1),
                            )
                        }
                    }
                }
            }

            item.comment?.takeIf { it.trim().isNotEmpty() }?.let { comment ->
                Box(modifier = Modifier.heightIn(max = 120.dp).verticalScroll(rememberScrollState())) {
                    Text(comment, style = AppText.subheadline, color = Color.White, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun GalleryArrow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier.size(44.dp).clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            null,
            tint = Color.White.copy(alpha = if (enabled) 1f else 0.3f),
            modifier = Modifier.size(22.dp),
        )
    }
}

/** Port of `struct ReportGalleryUnavailableView`. */
@Composable
private fun ReportGalleryUnavailableView() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Filled.BrokenImage,
            null,
            tint = Color.White.copy(alpha = 0.75f),
            modifier = Modifier.size(34.dp),
        )
        Text(
            L10n.string("Photo unavailable", "Фото недоступно"),
            style = AppText.headline,
            color = Color.White.copy(alpha = 0.75f),
        )
    }
}
