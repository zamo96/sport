package shop.sportsearch.app.ui.searches

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.RegularPairOccurrence
import shop.sportsearch.app.core.TimeRange
import shop.sportsearch.app.core.formattedNumericDateTime
import shop.sportsearch.app.core.parseServerInstant
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.time.ZoneId

/** How many clubs the quick-pick row offers before the full editor is needed. */
private const val QUICK_COURT_LIMIT = 6

/**
 * Port of `private struct RegularPairOccurrenceCard`.
 *
 * Richer than [RegularPairCard]'s row: besides confirm and decline it carries
 * the quick controls the detail sheet needs - shift a day, snap to a time
 * range, swap the club.
 */
@Composable
fun RegularPairOccurrenceDetailCard(
    occurrence: RegularPairOccurrence,
    partnerName: String,
    courts: List<Court>,
    currentUserId: String?,
    isUpdating: Boolean,
    onConfirm: () -> Unit,
    onDecline: () -> Unit,
    onShiftDay: (Int) -> Unit,
    onApplyTimeRange: (TimeRange) -> Unit,
    onApplyCourt: (String?) -> Unit,
    onEdit: () -> Unit,
) {
    val zone = remember { ZoneId.systemDefault() }

    // `selectedTimeRange` - which range the current hour falls into.
    val selectedTimeRange = remember(occurrence.scheduledAt) {
        parseServerInstant(occurrence.scheduledAt)?.atZone(zone)?.hour?.let { hour ->
            when {
                hour < 12 -> TimeRange.MORNING
                hour < 17 -> TimeRange.DAY
                else -> TimeRange.EVENING
            }
        }
    }

    fun confirmationStatus(userId: String?): String? =
        userId?.let { id -> occurrence.confirmations.firstOrNull { it.user.id == id }?.status?.lowercase() }

    val myStatus = confirmationStatus(currentUserId)
    val shouldShowDecisionBar = myStatus == null || myStatus !in setOf("confirmed", "declined")
    val partnerId = occurrence.confirmations.firstOrNull { it.user.id != currentUserId }?.user.let { it?.id }

    val shape = continuousShape(20.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.7f))
            .border(1.dp, AppTheme.line, shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    occurrence.scheduledAt.formattedNumericDateTime(),
                    style = AppText.headline,
                    color = AppTheme.ink,
                )
                occurrence.proposedCourt?.name?.let { name ->
                    Text(
                        name,
                        style = AppText.footnote,
                        color = AppTheme.ink.copy(alpha = 0.62f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            val status = occurrenceStatusPresentation(occurrence.status)
            AppInlineChip(status.first, status.second, status.third)
        }

        if (shouldShowDecisionBar || isUpdating) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DecisionChip(
                    title = L10n.string("Confirm", "Подтвердить"),
                    tint = AppTheme.court,
                    isBusy = isUpdating,
                    modifier = Modifier.weight(1f),
                    onClick = onConfirm,
                )
                DecisionChip(
                    title = L10n.string("Can't make it", "Не смогу"),
                    tint = Color.Red.copy(alpha = 0.9f),
                    isBusy = false,
                    modifier = Modifier.weight(1f),
                    onClick = onDecline,
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ConfirmationStatusCard(L10n.string("You", "Ты"), confirmationStatus(currentUserId), Modifier.weight(1f))
            ConfirmationStatusCard(partnerName, confirmationStatus(partnerId), Modifier.weight(1f))
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                L10n.string("Quick change", "Быстро изменить"),
                style = AppText.captionSemibold,
                color = AppTheme.ink.copy(alpha = 0.56f),
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                QuickChip(L10n.string("-1 day", "-1 день")) { onShiftDay(-1) }
                QuickChip(L10n.string("+1 day", "+1 день")) { onShiftDay(1) }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TimeRange.entries.forEach { range ->
                    QuickChip(range.title, isSelected = range == selectedTimeRange) { onApplyTimeRange(range) }
                }
            }

            // `courtMenu` is a SwiftUI Menu; a scrolling row of clubs is the
            // Android idiom, and the full list stays in the editor below.
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                QuickChip(
                    L10n.string("No club", "Без клуба"),
                    isSelected = occurrence.proposedCourt == null,
                ) { onApplyCourt(null) }

                courts.take(QUICK_COURT_LIMIT).forEach { court ->
                    QuickChip(court.name, isSelected = occurrence.proposedCourt?.id == court.id) {
                        onApplyCourt(court.id)
                    }
                }
            }
        }

        SecondaryActionButton(
            title = L10n.string("Fine-tune", "Точная настройка"),
            onClick = onEdit,
            tint = AppTheme.ink,
        )
    }
}

/** `statusPresentation` - text, surface and tint for the slot's status chip. */
private fun occurrenceStatusPresentation(status: String): Triple<String, Color, Color> =
    when (status.lowercase()) {
        "confirmed" -> Triple(
            L10n.string("Confirmed", "Подтверждено"),
            AppTheme.mint,
            AppTheme.court,
        )
        "declined" -> Triple(
            L10n.string("Declined", "Отклонено"),
            Color.Red.copy(alpha = 0.12f),
            Color.Red.copy(alpha = 0.9f),
        )
        "canceled", "cancelled" -> Triple(
            L10n.string("Canceled", "Отменено"),
            AppTheme.ink.copy(alpha = 0.08f),
            AppTheme.ink.copy(alpha = 0.72f),
        )
        else -> Triple(
            L10n.string("Awaiting confirmation", "Ждет подтверждения"),
            AppTheme.cream,
            AppTheme.ink,
        )
    }

@Composable
private fun ConfirmationStatusCard(title: String, status: String?, modifier: Modifier = Modifier) {
    val (label, color) = when (status) {
        "confirmed" -> L10n.string("Confirmed", "Подтверждено") to AppTheme.court
        "declined" -> L10n.string("Can't make it", "Не смогу") to Color.Red.copy(alpha = 0.9f)
        else -> L10n.string("Awaiting confirmation", "Ждет подтверждения") to AppTheme.ink.copy(alpha = 0.72f)
    }

    Column(
        modifier = modifier
            .clip(continuousShape(14.dp))
            .background(AppTheme.creamLight)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(title, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.56f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(label, style = AppText.captionSemibold, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun QuickChip(
    title: String,
    isSelected: Boolean = false,
    onClick: () -> Unit,
) {
    Text(
        title,
        modifier = Modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(if (isSelected) AppTheme.mint else AppTheme.creamLight)
            .border(
                1.dp,
                if (isSelected) AppTheme.court.copy(alpha = 0.28f) else AppTheme.line,
                RoundedCornerShape(percent = 50),
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        style = AppText.captionSemibold,
        color = if (isSelected) AppTheme.court else AppTheme.ink,
        maxLines = 1,
    )
}

@Composable
private fun DecisionChip(
    title: String,
    tint: Color,
    isBusy: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier = modifier
            .clip(continuousShape(14.dp))
            .background(tint.copy(alpha = 0.12f))
            .clickable(enabled = !isBusy, onClick = onClick)
            .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isBusy) {
            CircularProgressIndicator(color = tint, modifier = Modifier.size(16.dp))
        } else {
            Icon(Icons.Filled.Check, contentDescription = null, tint = tint, modifier = Modifier.size(14.dp))
            Text(title, style = AppText.captionSemibold, color = tint, maxLines = 1)
        }
    }
}
