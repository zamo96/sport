package shop.sportsearch.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.MatchGameRequest
import shop.sportsearch.app.core.MatchSummary
import shop.sportsearch.app.core.displayName
import shop.sportsearch.app.core.formattedNumericDateTime
import shop.sportsearch.app.core.localizedDistrictName
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.AppScreen
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.EmptyStateView
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.searches.SheetHeader
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * `shareableMatches(for:)` - every other match whose latest game request is not
 * already pending or accepted.
 */
fun shareableMatches(request: MatchGameRequest, matches: List<MatchSummary>): List<MatchSummary> =
    matches.filter { match ->
        if (match.id == request.matchId) return@filter false
        val latest = match.latestGameRequest?.status?.lowercase()
        latest != "pending" && latest != "accepted"
    }

/** Port of `struct ShareExistingGameSheet`. */
@Composable
fun ShareExistingGameSheet(
    request: MatchGameRequest,
    matches: List<MatchSummary>,
    onDismiss: () -> Unit,
    onShare: suspend (List<String>) -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    var selectedMatchIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var isSubmitting by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    AppScreen {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                SheetHeader(
                    title = L10n.string("Invitations", "Приглашения"),
                    onClose = onDismiss,
                    trailing = {
                        val canSend = selectedMatchIds.isNotEmpty() && !isSubmitting
                        if (isSubmitting) {
                            CircularProgressIndicator(color = AppTheme.court, modifier = Modifier.size(22.dp))
                        } else {
                            Text(
                                text = L10n.string("Send", "Отправить"),
                                style = AppText.headline,
                                color = if (canSend) AppTheme.court else AppTheme.ink.copy(alpha = 0.3f),
                                modifier = Modifier.clickable(enabled = canSend) {
                                    scope.launch {
                                        isSubmitting = true
                                        onShare(selectedMatchIds.toList())
                                        isSubmitting = false
                                        onDismiss()
                                    }
                                },
                            )
                        }
                    },
                )
            }

            item {
                SectionCard(
                    title = L10n.string("Invite to game", "Пригласить в игру"),
                    subtitle = L10n.string(
                        "Choose matches to receive the game you already created.",
                        "Выбери мэтчи, которым нужно отправить уже созданную договорённость.",
                    ),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppInlineChip(request.sport.title, AppTheme.cream, AppTheme.ink)
                        AppInlineChip(
                            request.proposedDatetime.formattedNumericDateTime(),
                            AppTheme.ink,
                            Color.White,
                        )
                    }
                }
            }

            if (matches.isEmpty()) {
                item {
                    SectionCard(
                        title = L10n.string("No available matches", "Нет доступных мэтчей"),
                        subtitle = L10n.string(
                            "You need at least one more match without an active invitation.",
                            "Сначала нужен ещё хотя бы один мэтч без активного приглашения.",
                        ),
                    ) {
                        EmptyStateView(
                            title = L10n.string("No one to invite", "Некого приглашать"),
                            subtitle = L10n.string(
                                "When more matches appear, you can quickly send this game to several people here.",
                                "Как только появятся другие мэтчи, здесь можно будет быстро разослать эту игру нескольким людям.",
                            ),
                        ) {
                            Icon(
                                Icons.Filled.Group,
                                contentDescription = null,
                                tint = AppTheme.court,
                                modifier = Modifier.size(34.dp),
                            )
                        }
                    }
                }
            } else {
                item {
                    SectionCard(
                        title = L10n.string("Send to", "Кому отправить"),
                        subtitle = L10n.string(
                            "You can select several players at once.",
                            "Можно отметить сразу нескольких игроков.",
                        ),
                    ) {}
                }

                items(matches, key = { it.id }) { match ->
                    ShareMatchRow(
                        match = match,
                        isSelected = selectedMatchIds.contains(match.id),
                    ) {
                        selectedMatchIds = if (selectedMatchIds.contains(match.id)) {
                            selectedMatchIds - match.id
                        } else {
                            selectedMatchIds + match.id
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ShareMatchRow(match: MatchSummary, isSelected: Boolean, onToggle: () -> Unit) {
    val shape = continuousShape(22.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (isSelected) AppTheme.mint else Color.White.copy(alpha = 0.7f))
            .clickable(onClick = onToggle)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RemoteAvatarView(name = match.otherUser.displayName, path = match.otherUser.avatarUrl, size = 52.dp)

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                match.otherUser.displayName,
                style = AppText.headline,
                color = AppTheme.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val district = match.otherUser.districtLabel ?: match.otherUser.district
            if (district != null) {
                Text(
                    localizedDistrictName(district) ?: district,
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.62f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Spacer(Modifier.size(0.dp))

        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = null,
            tint = if (isSelected) AppTheme.court else AppTheme.ink.copy(alpha = 0.24f),
            modifier = Modifier.size(22.dp),
        )
    }
}
