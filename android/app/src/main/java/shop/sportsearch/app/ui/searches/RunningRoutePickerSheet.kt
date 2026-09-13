package shop.sportsearch.app.ui.searches

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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.RunningRoutePoint
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.routeDefaultTitle
import shop.sportsearch.app.core.routeFollowsRoads
import shop.sportsearch.app.ui.components.AppScreen
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.maps.RunningRouteEditorMapView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `private struct RunningRoutePickerSheet`. */
@Composable
fun RunningRoutePickerSheet(
    sport: Sport,
    points: List<RunningRoutePoint>,
    routeTitle: String,
    onDismiss: () -> Unit,
    onDone: (List<RunningRoutePoint>, String) -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val haptics = rememberAppHaptics()
    var draftPoints by remember { mutableStateOf(points) }
    var draftTitle by remember { mutableStateOf(routeTitle) }
    var usesSatelliteMap by remember { mutableStateOf(false) }

    AppScreen {
        Column(modifier = Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
            // `header`
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    // The map is an AndroidView, and Compose draws native views
                    // after the siblings laid out before them; without this the
                    // map's surface covers the header.
                    .zIndex(1f)
                    .background(Color.White)
                    .padding(horizontal = 18.dp)
                    .padding(top = 18.dp, bottom = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        sport.routeDefaultTitle,
                        fontSize = 24.sp,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                        color = AppTheme.ink,
                    )
                    Text(
                        L10n.string(
                            "${draftPoints.size} points on map",
                            "${draftPoints.size} точек на карте",
                        ),
                        style = AppText.subheadline,
                        color = AppTheme.ink.copy(alpha = 0.56f),
                    )
                }

                Text(
                    if (usesSatelliteMap) L10n.string("Map", "Карта") else L10n.string("Satellite", "Спутник"),
                    modifier = Modifier
                        .height(36.dp)
                        .clip(RoundedCornerShape(percent = 50))
                        .background(Color.Black.copy(alpha = 0.04f))
                        .clickable {
                            usesSatelliteMap = !usesSatelliteMap
                            haptics.selection()
                        }
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                    fontSize = 13.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                    color = AppTheme.ink,
                )

                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.04f))
                        .clickable(onClick = onDismiss),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = L10n.string("Close", "Закрыть"),
                        tint = AppTheme.ink,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }

            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                RunningRouteEditorMapView(
                    points = draftPoints,
                    isSatellite = usesSatelliteMap,
                    followsRoads = sport.routeFollowsRoads,
                    modifier = Modifier.fillMaxSize(),
                    onAddPoint = { draftPoints = draftPoints + it },
                )

                Column(
                    modifier = Modifier
                        .padding(16.dp)
                        .clip(continuousShape(18.dp))
                        .background(Color.White.copy(alpha = 0.94f))
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        L10n.string("Tap along the route on the map", "Нажимайте на карту по маршруту"),
                        fontSize = 14.sp,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                        color = AppTheme.ink,
                    )
                    Text(
                        if (sport.routeFollowsRoads) {
                            L10n.string(
                                "Add at least a start and finish. The line will follow streets.",
                                "Поставьте минимум старт и финиш. Линия будет строиться по улицам.",
                            )
                        } else {
                            L10n.string(
                                "Add at least a start and finish. The line will follow the water between points.",
                                "Поставьте минимум старт и финиш. Линия пойдёт по воде между точками.",
                            )
                        },
                        style = AppText.caption,
                        color = AppTheme.ink.copy(alpha = 0.58f),
                    )
                }
            }

            // `controls`
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White)
                    .navigationBarsPadding()
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                val fieldShape = continuousShape(18.dp)
                TextField(
                    value = draftTitle,
                    onValueChange = { draftTitle = it },
                    placeholder = {
                        Text(
                            if (sport == Sport.SUPBOARD) {
                                L10n.string(
                                    "Route name, for example: island loop on the water",
                                    "Название маршрута, например: Крестовский, круг по воде",
                                )
                            } else {
                                L10n.string(
                                    "Route name, for example: park loop, 5 km",
                                    "Название маршрута, например: Парк 300-летия, круг 5 км",
                                )
                            },
                            style = AppText.subheadline,
                            color = AppTheme.ink.copy(alpha = 0.42f),
                        )
                    },
                    maxLines = 3,
                    singleLine = false,
                    textStyle = AppText.subheadline.copy(color = AppTheme.ink),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.Transparent,
                        unfocusedContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        cursorColor = AppTheme.court,
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(fieldShape)
                        .background(Color.Black.copy(alpha = 0.035f))
                        .border(1.dp, Color.Black.copy(alpha = 0.08f), fieldShape),
                )

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SecondaryActionButton(
                        title = L10n.string("Undo", "Назад"),
                        onClick = {
                            draftPoints = draftPoints.dropLast(1)
                            haptics.selection()
                        },
                        modifier = Modifier.weight(1f),
                        enabled = draftPoints.isNotEmpty(),
                    )
                    SecondaryActionButton(
                        title = L10n.string("Clear", "Очистить"),
                        onClick = {
                            draftPoints = emptyList()
                            haptics.selection()
                        },
                        modifier = Modifier.weight(1f),
                        tint = Color.Red.copy(alpha = 0.88f),
                        enabled = draftPoints.isNotEmpty(),
                    )
                }

                PrimaryActionButton(
                    title = L10n.string("Done", "Готово"),
                    onClick = {
                        val normalized = draftTitle.trim()
                        val title = if (normalized.isEmpty() && draftPoints.size >= 2) {
                            L10n.string("Route on map", "Маршрут на карте")
                        } else {
                            normalized
                        }
                        onDone(draftPoints, title)
                        haptics.success()
                    },
                    enabled = draftPoints.size >= 2,
                )
            }
        }
    }
}
