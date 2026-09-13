package shop.sportsearch.app.ui.matches

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppInlineChip
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.RemoteAvatarView
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.components.SportLevelMiniChip
import shop.sportsearch.app.ui.components.UserSafetyActions
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import shop.sportsearch.app.ui.theme.statusSurfaceColor
import shop.sportsearch.app.ui.theme.statusTintColor

/** Port of `struct MatchPlayerSheet` in ios/TennisSearchIOS/Views/MatchesView.swift. */
@Composable
fun MatchPlayerSheet(
    appModel: AppViewModel,
    match: MatchSummary,
    onDismiss: () -> Unit,
    onOpenChat: () -> Unit,
    onProposeGame: () -> Unit,
    onBlocked: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    var gameHistory by remember { mutableStateOf<List<MatchGameRequest>>(emptyList()) }
    var isLoadingHistory by remember { mutableStateOf(false) }

    val other = match.otherUser

    val commonSports = remember(appModel.currentUser, other) {
        val mine = appModel.currentUser?.preferredSports.orEmpty().toSet()
        val common = mine.intersect(other.preferredSports.toSet())
        if (common.isNotEmpty()) other.preferredSports.filter { it in common } else other.preferredSports
    }
    val primarySport = commonSports.firstOrNull() ?: other.preferredSports.firstOrNull() ?: Sport.TENNIS
    val sportsSummary = commonSports.take(3).joinToString(" · ") { it.title }
        .ifEmpty { L10n.string("Sport to be confirmed", "Спорт уточняется") }
    val levelSummary = (other.sportLevels[primarySport.wire] ?: other.tennisLevel)
        ?.let { "$it/10" } ?: L10n.string("level not specified", "уровень не указан")

    LaunchedEffect(match.id) {
        if (appModel.isUsingMockData) {
            gameHistory = listOfNotNull(match.latestGameRequest)
            return@LaunchedEffect
        }
        isLoadingHistory = true
        gameHistory = runCatching {
            appModel.repository.fetchMyGameRequests()
                .filter { it.matchId == match.id }
                .sortedByDescending { it.proposedDatetime }
        }.getOrElse { listOfNotNull(match.latestGameRequest) }
        isLoadingHistory = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(horizontal = 16.dp)
            .padding(top = 16.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        SectionCard(
            title = other.displayName,
            subtitle = other.bio ?: L10n.string("A player from your matches.", "Игрок из твоего мэтча."),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.Top,
            ) {
                RemoteAvatarView(name = other.displayName, path = other.avatarUrl, size = 92.dp)

                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        other.districtDisplayNames.take(3).forEach { district ->
                            AppInlineChip(text = district, tint = AppTheme.mint, foreground = AppTheme.court)
                        }
                    }

                    val age = other.age
                    val city = other.city
                    if (age != null && city != null) {
                        Text(
                            L10n.string("$age years old, $city", "$age лет, $city"),
                            style = AppText.subheadline,
                            color = AppTheme.ink.copy(alpha = 0.68f),
                        )
                    }

                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        other.preferredSports.take(4).forEach { sport ->
                            SportLevelMiniChip(sport = sport, level = other.sportLevels[sport.wire])
                        }
                    }
                }
            }
        }

        SectionCard(
            title = L10n.string("Why you should play", "Почему вам стоит сыграть"),
            subtitle = L10n.string(
                "Based on your match, preferred areas, sport, and level.",
                "Пока это базовые причины: мэтч, районы для игры, спорт и уровень.",
            ),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                MatchReasonRow(
                    Icons.Filled.Verified,
                    L10n.string(
                        "You already matched, so you can start planning right away.",
                        "У вас уже есть мэтч — можно сразу переходить к делу.",
                    ),
                )
                MatchReasonRow(
                    Icons.Filled.LocationOn,
                    L10n.string(
                        "Preferred areas: ${other.districtDisplaySummary}",
                        "Удобные районы: ${other.districtDisplaySummary}",
                    ),
                )
                MatchReasonRow(
                    Icons.Filled.SportsTennis,
                    L10n.string("Sport in common: $sportsSummary", "Общий спорт: $sportsSummary"),
                )
                MatchReasonRow(
                    Icons.Filled.BarChart,
                    L10n.string(
                        "${primarySport.title} level: $levelSummary",
                        "Уровень в ${primarySport.title}: $levelSummary",
                    ),
                )
            }
        }

        SectionCard(
            title = L10n.string("What's next", "Что дальше"),
            subtitle = L10n.string(
                "Starting with a chat is usually fastest. Create a game proposal when you want to set a time.",
                "Обычно быстрее всего начать с чата. Если хочешь зафиксировать время — создай предложение игры.",
            ),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                PrimaryActionButton(
                    title = L10n.string("Open chat", "Открыть чат"),
                    onClick = onOpenChat,
                    tint = AppTheme.ink,
                )
                SecondaryActionButton(
                    title = L10n.string("Propose a game", "Предложить игру"),
                    onClick = onProposeGame,
                    tint = AppTheme.court,
                )
                Text(
                    L10n.string(
                        "Tip: suggest 2–3 times and one convenient venue to make planning faster.",
                        "Совет: предложи 2–3 времени и один короткий вариант места — так быстрее договориться.",
                    ),
                    style = AppText.caption,
                    color = AppTheme.ink.copy(alpha = 0.6f),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        SectionCard(
            title = L10n.string("Safety", "Безопасность"),
            subtitle = L10n.string(
                "You can report this player to moderators or hide them completely.",
                "Можно пожаловаться модератору или полностью скрыть пользователя.",
            ),
        ) {
            UserSafetyActions(
                appModel = appModel,
                userId = other.id,
                displayName = other.displayName,
                context = UserSafetyContext.profile(other.id),
                onBlocked = {
                    onDismiss()
                    onBlocked()
                },
            )
        }

        match.latestGameRequest?.let { request ->
            SectionCard(
                title = L10n.string("Latest game proposal", "Последнее предложение игры"),
                subtitle = request.comment
                    ?: L10n.string(
                        "This game is already linked to your match.",
                        "Договоренность уже заведена в мэтче.",
                    ),
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    AppInlineChip(
                        text = request.statusLabel.localizedMatchesText,
                        tint = request.statusTintColor,
                        foreground = Color.White,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AppInlineChip(text = request.sport.title, tint = AppTheme.cream, foreground = AppTheme.ink)
                        AppInlineChip(text = request.effectiveFormatTitle, tint = AppTheme.cream, foreground = AppTheme.ink)
                    }
                    AppInlineChip(
                        text = request.proposedDatetime.formattedDateTime(),
                        tint = AppTheme.ink,
                        foreground = Color.White,
                    )
                    request.proposedCourt?.let { court ->
                        Text(
                            "${court.name}, ${court.address}",
                            style = AppText.subheadline,
                            color = AppTheme.ink.copy(alpha = 0.68f),
                        )
                    }
                    Text(
                        request.nextStepLabel.localizedMatchesText,
                        style = AppText.caption,
                        color = AppTheme.ink.copy(alpha = 0.6f),
                    )
                }
            }
        }

        if (isLoadingHistory) {
            SectionCard(
                title = L10n.string("Games", "Договоренности"),
                subtitle = L10n.string(
                    "Loading game history for this match.",
                    "Загружаю историю игр в этом мэтче.",
                ),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(color = AppTheme.court, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                    Text(
                        L10n.string("Loading games", "Загружаю договоренности"),
                        style = AppText.subheadline,
                        color = AppTheme.mutedInk,
                    )
                }
            }
        } else if (gameHistory.isNotEmpty()) {
            SectionCard(
                title = L10n.string("Games", "Договоренности"),
                subtitle = L10n.string(
                    "Current and past games. Tap one to open it in Upcoming Games.",
                    "Текущие и прошлые игры. Нажми, чтобы открыть их в ближайших играх.",
                ),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    gameHistory.forEach { request ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(continuousShape(18.dp))
                                .background(request.statusSurfaceColor)
                                .clickable {
                                    onDismiss()
                                    appModel.navigate(
                                        AppNavigationTarget.Discover(
                                            DiscoverTab.UPCOMING,
                                            highlightedGameRequestID = request.id,
                                        ),
                                    )
                                }
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(
                                    request.proposedDatetime.formattedNumericDateTime(),
                                    style = AppText.subheadlineSemibold,
                                    color = AppTheme.ink,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    request.proposedCourt?.name ?: request.sport.venueUnspecifiedTitle,
                                    style = AppText.caption,
                                    color = AppTheme.ink.copy(alpha = 0.62f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }

                            Spacer(Modifier.size(0.dp))

                            AppInlineChip(
                                text = request.statusLabel.localizedMatchesText,
                                tint = request.statusTintColor,
                                foreground = Color.White,
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Port of `struct MatchReasonRow`. */
@Composable
fun MatchReasonRow(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Box(modifier = Modifier.size(22.dp), contentAlignment = Alignment.CenterStart) {
            Icon(icon, null, tint = AppTheme.court, modifier = Modifier.size(16.dp))
        }
        Text(text, style = AppText.subheadline, color = AppTheme.ink.copy(alpha = 0.78f))
    }
}
