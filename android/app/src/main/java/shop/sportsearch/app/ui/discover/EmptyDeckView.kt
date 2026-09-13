package shop.sportsearch.app.ui.discover

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.TravelExplore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

private object EmptyDeckPalette {
    val lime = Color(red = 0.83f, green = 0.95f, blue = 0.49f)
    val panel = Color(red = 0.075f, green = 0.085f, blue = 0.078f)
}

/**
 * Port of `struct EmptyDeckView` in ios/TennisSearchIOS/Views/EmptyDeckView.swift:
 * the next useful step once the player deck runs out.
 */
@Composable
fun EmptyDeckView(
    city: String?,
    preferredSports: List<Sport>,
    sections: List<EmptyDeckSection>,
    invite: InviteSummary?,
    hasActiveSearch: Boolean,
    isLoading: Boolean,
    hasLoaded: Boolean,
    loadFailed: Boolean,
    onCreateSearch: () -> Unit,
    onManageSearches: () -> Unit,
    onOpenCourt: (EmptyDeckCourt, Sport) -> Unit,
    onOpenClubs: (Sport) -> Unit,
    onRetry: () -> Unit,
) {
    val visibleSections = sections.filter { it.courts.isNotEmpty() }
    val trainingSport = emptyDeckTrainingSport(preferredSports, sections)

    var selectedPage by remember { mutableIntStateOf(0) }
    var isRotationPaused by remember { mutableStateOf(false) }

    // `task(id: canAutoRotate)` - the hero flips every eight seconds until touched.
    LaunchedEffect(trainingSport, isRotationPaused) {
        if (trainingSport == null || isRotationPaused) return@LaunchedEffect
        while (true) {
            delay(8000)
            selectedPage = if (selectedPage == 0) 1 else 0
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxWidth()) {
        // --- hero ---
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(continuousShape(24.dp))
                .background(
                    Brush.linearGradient(
                        listOf(
                            Color(red = 0.09f, green = 0.27f, blue = 0.21f),
                            Color(red = 0.045f, green = 0.13f, blue = 0.105f),
                        ),
                    ),
                )
                .border(1.dp, Color.White.copy(alpha = 0.12f), continuousShape(24.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().heightIn(min = if (trainingSport == null) 24.dp else 44.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    EmptyDeckCourtIllustration()
                    Text(
                        if (selectedPage == 0 || trainingSport == null) {
                            L10n.string("YOUR NEXT STEP", "СЛЕДУЮЩИЙ ШАГ")
                        } else {
                            trainingSport.title
                        },
                        style = AppText.caption2Semibold.copy(fontWeight = FontWeight.Bold),
                        color = EmptyDeckPalette.lime,
                    )
                }

                Spacer(Modifier.weight(1f))

                if (trainingSport != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        (0..1).forEach { page ->
                            val width by animateDpAsState(
                                if (selectedPage == page) 18.dp else 6.dp,
                                label = "pageDot",
                            )
                            Box(
                                modifier = Modifier
                                    .size(44.dp)
                                    .clickable {
                                        isRotationPaused = true
                                        selectedPage = page
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(
                                    modifier = Modifier
                                        .width(width)
                                        .height(6.dp)
                                        .clip(CircleShape)
                                        .background(
                                            if (selectedPage == page) {
                                                EmptyDeckPalette.lime
                                            } else {
                                                Color.White.copy(alpha = 0.3f)
                                            },
                                        ),
                                )
                            }
                        }

                        Box(
                            modifier = Modifier
                                .size(44.dp)
                                .clickable { isRotationPaused = !isRotationPaused },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                if (isRotationPaused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                                contentDescription = if (isRotationPaused) {
                                    L10n.string("Resume recommendations", "Включить смену рекомендаций")
                                } else {
                                    L10n.string("Pause recommendations", "Остановить смену рекомендаций")
                                },
                                tint = Color.White.copy(alpha = 0.8f),
                                modifier = Modifier.size(12.dp),
                            )
                        }
                    }
                }
            }

            Box {
                androidx.compose.animation.AnimatedVisibility(
                    visible = selectedPage == 0 || trainingSport == null,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    RecommendationPage(
                        title = if (hasActiveSearch) {
                            L10n.string("Your search is active", "Ваш поиск активен")
                        } else {
                            L10n.string("Keep the game going", "Игра продолжается")
                        },
                        subtitle = if (hasActiveSearch) {
                            L10n.string(
                                "Check responses or update your plans for a game.",
                                "Посмотрите отклики или обновите планы на игру.",
                            )
                        } else {
                            L10n.string(
                                "Create a search so other players can find you and suggest a game.",
                                "Оставьте поиск — другие игроки смогут найти вас и предложить игру.",
                            )
                        },
                        buttonTitle = if (hasActiveSearch) {
                            L10n.string("My searches", "Мои поиски")
                        } else {
                            L10n.string("Create a search", "Создать поиск")
                        },
                        buttonIcon = if (hasActiveSearch) Icons.AutoMirrored.Filled.Message else Icons.Filled.AddCircle,
                    ) {
                        isRotationPaused = true
                        if (hasActiveSearch) onManageSearches() else onCreateSearch()
                    }
                }

                if (trainingSport != null) {
                    androidx.compose.animation.AnimatedVisibility(
                        visible = selectedPage == 1,
                        enter = fadeIn(),
                        exit = fadeOut(),
                    ) {
                        RecommendationPage(
                            title = L10n.string("Individual training", "Индивидуальная тренировка"),
                            subtitle = L10n.string(
                                "Choose a club and ask about training options.",
                                "Выберите клуб и уточните условия занятий.",
                            ),
                            buttonTitle = L10n.string("Choose a club", "Выбрать клуб"),
                            buttonIcon = Icons.Outlined.Place,
                        ) {
                            isRotationPaused = true
                            onOpenClubs(trainingSport)
                        }
                    }
                }
            }
        }

        if (visibleSections.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        L10n.string("Find your court", "Найдите свой корт"),
                        style = AppText.title3Bold,
                        color = Color.White,
                    )
                    Text(
                        L10n.string(
                            "Explore clubs and their players",
                            "Посмотрите клубы и тех, кто там играет",
                        ),
                        style = AppText.subheadline,
                        color = Color.White.copy(alpha = 0.65f),
                    )
                }

                visibleSections.forEach { section ->
                    EmptyDeckClubRow(
                        section = section,
                        onOpenCourt = { court ->
                            isRotationPaused = true
                            onOpenCourt(court, section.sport)
                        },
                        onOpenClubs = {
                            isRotationPaused = true
                            onOpenClubs(section.sport)
                        },
                    )
                }
            }
        }

        when {
            isLoading -> Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(color = AppTheme.mint, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                Text(
                    L10n.string("Loading clubs and invitation…", "Загружаем клубы и приглашение…"),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.7f),
                )
            }

            loadFailed -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    L10n.string(
                        "Clubs and invitation couldn't load",
                        "Не удалось загрузить клубы и приглашение",
                    ),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.7f),
                )
                Row(
                    modifier = Modifier.heightIn(min = 44.dp).clickable(onClick = onRetry),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Refresh, null, tint = EmptyDeckPalette.lime, modifier = Modifier.size(15.dp))
                    Text(
                        L10n.string("Try again", "Попробовать снова"),
                        style = AppText.subheadlineSemibold,
                        color = EmptyDeckPalette.lime,
                    )
                }
            }

            hasLoaded && visibleSections.isEmpty() -> Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(
                    Icons.Outlined.Place,
                    null,
                    tint = Color.White.copy(alpha = 0.65f),
                    modifier = Modifier.size(15.dp),
                )
                Text(
                    L10n.string(
                        "No clubs in this selection yet. You can create a search without a club.",
                        "В этой подборке пока нет клубов. Поиск можно создать без клуба.",
                    ),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.65f),
                )
            }
        }

        invite?.let { EmptyDeckInviteCard(invite = it, city = city) { isRotationPaused = true } }
    }
}

