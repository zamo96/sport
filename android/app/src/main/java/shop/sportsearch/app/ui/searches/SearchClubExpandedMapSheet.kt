package shop.sportsearch.app.ui.searches

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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.localizedDistrictName
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.resolveAppRemoteUrl
import shop.sportsearch.app.ui.maps.ClubsMapView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `struct SearchClubExpandedMapSheet` in
 * ios/TennisSearchIOS/Views/SearchesView.swift.
 *
 * The small map in the picker only previews a club; this is the full-screen
 * version where a marker tap previews and the mini card confirms.
 */
@Composable
fun SearchClubExpandedMapSheet(
    sport: Sport,
    courts: List<Court>,
    focusedCourt: Court?,
    selectedCourt: Court?,
    onPreview: (Court) -> Unit,
    onChoose: (Court) -> Unit,
    onDismiss: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)

    // `.onAppear { previewCourt = selectedCourt ?? focusedCourt }`
    var previewCourt by remember { mutableStateOf(selectedCourt ?: focusedCourt) }
    val activeCourt = previewCourt ?: selectedCourt ?: focusedCourt

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppTheme.cream)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Box(
            modifier = Modifier
                .padding(top = 10.dp)
                .align(Alignment.CenterHorizontally)
                .size(width = 48.dp, height = 6.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.1f)),
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 18.dp, end = 18.dp, top = 18.dp, bottom = 14.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    L10n.string("Club map", "Карта клубов"),
                    style = AppText.title2Bold,
                    color = AppTheme.ink,
                )
                Text(
                    L10n.string(
                        "Tap a marker to view and choose a club",
                        "Нажмите на значок, чтобы увидеть клуб и выбрать его",
                    ),
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.58f),
                )
            }

            Spacer(Modifier.width(8.dp))

            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.04f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = AppTheme.ink)
            }
        }

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(bottom = 18.dp),
            contentAlignment = Alignment.BottomCenter,
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(continuousShape(28.dp))
                    .border(1.dp, Color.Black.copy(alpha = 0.08f), continuousShape(28.dp)),
            ) {
                ClubsMapView(
                    courts = courts,
                    focusedCourtId = activeCourt?.id,
                    modifier = Modifier.fillMaxSize(),
                    onSelectCourt = { courtId ->
                        val court = courts.firstOrNull { it.id == courtId } ?: return@ClubsMapView
                        previewCourt = court
                        onPreview(court)
                    },
                )
            }

            activeCourt?.let { court ->
                MapSelectedCourtMiniCard(
                    court = court,
                    sport = sport,
                    modifier = Modifier.padding(14.dp),
                    onChoose = {
                        onChoose(court)
                        onDismiss()
                    },
                )
            }
        }
    }
}

/** Port of `private struct MapSelectedCourtMiniCard`. */
@Composable
fun MapSelectedCourtMiniCard(
    court: Court,
    sport: Sport,
    modifier: Modifier = Modifier,
    onChoose: () -> Unit,
) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppTheme.mint.copy(alpha = 0.72f))
            .border(1.dp, AppTheme.court.copy(alpha = 0.16f), shape)
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        MapCourtThumbnail(court = court, sport = sport, size = 66.dp)

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                court.name,
                style = AppText.subheadlineSemibold,
                color = AppTheme.ink,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                listOfNotNull(sport.title, court.metroDisplayName ?: localizedDistrictName(court.district))
                    .joinToString(" · "),
                style = AppText.caption,
                color = AppTheme.ink.copy(alpha = 0.58f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                court.address,
                style = AppText.caption2Semibold,
                color = AppTheme.ink.copy(alpha = 0.5f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Box(
            modifier = Modifier
                .height(38.dp)
                .clip(CircleShape)
                .background(AppTheme.ink)
                .clickable(onClick = onChoose)
                .padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                L10n.string("Choose", "Выбрать"),
                style = AppText.captionBold,
                color = Color.White,
            )
        }
    }
}

/** Port of `private struct MapCourtThumbnail`. */
@Composable
private fun MapCourtThumbnail(court: Court, sport: Sport, size: Dp) {
    val shape = continuousShape(16.dp)
    Box(
        modifier = Modifier.size(size).clip(shape),
        contentAlignment = Alignment.Center,
    ) {
        val url = resolveAppRemoteUrl(court.primaryPhotoUrl)
        if (url != null) {
            SubcomposeAsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                loading = { MapCourtThumbnailFallback(court, sport, size) },
                error = { MapCourtThumbnailFallback(court, sport, size) },
            )
        } else {
            MapCourtThumbnailFallback(court, sport, size)
        }
    }
}

@Composable
private fun MapCourtThumbnailFallback(court: Court, sport: Sport, size: Dp) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    listOf(AppTheme.court.copy(alpha = 0.82f), AppTheme.ink.copy(alpha = 0.88f)),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        SportIconView(
            sport = court.supportedSports.firstOrNull() ?: sport,
            color = Color.White.copy(alpha = 0.9f),
            size = size * 0.38f,
        )
    }
}
