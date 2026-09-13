package shop.sportsearch.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.action.actionStartActivity as glanceActionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import shop.sportsearch.app.MainActivity
import shop.sportsearch.app.core.UpcomingGamesWidgetGame
import shop.sportsearch.app.core.UpcomingGamesWidgetStore
import java.time.Instant

/** `WidgetStatusStyle` - the pill's foreground/background pair. */
private data class WidgetStatusStyle(val foreground: Color, val background: Color)

private val WidgetGreen = Color(0xFF34C759)
private val WidgetSurface = Color(0xFF061C14)

/**
 * Port of `struct UpcomingGamesWidget`.
 *
 * The iOS widget supports `.systemSmall` and `.systemMedium`; Glance picks the
 * matching layout from the cell size instead of a `widgetFamily`.
 */
class UpcomingGamesWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val payload = UpcomingGamesWidgetStore.load(context)
        provideContent {
            GlanceTheme {
                WidgetBody(payload.games.firstOrNull(), Instant.now())
            }
        }
    }

    companion object {
        val SMALL = DpSize(140.dp, 140.dp)
        val MEDIUM = DpSize(300.dp, 140.dp)
    }
}

class UpcomingGamesWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = UpcomingGamesWidget()
}

@Composable
private fun WidgetBody(game: UpcomingGamesWidgetGame?, reference: Instant) {
    val isCompact = LocalSize.current.width < UpcomingGamesWidget.MEDIUM.width

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetSurface)
            .cornerRadius(24.dp)
            .clickable(glanceActionStartActivity<MainActivity>())
            .padding(if (isCompact) 14.dp else 16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (game == null) {
            EmptyContent(isCompact)
        } else if (isCompact) {
            CompactContent(game, reference)
        } else {
            RegularContent(game, reference)
        }
    }
}

/** Port of `compactContent(for:referenceDate:)`. */
@Composable
private fun ColumnScope.CompactContent(game: UpcomingGamesWidgetGame, reference: Instant) {
    val style = statusStyle(game.effectiveStatusLabel(reference))

    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = if (game.isPersonalEvent) "ВИЗИТ" else "ИГРА",
            style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White.copy(alpha = 0.62f)), fontSize = 10.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
        Spacer(GlanceModifier.defaultWeight())
        StatusPill(game.compactStatusLabel(reference), style, 10.sp)
    }

    Spacer(GlanceModifier.defaultWeight())

    Text(
        text = game.title,
        style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White), fontSize = 17.sp, fontWeight = FontWeight.Bold),
        maxLines = 1,
    )
    Spacer(GlanceModifier.height(6.dp))
    Row(verticalAlignment = Alignment.Bottom) {
        Text(
            text = game.dateText,
            style = TextStyle(color = androidx.glance.unit.ColorProvider(WidgetGreen), fontSize = 13.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
        Spacer(GlanceModifier.size(6.dp))
        Text(
            text = game.timeText,
            style = TextStyle(color = androidx.glance.unit.ColorProvider(WidgetGreen), fontSize = 21.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
    }
    Text(
        text = game.compactVenueLine,
        style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White.copy(alpha = 0.72f)), fontSize = 11.sp, fontWeight = FontWeight.Medium),
        maxLines = 1,
    )
    Text(
        text = game.courtName,
        style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White.copy(alpha = 0.72f)), fontSize = 10.sp, fontWeight = FontWeight.Medium),
        maxLines = 1,
    )
}

/** Port of `regularContent(for:referenceDate:)`. */
@Composable
private fun ColumnScope.RegularContent(game: UpcomingGamesWidgetGame, reference: Instant) {
    val label = game.effectiveStatusLabel(reference)
    val style = statusStyle(label)

    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = if (game.isPersonalEvent) "БЛИЖАЙШИЙ ВИЗИТ" else "БЛИЖАЙШАЯ ИГРА",
            style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White.copy(alpha = 0.62f)), fontSize = 11.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
        Spacer(GlanceModifier.defaultWeight())
        StatusPill(label, style, 11.sp)
    }

    Spacer(GlanceModifier.defaultWeight())

    Text(
        text = game.title,
        style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White), fontSize = 23.sp, fontWeight = FontWeight.Bold),
        maxLines = 1,
    )
    Spacer(GlanceModifier.height(6.dp))
    Text(
        text = "${game.dateText}, ${game.timeText}",
        style = TextStyle(color = androidx.glance.unit.ColorProvider(WidgetGreen), fontSize = 17.sp, fontWeight = FontWeight.Bold),
        maxLines = 1,
    )
    Text(
        text = "${game.sportTitle} · ${game.courtName}",
        style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White.copy(alpha = 0.72f)), fontSize = 12.sp, fontWeight = FontWeight.Medium),
        maxLines = 1,
    )
    game.courtAddress?.trim()?.takeIf { it.isNotEmpty() }?.let { address ->
        Text(
            text = address,
            style = TextStyle(color = androidx.glance.unit.ColorProvider(Color.White.copy(alpha = 0.56f)), fontSize = 11.sp, fontWeight = FontWeight.Medium),
            maxLines = 1,
        )
    }
}

/** Port of `compactEmptyContent` / `regularEmptyContent`. */
@Composable
private fun ColumnScope.EmptyContent(isCompact: Boolean) {
    Text(
        text = "Игр пока нет",
        style = TextStyle(
            color = androidx.glance.unit.ColorProvider(Color.White),
            fontSize = if (isCompact) 19.sp else 23.sp,
            fontWeight = FontWeight.Bold,
        ),
        maxLines = 2,
    )
    Spacer(GlanceModifier.height(6.dp))
    Text(
        text = "Первая подтвержденная игра появится здесь.",
        style = TextStyle(
            color = androidx.glance.unit.ColorProvider(Color.White.copy(alpha = 0.62f)),
            fontSize = if (isCompact) 11.sp else 13.sp,
            fontWeight = FontWeight.Medium,
        ),
        maxLines = 3,
    )
}

@Composable
private fun StatusPill(label: String, style: WidgetStatusStyle, fontSize: androidx.compose.ui.unit.TextUnit) {
    Text(
        text = label,
        modifier = GlanceModifier
            .background(style.background)
            .cornerRadius(12.dp)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        style = TextStyle(
            color = androidx.glance.unit.ColorProvider(style.foreground),
            fontSize = fontSize,
            fontWeight = FontWeight.Bold,
        ),
        maxLines = 1,
    )
}

/** Port of `statusStyle(referenceDate:)`. */
private fun statusStyle(label: String): WidgetStatusStyle = when (label) {
    "Ждём подтверждение", "Ждёт подтверждения", "Требуется ответ", "Ожидает подтверждения" ->
        WidgetStatusStyle(Color(0xFF7D73C7), Color(0xFFE8E6FD))
    "Игра подтверждена", "Игра прошла", "Визит запланирован" ->
        WidgetStatusStyle(Color(0xFF299454), Color(0xFFDBF2E3))
    "Скоро начнется" ->
        WidgetStatusStyle(Color(0xFFC7852E), Color(0xFFFCF0D4))
    "Игра началась", "Игра идет", "Визит начался", "Визит идет" ->
        WidgetStatusStyle(Color(0xFF1E6B4A), Color(0xFFBFEBD3))
    else ->
        WidgetStatusStyle(Color(0xFF4A4A4A), Color(0xFFE6E6E6))
}
