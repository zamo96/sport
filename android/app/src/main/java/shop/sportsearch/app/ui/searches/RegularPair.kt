package shop.sportsearch.app.ui.searches

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct RegularPairCard` in ios/TennisSearchIOS/Views/SearchesView.swift. */
@Composable
fun RegularPairCard(
    regularPair: RegularPairSummary,
    currentUserId: String?,
    upcomingOccurrences: List<RegularPairOccurrence>,
    updatingOccurrenceID: String?,
    onOpenChat: () -> Unit,
    onConfirmOccurrence: (RegularPairOccurrence) -> Unit,
    onDeclineOccurrence: (RegularPairOccurrence) -> Unit,
    onEditOccurrence: (RegularPairOccurrence) -> Unit,
) {
    val visibleOccurrences = upcomingOccurrences.take(4)
    val shape = continuousShape(24.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.58f))
            .border(1.dp, AppTheme.mint.copy(alpha = 0.9f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            RemoteAvatarView(
                name = regularPair.partnerUser.displayName,
                path = regularPair.partnerUser.avatarUrl,
                size = 52.dp,
            )

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    L10n.string("Recurring pair is active", "Регулярная пара активна").uppercase(),
                    style = AppText.captionSemibold.copy(letterSpacing = 1.6.sp),
                    color = AppTheme.court,
                )
                Text(regularPair.partnerUser.displayName, style = AppText.headline, color = AppTheme.ink)
                regularPair.preferredCourt?.name?.let { courtName ->
                    Text(
                        courtName,
                        style = AppText.footnote,
                        color = AppTheme.ink.copy(alpha = 0.62f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            Box(
                modifier = Modifier.size(42.dp).clip(CircleShape).background(AppTheme.ink).clickable(onClick = onOpenChat),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Message,
                    contentDescription = L10n.string("Open chat", "Открыть чат"),
                    tint = Color.White,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        if (visibleOccurrences.isEmpty()) {
            Text(
                L10n.string(
                    "The pair is created, but upcoming slots haven't appeared yet. " +
                        "Check the days and times in search settings.",
                    "Пара создана, но ближайшие слоты пока не появились. " +
                        "Проверь дни и время в параметрах поиска.",
                ),
                style = AppText.footnote,
                color = AppTheme.ink.copy(alpha = 0.68f),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(18.dp))
                    .background(Color.White.copy(alpha = 0.62f))
                    .padding(12.dp),
            )
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L10n.string("Upcoming time slots", "Ближайшие слоты").uppercase(),
                        style = AppText.captionSemibold.copy(letterSpacing = 1.6.sp),
                        color = AppTheme.court,
                    )
                    Spacer(Modifier.weight(1f))
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(AppTheme.court)
                            .padding(horizontal = 8.dp, vertical = 5.dp),
                    ) {
                        Text("${upcomingOccurrences.size}", style = AppText.captionBold, color = Color.White)
                    }
                }

                visibleOccurrences.forEach { occurrence ->
                    RegularOccurrenceRow(
                        occurrence = occurrence,
                        currentUserId = currentUserId,
                        partnerUserId = regularPair.partnerUser.id,
                        isUpdating = updatingOccurrenceID == occurrence.id,
                        onConfirm = { onConfirmOccurrence(occurrence) },
                        onDecline = { onDeclineOccurrence(occurrence) },
                        onEdit = { onEditOccurrence(occurrence) },
                    )
                }

                if (upcomingOccurrences.size > visibleOccurrences.size) {
                    val extra = upcomingOccurrences.size - visibleOccurrences.size
                    Text(
                        L10n.string(
                            "$extra more slots are available in the recurring pair.",
                            "Ещё $extra слота доступны в регулярной паре.",
                        ),
                        style = AppText.footnote,
                        color = AppTheme.ink.copy(alpha = 0.6f),
                    )
                }
            }
        }
    }
}

/** Port of `struct RegularOccurrenceRow`. */
@Composable
private fun RegularOccurrenceRow(
    occurrence: RegularPairOccurrence,
    currentUserId: String?,
    partnerUserId: String,
    isUpdating: Boolean,
    onConfirm: () -> Unit,
    onDecline: () -> Unit,
    onEdit: () -> Unit,
) {
    fun confirmationStatus(userId: String?): String? =
        userId?.let { id -> occurrence.confirmations.firstOrNull { it.user.id == id }?.status?.lowercase() }

    fun confirmationLabel(userId: String?): String = when (confirmationStatus(userId)) {
        "confirmed" -> L10n.string("Confirmed", "Подтверждено")
        "declined" -> L10n.string("Can't make it", "Не смогу")
        else -> L10n.string("Awaiting confirmation", "Ждет подтверждения")
    }

    fun confirmationColor(userId: String?): Color = when (confirmationStatus(userId)) {
        "confirmed" -> AppTheme.court
        "declined" -> Color.Red.copy(alpha = 0.9f)
        else -> AppTheme.ink.copy(alpha = 0.72f)
    }

    val myStatus = confirmationStatus(currentUserId)
    val shouldShowDecisionBar = myStatus == null || myStatus !in setOf("confirmed", "declined")

    val declinedUserId = occurrence.confirmations.firstOrNull { it.status.lowercase() == "declined" }?.user?.id
    val status = when (occurrence.status.lowercase()) {
        "confirmed" -> Triple(L10n.string("Confirmed", "Подтверждено"), AppTheme.court, AppTheme.mint)
        "declined" -> if (currentUserId != null && declinedUserId == currentUserId) {
            Triple(L10n.string("You declined", "Ты отказался"), Color.Red.copy(alpha = 0.9f), Color.Red.copy(alpha = 0.12f))
        } else {
            Triple(
                L10n.string("Partner can't make it", "Партнер не может"),
                Color.Red.copy(alpha = 0.9f),
                Color.Red.copy(alpha = 0.12f),
            )
        }
        "canceled", "cancelled" -> Triple(
            L10n.string("Cancelled", "Отменено"),
            AppTheme.ink.copy(alpha = 0.72f),
            Color.Gray.copy(alpha = 0.18f),
        )
        "expired" -> Triple(
            L10n.string("Past", "Уже прошло"),
            AppTheme.ink.copy(alpha = 0.72f),
            Color.Gray.copy(alpha = 0.18f),
        )
        else -> Triple(L10n.string("Awaiting confirmation", "Ждет подтверждения"), AppTheme.ink, AppTheme.cream)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(18.dp))
            .background(Color.White.copy(alpha = 0.68f))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    occurrence.scheduledAt.formattedNumericDateTime(),
                    style = AppText.subheadlineSemibold,
                    color = AppTheme.ink,
                )
                occurrence.proposedCourt?.name?.let {
                    Text(
                        it,
                        style = AppText.footnote,
                        color = AppTheme.ink.copy(alpha = 0.62f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            AppInlineChip(text = status.first, tint = status.third, foreground = status.second)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (shouldShowDecisionBar || isUpdating) {
                RegularOccurrenceDecisionBar(
                    isUpdating = isUpdating,
                    onConfirm = onConfirm,
                    onDecline = onDecline,
                    modifier = Modifier.weight(1f),
                )
            } else {
                Spacer(Modifier.weight(1f))
            }

            Box(
                modifier = Modifier
                    .width(44.dp)
                    .height(38.dp)
                    .clip(continuousShape(14.dp))
                    .background(AppTheme.creamLight)
                    .clickable(enabled = !isUpdating, onClick = onEdit),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Tune,
                    contentDescription = L10n.string(
                        "Change date, time, or club",
                        "Изменить дату, время или клуб",
                    ),
                    tint = AppTheme.ink,
                    modifier = Modifier.size(15.dp),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ConfirmationPill(
                L10n.string("You", "Ты"),
                confirmationLabel(currentUserId),
                confirmationColor(currentUserId),
                Modifier.weight(1f),
            )
            ConfirmationPill(
                L10n.string("Partner", "Партнер"),
                confirmationLabel(partnerUserId),
                confirmationColor(partnerUserId),
                Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun ConfirmationPill(title: String, value: String, valueColor: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(continuousShape(14.dp))
            .background(AppTheme.creamLight)
            .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = AppText.caption2Semibold, color = AppTheme.ink.copy(alpha = 0.52f))
        Text(value, style = AppText.footnote, color = valueColor, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Port of `struct RegularOccurrenceDecisionBar` - the buttons swap for a
 * confirmation label the moment you tap, before the server answers.
 */
@Composable
private fun RegularOccurrenceDecisionBar(
    isUpdating: Boolean,
    onConfirm: () -> Unit,
    onDecline: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var pendingAction by remember { mutableStateOf<String?>(null) }

    AnimatedContent(targetState = pendingAction, label = "decision", modifier = modifier) { pending ->
        if (pending != null) {
            val isConfirm = pending == "confirm"
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(38.dp)
                    .clip(continuousShape(14.dp))
                    .background(if (isConfirm) AppTheme.mint else Color.Red.copy(alpha = 0.12f)),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val tint = if (isConfirm) AppTheme.court else Color.Red.copy(alpha = 0.9f)
                if (isUpdating) {
                    CircularProgressIndicator(color = tint, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
                } else {
                    Icon(
                        if (isConfirm) Icons.Filled.Check else Icons.Filled.Close,
                        null,
                        tint = tint,
                        modifier = Modifier.size(14.dp),
                    )
                }
                Text(if (isConfirm) "Подтверждено" else "Отказ", style = AppText.footnote, color = tint)
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DecisionButton(Icons.Filled.Check, AppTheme.court, AppTheme.mint, Modifier.weight(1f)) {
                    pendingAction = "confirm"
                    onConfirm()
                }
                DecisionButton(
                    Icons.Filled.Close,
                    Color.Red.copy(alpha = 0.9f),
                    Color.Red.copy(alpha = 0.12f),
                    Modifier.weight(1f),
                ) {
                    pendingAction = "decline"
                    onDecline()
                }
            }
        }
    }
}

@Composable
private fun DecisionButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tint: Color,
    surface: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .height(38.dp)
            .clip(continuousShape(14.dp))
            .background(surface)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(15.dp))
    }
}