@Composable
private fun RecommendationPage(
    title: String,
    subtitle: String,
    buttonTitle: String,
    buttonIcon: ImageVector,
    onClick: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(title, style = AppText.title3Bold, color = Color.White, modifier = Modifier.padding(bottom = 6.dp))
        Text(
            subtitle,
            style = AppText.subheadline,
            color = Color.White.copy(alpha = 0.78f),
            modifier = Modifier.padding(bottom = 12.dp),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(EmptyDeckPalette.lime)
                .clickable(onClick = onClick)
                .padding(horizontal = 15.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(buttonIcon, null, tint = AppTheme.ink, modifier = Modifier.size(17.dp))
            Text(buttonTitle, style = AppText.subheadlineSemibold, color = AppTheme.ink)
            Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.NorthEast, null, tint = AppTheme.ink, modifier = Modifier.size(15.dp))
        }
    }
}

/** Port of `struct EmptyDeckCourtIllustration` - a tilted court with a ball. */
@Composable
private fun EmptyDeckCourtIllustration() {
    Box(modifier = Modifier.size(width = 56.dp, height = 40.dp), contentAlignment = Alignment.Center) {
        Canvas(
            modifier = Modifier
                .size(width = 44.dp, height = 31.dp)
                .rotate(-12f)
                .clip(RoundedCornerShape(7.dp))
                .background(AppTheme.court),
        ) {
            val inset = 5f
            val court = androidx.compose.ui.geometry.Rect(
                offset = Offset(inset, 4f),
                size = Size(size.width - inset * 2, size.height - 8f),
            )
            val stroke = Color.White.copy(alpha = 0.8f)
            drawRect(stroke, topLeft = court.topLeft, size = court.size, style = androidx.compose.ui.graphics.drawscope.Stroke(0.8f))
            drawLine(stroke, Offset(court.center.x, court.top), Offset(court.center.x, court.bottom), 0.8f)
            listOf(court.top + 5f, court.bottom - 5f).forEach { y ->
                drawLine(stroke, Offset(court.left, y), Offset(court.right, y), 0.8f)
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 2.dp, top = 12.dp)
                .size(21.dp)
                .rotate(24f)
                .clip(CircleShape)
                .background(EmptyDeckPalette.lime),
        )
    }
}

