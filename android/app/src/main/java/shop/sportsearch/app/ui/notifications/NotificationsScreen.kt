package shop.sportsearch.app.ui.notifications

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Verified
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.EmptyStateView
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `struct NotificationsView` in ios/TennisSearchIOS/Views/NotificationsView.swift.
 * The Swift original hard-codes Russian here, so the strings stay Russian on both clients.
 */
@Composable
fun NotificationsScreen(appModel: AppViewModel, onBack: () -> Unit) {
    DismissOnSystemBack(onBack)
    HideBottomBarWhileVisible(appModel)

    var notifications by remember { mutableStateOf<List<AppNotification>>(emptyList()) }
    var collapsedGroups by remember { mutableStateOf<Set<AppNotificationType>>(emptySet()) }

    LaunchedEffect(Unit) {
        notifications = runCatching { appModel.repository.fetchNotifications() }.getOrDefault(emptyList())
        runCatching { appModel.repository.markNotificationsSeen() }
        appModel.refreshActivitySummary()
    }

    // The Swift version fixes the group order rather than using dictionary order.
    val order = listOf(
        AppNotificationType.NEW_MESSAGE,
        AppNotificationType.NEW_MATCH,
        AppNotificationType.INCOMING_LIKE,
        AppNotificationType.SEARCH_RESPONSE,
        AppNotificationType.APPLICATION_RESULT,
        AppNotificationType.HOT_EVENT,
    )
    val grouped = order.mapNotNull { type ->
        notifications.filter { it.type == type }.takeIf { it.isNotEmpty() }?.let { type to it }
    }

    Column(modifier = Modifier.fillMaxSize().background(Color.Black).statusBarsPadding()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier.size(44.dp).clickable(onClick = onBack),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    null,
                    tint = Color.White,
                    modifier = Modifier.size(20.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            Text("Уведомления", style = AppText.headline, color = Color.White)
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(44.dp))
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                SectionCard(
                    title = "Уведомления",
                    subtitle = "Новые мэтчи, сообщения, входящие симпатии, отклики и срочные события.",
                ) {
                    val unread = appModel.activitySummary.inboxBadgeCount
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppInlineChip(
                            text = "Уведомления включены",
                            tint = AppTheme.mint,
                            foreground = AppTheme.court,
                        )
                        if (unread > 0) {
                            AppInlineChip(
                                text = "Новых: $unread",
                                tint = AppTheme.cream,
                                foreground = AppTheme.ink,
                            )
                        }
                    }
                }
            }

            if (grouped.isEmpty()) {
                item {
                    SectionCard(
                        title = "Пока всё спокойно",
                        subtitle = "Когда появятся новые события, они будут собраны здесь по разделам.",
                    ) {
                        EmptyStateView(
                            title = "Новых уведомлений нет",
                            subtitle = "Здесь появятся сообщения, мэтчи, входящие лайки и изменения по твоим поискам.",
                        ) {
                            Icon(
                                Icons.Filled.NotificationsOff,
                                null,
                                tint = AppTheme.court,
                                modifier = Modifier.size(28.dp),
                            )
                        }
                    }
                }
            } else {
                grouped.forEach { (type, items) ->
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth().clickable {
                                collapsedGroups = if (collapsedGroups.contains(type)) {
                                    collapsedGroups - type
                                } else {
                                    collapsedGroups + type
                                }
                            },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(groupTitle(type), style = AppText.title3Bold, color = Color.White)
                            Spacer(Modifier.weight(1f))
                            AppInlineChip(
                                text = "${items.size}",
                                tint = Color.White.copy(alpha = 0.12f),
                                foreground = Color.White.copy(alpha = 0.82f),
                            )
                            Icon(
                                if (collapsedGroups.contains(type)) Icons.Filled.ExpandMore else Icons.Filled.ExpandLess,
                                null,
                                tint = Color.White.copy(alpha = 0.52f),
                                modifier = Modifier.size(14.dp),
                            )
                        }
                    }

                    if (!collapsedGroups.contains(type)) {
                        items(items.size) { index ->
                            val item = items[index]
                            NotificationGroupCard(item = item, groupTitle = groupTitle(type)) {
                                AppNavigationTarget.fromNotificationHref(item.href)?.let { target ->
                                    appModel.navigate(target)
                                    onBack()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun groupTitle(type: AppNotificationType): String = when (type) {
    AppNotificationType.NEW_MATCH -> "Новые мэтчи"
    AppNotificationType.NEW_MESSAGE -> "Новые сообщения"
    AppNotificationType.INCOMING_LIKE -> "Хотят с тобой сыграть"
    AppNotificationType.SEARCH_RESPONSE -> "Новые отклики"
    AppNotificationType.APPLICATION_RESULT -> "Решения по заявкам"
    AppNotificationType.HOT_EVENT -> "Срочные события"
}

/** Port of `struct NotificationGroupCard`. */
@Composable
private fun NotificationGroupCard(item: AppNotification, groupTitle: String, onClick: () -> Unit) {
    val isRejected = item.type == AppNotificationType.APPLICATION_RESULT && item.status == "rejected"

    val groupTint = when {
        isRejected -> Color(red = 1.0f, green = 0.36f, blue = 0.34f)
        item.type == AppNotificationType.NEW_MATCH -> Color(red = 0.96f, green = 0.48f, blue = 0.52f)
        item.type == AppNotificationType.NEW_MESSAGE -> Color(red = 0.42f, green = 0.72f, blue = 1.0f)
        item.type == AppNotificationType.INCOMING_LIKE -> AppTheme.court
        item.type == AppNotificationType.SEARCH_RESPONSE -> Color(red = 0.97f, green = 0.65f, blue = 0.29f)
        item.type == AppNotificationType.APPLICATION_RESULT -> Color(red = 0.48f, green = 0.86f, blue = 0.60f)
        else -> Color(red = 1.0f, green = 0.42f, blue = 0.34f)
    }

    val groupIcon: ImageVector = when (item.type) {
        AppNotificationType.NEW_MATCH -> Icons.Filled.Favorite
        AppNotificationType.NEW_MESSAGE -> Icons.AutoMirrored.Filled.Message
        AppNotificationType.INCOMING_LIKE -> Icons.Filled.AutoAwesome
        AppNotificationType.SEARCH_RESPONSE -> Icons.AutoMirrored.Filled.Send
        AppNotificationType.APPLICATION_RESULT -> Icons.Filled.Verified
        else -> Icons.Filled.LocalFireDepartment
    }

    val ctaLabel = when {
        item.type == AppNotificationType.APPLICATION_RESULT && item.status == "approved" ->
            if (item.href.startsWith("/inbox/")) "Открыть чат" else "Открыть событие"
        item.type == AppNotificationType.INCOMING_LIKE -> "Открыть игрока"
        item.type == AppNotificationType.NEW_MATCH -> "Перейти в чат"
        item.type == AppNotificationType.NEW_MESSAGE -> "Открыть переписку"
        else -> null
    }

    val gradient = if (isRejected) {
        listOf(Color.Red.copy(alpha = 0.22f), Color.Red.copy(alpha = 0.10f))
    } else {
        listOf(Color.White.copy(alpha = 0.10f), Color.White.copy(alpha = 0.05f))
    }

    val shape = continuousShape(26.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Brush.linearGradient(gradient))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(continuousShape(18.dp))
                    .background(groupTint.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(groupIcon, null, tint = groupTint, modifier = Modifier.size(18.dp))
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(item.title, style = AppText.headline, color = Color.White)
                Text(item.description, style = AppText.subheadline, color = Color.White.copy(alpha = 0.74f))
                ctaLabel?.let {
                    Text(
                        it,
                        style = AppText.captionSemibold,
                        color = groupTint,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }

            Icon(
                Icons.Filled.ChevronRight,
                null,
                tint = Color.White.copy(alpha = 0.36f),
                modifier = Modifier.padding(top = 4.dp).size(13.dp),
            )
        }

        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                groupTitle.uppercase(),
                style = AppText.captionSemibold.copy(letterSpacing = 1.6.sp),
                color = groupTint,
            )
            Spacer(Modifier.weight(1f))
            Text(
                item.createdAt.formattedDateTime(),
                style = AppText.caption,
                color = Color.White.copy(alpha = 0.48f),
            )
        }
    }
}
