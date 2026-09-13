package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.displayName
import shop.sportsearch.app.core.formatTitle
import shop.sportsearch.app.core.isOnline
import shop.sportsearch.app.ui.components.AutoSizeText
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.searches.SheetHeader
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct ActiveHotSearchMapCard`. */
@Composable
fun ActiveHotSearchMapCard(
    item: ActiveHotSearchItem,
    responseStatus: String?,
    responseId: String?,
    modifier: Modifier = Modifier,
    onOpenUser: () -> Unit,
    onOpenCourt: (Court) -> Unit,
    onOpenApprovedChat: () -> Unit,
    onAction: () -> Unit,
) {
    val canOpenApprovedChat = responseStatus == "approved" &&
        (item.search.playersNeeded > 1 || item.search.regularPair?.id != null)

    val actionTitle = when (responseStatus) {
        "pending" -> L10n.string("Cancel", "Отменить")
        "approved" -> if (canOpenApprovedChat) {
            L10n.string("Open chat", "Открыть чат")
        } else {
            L10n.string("Response accepted", "Отклик принят")
        }
        "rejected" -> L10n.string("Response declined", "Отклик отклонён")
        else -> L10n.string("Respond", "Откликнуться")
    }

    val isActionDisabled = responseStatus == "rejected" ||
        (responseStatus == "pending" && responseId == null) ||
        (responseStatus == "approved" && !canOpenApprovedChat)

    val shape = continuousShape(22.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .appShadow(Color.Black.copy(alpha = 0.28f), 20.dp, 0.dp, 10.dp, shape)
            .clip(shape)
            .background(Color.Black.copy(alpha = 0.76f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(modifier = Modifier.clickable(onClick = onOpenUser)) {
                RemoteAvatarView(name = item.user.displayName, path = item.user.avatarUrl, size = 48.dp)
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(if (item.user.isOnline) Color.Green else Color.White.copy(alpha = 0.52f))
                        .border(2.dp, Color.Black.copy(alpha = 0.72f), CircleShape),
                )
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                AutoSizeText(
                    text = item.user.age?.let { "${item.user.displayName}, $it" } ?: item.user.displayName,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    minScale = 0.78f,
                )
                AutoSizeText(
                    text = "${item.search.sport.title} · " +
                        item.search.sport.formatTitle(item.search.format, item.search.playersNeeded),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppTheme.court,
                    maxLines = 1,
                    minScale = 0.78f,
                )
            }

            Text(
                item.playersTitle,
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White.copy(alpha = 0.78f),
                maxLines = 1,
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            MapCardLabel(Icons.Filled.CalendarMonth, item.timeTitle, Modifier.weight(1f, fill = false))

            val court = item.search.preferredCourt
            MapCardLabel(
                Icons.Outlined.Place,
                item.venueTitle,
                if (court != null) {
                    Modifier.weight(1f, fill = false).clickable { onOpenCourt(court) }
                } else {
                    Modifier.weight(1f, fill = false)
                },
            )
        }

        Text(
            actionTitle,
            modifier = Modifier
                .fillMaxWidth()
                .height(44.dp)
                .alpha(if (isActionDisabled) 0.62f else 1f)
                .clip(RoundedCornerShape(percent = 50))
                .background(AppTheme.court)
                .clickable(enabled = !isActionDisabled) {
                    if (canOpenApprovedChat) onOpenApprovedChat() else onAction()
                }
                .padding(top = 11.dp),
            fontFamily = appFontFamily,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = Color.Black,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

@Composable
private fun MapCardLabel(icon: ImageVector, text: String, modifier: Modifier = Modifier) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.66f), modifier = Modifier.size(13.dp))
        Text(
            text,
            fontFamily = appFontFamily,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.66f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Port of `struct ActiveHotSearchClusterPickerSheet`. */
@Composable
fun ActiveHotSearchClusterPickerSheet(
    items: List<ActiveHotSearchItem>,
    onDismiss: () -> Unit,
    onSelect: (String) -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    Box(modifier = Modifier.fillMaxWidth().background(AppTheme.ink)) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                SheetHeader(
                    title = L10n.string("Searches in this area", "Поиски в этом месте"),
                    onClose = onDismiss,
                )
            }

            items(items.size) { index ->
                val entry = items[index]
                val shape = continuousShape(18.dp)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(shape)
                        .background(Color.White.copy(alpha = 0.07f))
                        .border(1.dp, Color.White.copy(alpha = 0.09f), shape)
                        .clickable { onSelect(entry.id) }
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RemoteAvatarView(name = entry.user.displayName, path = entry.user.avatarUrl, size = 50.dp)

                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(
                            entry.user.age?.let { "${entry.user.displayName}, $it" } ?: entry.user.displayName,
                            fontFamily = appFontFamily,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            "${entry.search.sport.title} · ${entry.timeTitle}",
                            fontFamily = appFontFamily,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = AppTheme.court,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        MapCardLabel(Icons.Outlined.Place, entry.venueTitle)
                    }

                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.42f),
                        modifier = Modifier.size(13.dp),
                    )
                }
            }
        }
    }
}
