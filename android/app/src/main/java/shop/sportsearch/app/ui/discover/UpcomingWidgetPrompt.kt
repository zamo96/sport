package shop.sportsearch.app.ui.discover

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.GlanceAppWidgetManager
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.ui.components.AutoSizeText
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape
import shop.sportsearch.app.widget.UpcomingGamesWidgetReceiver

/** `Color.green` as the widget prompt uses it. */
private val PromptGreen = Color(0xFF34C759)

/** Port of `private struct UpcomingWidgetPromptCard`. */
@Composable
fun UpcomingWidgetPromptCard(hasUpcomingGames: Boolean, onOpenHelp: () -> Unit) {
    val shape = continuousShape(24.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(Color.White.copy(alpha = 0.09f), Color.White.copy(alpha = 0.04f)),
                ),
            )
            .border(1.dp, PromptGreen.copy(alpha = 0.26f), shape)
            .clickable(onClick = onOpenHelp)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(58.dp)
                .clip(continuousShape(18.dp))
                .background(
                    Brush.linearGradient(
                        listOf(PromptGreen.copy(alpha = 0.28f), shop.sportsearch.app.ui.theme.AppTheme.court.copy(alpha = 0.18f)),
                    ),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Widgets, contentDescription = null, tint = PromptGreen, modifier = Modifier.size(24.dp))
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            AutoSizeText(
                text = L10n.string("Upcoming games widget", "Виджет ближайших игр"),
                fontSize = 17.sp,
                fontWeight = FontWeight.ExtraBold,
                color = Color.White,
                maxLines = 1,
                minScale = 0.82f,
            )
            Text(
                text = if (hasUpcomingGames) {
                    L10n.string(
                        "We'll show your next game right on the Home screen.",
                        "Покажем следующую игру прямо на главном экране.",
                    )
                } else {
                    L10n.string(
                        "Add the widget now; it will populate after your first confirmed game.",
                        "Добавь виджет сейчас, он заполнится после первой подтвержденной игры.",
                    )
                },
                fontFamily = appFontFamily,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.62f),
            )
        }

        Spacer(Modifier.width(8.dp))

        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.42f),
            modifier = Modifier.size(15.dp),
        )
    }
}

/**
 * Port of `private struct UpcomingWidgetHelpSheet`.
 *
 * The iOS steps describe the iPhone Home Screen gesture; Android's are its own,
 * and where the launcher supports it the button pins the widget directly.
 */
@Composable
fun UpcomingWidgetHelpSheet(onConfirm: () -> Unit, onDismiss: () -> Unit) {
    DismissOnSystemBack(onDismiss)
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Box(modifier = Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .width(44.dp)
                    .height(5.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.22f)),
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(continuousShape(20.dp))
                    .background(PromptGreen.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Widgets, contentDescription = null, tint = PromptGreen, modifier = Modifier.size(30.dp))
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    L10n.string("Add the widget", "Добавь виджет"),
                    fontFamily = appFontFamily,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = Color.White,
                )
                Text(
                    L10n.string(
                        "Your next game will be visible without opening the app.",
                        "Ближайшая игра будет видна без открытия приложения.",
                    ),
                    fontFamily = appFontFamily,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.62f),
                )
            }

            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.1f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = L10n.string("Close", "Закрыть"),
                    tint = Color.White.copy(alpha = 0.82f),
                    modifier = Modifier.size(14.dp),
                )
            }
        }

        val stepsShape = continuousShape(24.dp)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(stepsShape)
                .background(Color.White.copy(alpha = 0.07f))
                .border(1.dp, Color.White.copy(alpha = 0.1f), stepsShape)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            WidgetInstructionRow(
                1,
                L10n.string(
                    "Touch and hold an empty area on the Home screen.",
                    "Зажми пустое место на главном экране.",
                ),
            )
            WidgetInstructionRow(
                2,
                L10n.string("Tap “Widgets” and find SportSearch.", "Нажми «Виджеты» и найди SportSearch."),
            )
            WidgetInstructionRow(
                3,
                L10n.string(
                    "Choose “Upcoming games” and drag it onto the screen.",
                    "Выбери «Ближайшие игры» и перетащи на экран.",
                ),
            )
        }

        Text(
            L10n.string(
                "Data is refreshed when you open Upcoming Games and whenever a game changes.",
                "Данные обновляются после открытия раздела «Ближайшие игры» и после изменений в играх.",
            ),
            fontFamily = appFontFamily,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.52f),
        )

        // Launchers from Android 8 on can pin a widget straight from the app.
        val canPin = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported

        if (canPin) {
            WidgetPrimaryButton(L10n.string("Add to Home screen", "Добавить на экран")) {
                scope.launch {
                    runCatching {
                        GlanceAppWidgetManager(context).requestPinGlanceAppWidget(
                            UpcomingGamesWidgetReceiver::class.java,
                        )
                    }
                    onConfirm()
                    onDismiss()
                }
            }
        }

        WidgetPrimaryButton(
            title = L10n.string("Got it", "Понятно"),
            isMuted = canPin,
        ) {
            onConfirm()
            onDismiss()
        }
    }
}

@Composable
private fun WidgetPrimaryButton(title: String, isMuted: Boolean = false, onClick: () -> Unit) {
    Text(
        text = title,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(continuousShape(20.dp))
            .background(
                if (isMuted) {
                    Brush.horizontalGradient(
                        listOf(Color.White.copy(alpha = 0.1f), Color.White.copy(alpha = 0.06f)),
                    )
                } else {
                    Brush.horizontalGradient(listOf(PromptGreen, Color(0xFF7DDB38)))
                },
            )
            .clickable(onClick = onClick)
            .padding(top = 16.dp),
        fontFamily = appFontFamily,
        fontSize = 18.sp,
        fontWeight = FontWeight.ExtraBold,
        color = if (isMuted) Color.White.copy(alpha = 0.82f) else Color.Black.copy(alpha = 0.9f),
        textAlign = TextAlign.Center,
    )
}

/** Port of `private struct WidgetInstructionRow`. */
@Composable
private fun WidgetInstructionRow(index: Int, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Text(
            "$index",
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(PromptGreen)
                .padding(top = 5.dp),
            fontFamily = appFontFamily,
            fontSize = 13.sp,
            fontWeight = FontWeight.ExtraBold,
            color = Color.Black.copy(alpha = 0.88f),
            textAlign = TextAlign.Center,
        )
        Text(
            text,
            fontFamily = appFontFamily,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.86f),
        )
    }
}
