package shop.sportsearch.app.ui.discover

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material.icons.filled.SportsTennis
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.*
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct DiscoverParticipantSheet` in ios/TennisSearchIOS/Views/DiscoverView.swift. */
@Composable
fun DiscoverParticipantSheet(
    appModel: AppViewModel,
    user: DiscoverUser,
    onDismiss: () -> Unit,
    onOpenChat: (() -> Unit)? = null,
    onBlocked: () -> Unit = {},
) {
    DismissOnSystemBack(onDismiss)
    var mediaPreview by remember { mutableStateOf<PlayerMediaItem?>(null) }

    val primarySport = user.preferredSports.firstOrNull() ?: Sport.TENNIS
    val sportsSummary = user.preferredSports.take(3).joinToString(" · ") { it.title }
        .ifEmpty { L10n.string("Sport to be confirmed", "Спорт уточняется") }
    val levelSummary = (user.sportLevels[primarySport.wire] ?: user.tennisLevel)
        ?.let { "$it/10" } ?: L10n.string("Level not specified", "Уровень не указан")

    mediaPreview?.let { item ->
        ChatMediaViewer(
            repository = appModel.repository,
            path = item.path,
            onDismiss = { mediaPreview = null },
        )
        return
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
        // The iOS sheet is dismissed by its drag indicator; this screen is not a
        // sheet, so it needs an explicit way out - and guests never reach the
        // "Close card" button further down, which lives in the signed-in branch.
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = L10n.string("Close", "Закрыть"),
                    tint = Color.White.copy(alpha = 0.74f),
                    modifier = Modifier.size(14.dp),
                )
            }
        }

        SectionCard(
            title = user.displayName,
            subtitle = user.bio ?: L10n.string("Game participant profile.", "Профиль участника игры."),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
                RemoteAvatarView(name = user.displayName, path = user.profileHeroImagePath, size = 92.dp)

                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        user.districtDisplayNames.take(3).forEach { district ->
                            AppInlineChip(text = district, tint = AppTheme.mint, foreground = AppTheme.court)
                        }
                    }

                    val age = user.age
                    val city = user.city
                    if (age != null && city != null) {
                        Text(
                            L10n.string("Age $age, $city", "$age лет, $city"),
                            style = AppText.subheadline,
                            color = AppTheme.ink.copy(alpha = 0.68f),
                        )
                    }

                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        user.preferredSports.take(4).forEach { sport ->
                            SportLevelMiniChip(
                                sport = sport,
                                level = user.sportLevels[sport.wire] ?: user.tennisLevel,
                            )
                        }
                    }
                }
            }
        }

        if (user.playerCardMediaItems.isNotEmpty()) {
            SectionCard(
                title = L10n.string("Photos and videos", "Фото и видео"),
                subtitle = L10n.string("Media from the player's profile.", "Медиа из карточки игрока."),
            ) {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    user.playerCardMediaItems.forEach { item ->
                        DiscoverPlayerMediaTile(item) { mediaPreview = item }
                    }
                }
            }
        }

        SectionCard(
            title = L10n.string("Why you should play", "Почему вам стоит сыграть"),
            subtitle = if (user.explainabilityReasons.isEmpty()) {
                L10n.string(
                    "For now these are the basic reasons: play areas, sport, and level.",
                    "Пока это базовые причины: районы для игры, спорт и уровень.",
                )
            } else {
                L10n.string("2–4 recommendation reasons.", "2–4 причины релевантности из подбора.")
            },
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (user.explainabilityReasons.isEmpty()) {
                    DiscoverReasonRow(
                        Icons.Filled.LocationOn,
                        L10n.string(
                            "Preferred areas: ${user.districtDisplaySummary}",
                            "Удобные районы: ${user.districtDisplaySummary}",
                        ),
                    )
                    DiscoverReasonRow(
                        Icons.Filled.SportsTennis,
                        L10n.string("Sport: $sportsSummary", "Спорт: $sportsSummary"),
                    )
                    DiscoverReasonRow(
                        Icons.Filled.BarChart,
                        L10n.string(
                            "${primarySport.title} level: $levelSummary",
                            "Уровень в ${primarySport.title}: $levelSummary",
                        ),
                    )
                } else {
                    user.explainabilityReasons.take(4).forEach { reason ->
                        DiscoverReasonRow(Icons.Filled.AutoAwesome, reason)
                    }
                }
            }
        }

        if (!appModel.isAuthenticated) {
            SectionCard(
                title = L10n.string("What's next", "Что дальше"),
                subtitle = L10n.string(
                    "Sign in to chat, save items, and receive notifications.",
                    "Вход нужен, чтобы переписываться, сохранять и получать уведомления.",
                ),
            ) {
                AuthInlinePrompt(
                    title = L10n.string("Sign in to continue", "Войти, чтобы продолжить"),
                    subtitle = L10n.string(
                        "Verify your email to chat, invite people to games, and see your history.",
                        "Подтверди email — и сможешь писать, предлагать игры и видеть историю.",
                    ),
                ) { appModel.presentAuth(AuthStep.EMAIL) }

                SecondaryActionButton(
                    title = L10n.string("Close card", "Закрыть карточку"),
                    onClick = onDismiss,
                    tint = AppTheme.court,
                )
            }
        } else {
            SectionCard(
                title = L10n.string("What's next", "Что дальше"),
                subtitle = L10n.string(
                    "The fastest next step is to send a message. Use the chat to suggest 2–3 times " +
                        "or confirm the venue.",
                    "Самый быстрый шаг — написать. В чате удобно предложить 2–3 времени или уточнить " +
                        primarySport.venueFieldTitle.lowercase() + ".",
                ),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (onOpenChat != null) {
                        PrimaryActionButton(
                            title = L10n.string("Open chat", "Открыть чат"),
                            tint = AppTheme.ink,
                            onClick = {
                                onDismiss()
                                onOpenChat()
                            },
                        )
                    } else {
                        Text(
                            L10n.string(
                                "Open the chat from the game card to arrange the time and format.",
                                "Открой чат из карточки игры — там проще договориться о времени и формате.",
                            ),
                            style = AppText.subheadline,
                            color = AppTheme.ink.copy(alpha = 0.68f),
                        )
                    }

                    SecondaryActionButton(
                        title = L10n.string("Close card", "Закрыть карточку"),
                        onClick = onDismiss,
                        tint = AppTheme.court,
                    )
                }
            }
        }

        SectionCard(
            title = L10n.string("Safety", "Безопасность"),
            subtitle = L10n.string(
                "Reports are reviewed by a moderator. A blocked user disappears from your feed immediately.",
                "Жалобы проверяет модератор. Заблокированный пользователь сразу исчезнет из вашей ленты.",
            ),
        ) {
            UserSafetyActions(
                appModel = appModel,
                userId = user.id,
                displayName = user.displayName,
                context = UserSafetyContext.profile(user.id),
                onBlocked = {
                    onDismiss()
                    onBlocked()
                },
            )
        }
    }
}

/** Port of `struct DiscoverReasonRow`. */
@Composable
fun DiscoverReasonRow(icon: ImageVector, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Box(modifier = Modifier.size(22.dp), contentAlignment = Alignment.CenterStart) {
            Icon(icon, null, tint = AppTheme.court, modifier = Modifier.size(16.dp))
        }
        Text(text, style = AppText.subheadline, color = AppTheme.ink.copy(alpha = 0.78f))
    }
}

/** Port of `struct DiscoverPlayerMediaTile`. */
@Composable
fun DiscoverPlayerMediaTile(item: PlayerMediaItem, onOpen: () -> Unit) {
    val shape = continuousShape(16.dp)
    Box(
        modifier = Modifier
            .size(width = 92.dp, height = 120.dp)
            .clip(shape)
            .background(AppTheme.court.copy(alpha = 0.16f))
            .clickable(onClick = onOpen),
        contentAlignment = Alignment.Center,
    ) {
        val url = resolveAppRemoteUrl(item.path)
        if (url != null && item.kind == PlayerMediaKind.PHOTO) {
            AsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Icon(
                if (item.kind == PlayerMediaKind.VIDEO) Icons.Filled.PlayCircleFilled else Icons.Filled.PhotoLibrary,
                null,
                tint = Color.White.copy(alpha = 0.8f),
                modifier = Modifier.size(26.dp),
            )
        }
    }
}

/** Port of `struct AuthInlinePrompt`. */
@Composable
fun AuthInlinePrompt(title: String, subtitle: String, onAction: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
        Text(title, style = AppText.headlineBold, color = AppTheme.ink)
        Text(subtitle, style = AppText.subheadline, color = AppTheme.ink.copy(alpha = 0.66f))
        PrimaryActionButton(
            title = L10n.string("Sign in", "Войти"),
            tint = AppTheme.court,
            onClick = onAction,
        )
    }
}
