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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.GameReport
import shop.sportsearch.app.data.TennisRepository
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme

/** Port of `struct GameReportViewerSheet` in UIComponents.swift. */
@Composable
fun GameReportViewerSheet(repository: TennisRepository, report: GameReport, onDismiss: () -> Unit) {
    DismissOnSystemBack(onDismiss)
    val photoUrls = report.photoUrls
    val pagerState = rememberPagerState(pageCount = { photoUrls.size })

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(top = 18.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Фотоотчёт", style = AppText.headlineBold, color = Color.White)
                Text(report.statusTitle, style = AppText.captionSemibold, color = AppTheme.mint)
            }

            Spacer(Modifier.weight(1f))

            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.10f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, null, tint = Color.White, modifier = Modifier.size(15.dp))
            }
        }

        if (photoUrls.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth().weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
            ) {
                Icon(
                    Icons.Filled.PhotoLibrary,
                    null,
                    tint = Color.White.copy(alpha = 0.74f),
                    modifier = Modifier.size(44.dp),
                )
                Text("Фото недоступны", style = AppText.headlineBold, color = Color.White.copy(alpha = 0.74f))
            }
        } else {
            HorizontalPager(state = pagerState, modifier = Modifier.fillMaxWidth().weight(1f)) { page ->
                RemoteChatMediaImage(
                    repository = repository,
                    path = photoUrls[page],
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                )
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.Black.copy(alpha = 0.82f))
                .navigationBarsPadding()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (photoUrls.isNotEmpty()) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${pagerState.currentPage + 1} / ${photoUrls.size}",
                        style = AppText.captionBold,
                        color = Color.White.copy(alpha = 0.78f),
                    )
                    Spacer(Modifier.weight(1f))
                    Icon(Icons.Filled.PhotoLibrary, null, tint = AppTheme.mint, modifier = Modifier.size(14.dp))
                }
            }

            report.comment?.takeIf { it.isNotEmpty() }?.let { comment ->
                Text(comment, style = AppText.subheadline, color = Color.White.copy(alpha = 0.82f))
            }
        }
    }
}
