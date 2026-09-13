package shop.sportsearch.app.ui.discover

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.bookingLinkUrl
import shop.sportsearch.app.core.displayTags
import shop.sportsearch.app.core.localizedDistrictName
import shop.sportsearch.app.core.sportsTitle
import shop.sportsearch.app.core.websiteLinkUrl
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.courts.CourtImageTile
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape

/** `Color(red: 48/255, green: 214/255, blue: 147/255)` — the sheet's accent. */
private val CourtAccent = Color(0xFF30D693)

/** Port of `private struct UpcomingCourtDetailSheet`. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun UpcomingCourtDetailSheet(court: Court, onDismiss: () -> Unit) {
    DismissOnSystemBack(onDismiss)
    val androidContext = LocalContext.current
    val haptics = rememberAppHaptics()
    val imageSize = minOf(LocalConfiguration.current.screenWidthDp - 36, 380).dp

    val placeLine = listOfNotNull(
        court.metroDisplayName,
        localizedDistrictName(court.district),
        court.distanceLabel,
    ).filter { it.isNotEmpty() }.joinToString(" · ")

    // `mapURL` - the club's own Yandex Maps link, else a generic geo: query.
    val mapUrl = court.yandexMapsUrl
        ?: "geo:${court.locationLat},${court.locationLng}?q=${android.net.Uri.encode(court.name)}"

    fun open(url: String?) {
        val target = url ?: return
        runCatching { androidContext.startActivity(Intent(Intent.ACTION_VIEW, target.toUri())) }
        haptics.selection()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color.Black, Color(0xFF040D0D), Color(0xFF0A1C18)),
                ),
            )
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 18.dp, bottom = 36.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    court.name,
                    fontFamily = appFontFamily,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    court.sportsTitle(null),
                    fontFamily = appFontFamily,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = CourtAccent,
                )
            }

            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.10f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = L10n.string("Close", "Закрыть"),
                    tint = Color.White,
                    modifier = Modifier.size(15.dp),
                )
            }
        }

        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            CourtImageTile(court, imageSize)
        }

        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (placeLine.isNotEmpty()) {
                CourtInfoRow(Icons.Outlined.Place, placeLine)
            }
            CourtInfoRow(Icons.Filled.MyLocation, court.address)
            court.workingHours?.takeIf { it.isNotEmpty() }?.let { CourtInfoRow(Icons.Filled.Schedule, it) }
            court.rating?.let { CourtInfoRow(Icons.Filled.Star, String.format("%.1f", it)) }
        }

        if (court.displayTags.isNotEmpty()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                court.displayTags.forEach { tag ->
                    Text(
                        tag,
                        modifier = Modifier
                            .height(30.dp)
                            .clip(RoundedCornerShape(percent = 50))
                            .background(Color.White.copy(alpha = 0.08f))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        fontFamily = appFontFamily,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.84f),
                    )
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CourtActionButton(L10n.string("Directions", "Маршрут"), Icons.Filled.Map, mapUrl, Modifier.weight(1f), ::open)
            CourtActionButton(L10n.string("Call", "Позвонить"), Icons.Filled.Call, court.dialUri, Modifier.weight(1f), ::open)
        }

        if (court.bookingLinkUrl != null || court.websiteLinkUrl != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CourtActionButton(
                    L10n.string("Book", "Бронь"),
                    Icons.Filled.CalendarMonth,
                    court.bookingLinkUrl,
                    Modifier.weight(1f),
                    ::open,
                )
                CourtActionButton(
                    L10n.string("Website", "Сайт"),
                    Icons.Filled.Language,
                    court.websiteLinkUrl,
                    Modifier.weight(1f),
                    ::open,
                )
            }
        }
    }
}

@Composable
private fun CourtInfoRow(icon: ImageVector, title: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(continuousShape(9.dp))
                .background(Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = CourtAccent, modifier = Modifier.size(14.dp))
        }

        Text(
            title,
            fontFamily = appFontFamily,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.78f),
        )
    }
}

@Composable
private fun CourtActionButton(
    title: String,
    icon: ImageVector,
    url: String?,
    modifier: Modifier = Modifier,
    onOpen: (String?) -> Unit,
) {
    val isEnabled = url != null
    val foreground = if (isEnabled) Color.White else Color.White.copy(alpha = 0.32f)
    Row(
        modifier = modifier
            .height(46.dp)
            .clip(continuousShape(16.dp))
            .background(if (isEnabled) AppTheme.court else Color.White.copy(alpha = 0.06f))
            .clickable(enabled = isEnabled) { onOpen(url) },
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(16.dp))
        Text(
            title,
            fontFamily = appFontFamily,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = foreground,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