/** Port of `emptyDeckTrainingSport(preferredSports:sections:)`. */
fun emptyDeckTrainingSport(preferredSports: List<Sport>, sections: List<EmptyDeckSection>): Sport? {
    val supported = setOf(
        Sport.TENNIS, Sport.TABLE_TENNIS, Sport.PADEL, Sport.SQUASH,
        Sport.BADMINTON, Sport.FITNESS, Sport.BOXING, Sport.YOGA,
    )
    return preferredSports.firstOrNull { sport ->
        sport in supported && sections.any { it.sport == sport && it.courts.isNotEmpty() }
    }
}

/** Port of `struct EmptyDeckClubRow`. */
@Composable
fun EmptyDeckClubRow(
    section: EmptyDeckSection,
    onOpenCourt: (EmptyDeckCourt) -> Unit,
    onOpenClubs: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SportIconView(sport = section.sport, color = Color.White.copy(alpha = 0.9f), size = 15.dp)
                Text(
                    section.sport.title,
                    style = AppText.subheadlineSemibold,
                    color = Color.White.copy(alpha = 0.9f),
                )
            }

            Spacer(Modifier.weight(1f))

            Row(
                modifier = Modifier.heightIn(min = 44.dp).clickable(onClick = onOpenClubs),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    L10n.string("All clubs", "Все клубы"),
                    style = AppText.captionSemibold,
                    color = EmptyDeckPalette.lime,
                )
                Icon(
                    Icons.AutoMirrored.Filled.ArrowForward,
                    null,
                    tint = EmptyDeckPalette.lime,
                    modifier = Modifier.size(12.dp),
                )
            }
        }

        section.courts.firstOrNull { it.nearby != null }?.nearby?.let { nearby ->
            NearbyResultsBanner(
                nearby = nearby,
                title = L10n.string("Clubs around your city", "Клубы рядом с вашим городом"),
            )
        }

        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            section.courts.forEach { court ->
                EmptyDeckClubTile(court = court, sport = section.sport) { onOpenCourt(court) }
            }
        }
    }
}

/** Port of `struct EmptyDeckClubTile`. */
@Composable
private fun EmptyDeckClubTile(court: EmptyDeckCourt, sport: Sport, onClick: () -> Unit) {
    val activity = when {
        court.activeSearchesCount > 0 -> L10n.string(
            "Active searches: ${court.activeSearchesCount}",
            "Активных поисков: ${court.activeSearchesCount}",
        )
        court.memberCount > 0 -> L10n.string(
            "Club players: ${court.memberCount}",
            "Игроков клуба: ${court.memberCount}",
        )
        else -> L10n.string("Explore the club", "Познакомиться с клубом")
    }

    val shape = continuousShape(23.dp)
    Column(
        modifier = Modifier
            .width(238.dp)
            .clip(shape)
            .background(AppTheme.creamLight)
            .clickable(onClick = onClick)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(15.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(AppTheme.court.copy(alpha = 0.09f)),
                contentAlignment = Alignment.Center,
            ) {
                SportIconView(sport = sport, color = AppTheme.court, size = 22.dp)
            }
            Spacer(Modifier.weight(1f))
            Icon(
                Icons.Filled.NorthEast,
                null,
                tint = AppTheme.ink.copy(alpha = 0.6f),
                modifier = Modifier.padding(4.dp).size(15.dp),
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text(
                court.name,
                style = AppText.headline,
                color = AppTheme.ink,
                maxLines = 2,
                modifier = Modifier.heightIn(min = 44.dp),
            )
            if (court.nearby != null) {
                court.city?.let {
                    Text(it, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.7f))
                }
            }
            (court.nearby?.distanceLabel ?: court.distanceLabel)?.takeIf { it.isNotEmpty() }?.let { distance ->
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Outlined.Place,
                        null,
                        tint = AppTheme.ink.copy(alpha = 0.65f),
                        modifier = Modifier.size(12.dp),
                    )
                    Text(distance, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.65f))
                }
            }
        }

        Box(Modifier.fillMaxWidth().height(1.dp).background(AppTheme.ink.copy(alpha = 0.09f)))

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
            Icon(
                if (court.activeSearchesCount > 0) Icons.Filled.People else Icons.Filled.SportsTennis,
                null,
                tint = AppTheme.court,
                modifier = Modifier.size(13.dp),
            )
            Text(activity, style = AppText.captionSemibold, color = AppTheme.court)
        }
    }
}

/** Port of `struct EmptyDeckInviteCard`. */
@Composable
private fun EmptyDeckInviteCard(invite: InviteSummary, city: String?, onInteraction: () -> Unit) {
    val androidContext = LocalContext.current
    var linkCopied by remember { mutableStateOf(false) }

    LaunchedEffect(linkCopied) {
        if (linkCopied) {
            delay(3000)
            linkCopied = false
        }
    }

    val intro = if (!city.isNullOrEmpty()) {
        L10n.string("I play in $city. Join me:", "Играю в городе $city. Присоединяйся:")
    } else {
        L10n.string("Let's find time for a game. Join me:", "Давайте найдём время для игры. Присоединяйся:")
    }
    val shareMessage = "$intro ${invite.url}"

    val shape = continuousShape(24.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(EmptyDeckPalette.panel)
            .border(1.dp, Color.White.copy(alpha = 0.1f), shape)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier
                    .size(42.dp)
                    .clip(RoundedCornerShape(13.dp))
                    .background(Color.White.copy(alpha = 0.06f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Groups, null, tint = EmptyDeckPalette.lime, modifier = Modifier.size(20.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    L10n.string("Better together", "Со своими ещё лучше"),
                    style = AppText.headline,
                    color = Color.White,
                )
                Text(
                    L10n.string(
                        "Invite someone you already play with. Your personal link is ready.",
                        "Позовите тех, с кем уже играете. Ваша личная ссылка готова.",
                    ),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.65f),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            InviteButton(
                title = L10n.string("Invite a friend", "Позвать друга"),
                icon = Icons.Filled.Share,
                background = AppTheme.mint,
                foreground = AppTheme.ink,
                modifier = Modifier.weight(1f),
            ) {
                onInteraction()
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, shareMessage)
                }
                runCatching { androidContext.startActivity(Intent.createChooser(intent, null)) }
            }

            InviteButton(
                title = if (linkCopied) L10n.string("Copied", "Скопировано") else L10n.string("Copy link", "Ссылка"),
                icon = if (linkCopied) Icons.Filled.Check else Icons.Filled.Link,
                background = Color.White.copy(alpha = 0.07f),
                foreground = if (linkCopied) EmptyDeckPalette.lime else Color.White,
                modifier = Modifier.weight(1f),
            ) {
                onInteraction()
                val clipboard = androidContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("invite", invite.url))
                linkCopied = true
            }
        }
    }
}

@Composable
private fun InviteButton(
    title: String,
    icon: ImageVector,
    background: Color,
    foreground: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(background)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = foreground, modifier = Modifier.size(16.dp))
        Text(title, style = AppText.subheadlineSemibold, color = foreground, maxLines = 1)
    }
}

/** Port of `struct NearbyResultsBanner`. */
@Composable
fun NearbyResultsBanner(nearby: NearbyResult, title: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(AppTheme.court.copy(alpha = 0.25f))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Filled.TravelExplore,
                null,
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(15.dp),
            )
            Text(title, style = AppText.subheadlineSemibold, color = Color.White.copy(alpha = 0.85f))
        }
        Text(nearby.areaLabel, style = AppText.caption, color = Color.White.copy(alpha = 0.85f))
        Text(
            L10n.string(
                "Distances are measured in a straight line from the search location.",
                "Расстояния указаны по прямой от места поиска.",
            ),
            style = AppText.caption,
            color = Color.White.copy(alpha = 0.85f),
        )
    }
}
