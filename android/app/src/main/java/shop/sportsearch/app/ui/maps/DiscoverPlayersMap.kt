package shop.sportsearch.app.ui.maps

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.viewinterop.AndroidView
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.LatLng
import shop.sportsearch.app.core.Sport
import kotlin.math.abs
import kotlin.math.min

/** Port of `struct DiscoverPlayerMapItem`. */
data class DiscoverPlayerMapItem(
    val id: String,
    val userID: String,
    val areaID: String,
    val anchorCoordinate: LatLng,
    val coordinate: LatLng,
    val areaLabel: String,
    val displayName: String,
    val avatarPath: String?,
    val sports: List<Sport>,
    val sportLevels: Map<String, Int>,
)

/** `DiscoverPlayerAnnotationView.accent`. */
private val PlayerCardAccent = Color(0xFFA1EDBF)

/**
 * Port of `struct DiscoverPlayersMap`.
 *
 * MapKit draws each player as a collision-aware `MKAnnotationView` card and
 * merges overlapping ones into a count bubble. osmdroid has neither, so the
 * cards are rasterised here and cards that would overlap on screen collapse
 * into the same count bubble MapKit would have shown.
 */
@Composable
fun DiscoverPlayersMap(
    items: List<DiscoverPlayerMapItem>,
    selectedPlayerID: String?,
    isEnabled: Boolean,
    modifier: Modifier = Modifier,
    onSelect: (String) -> Unit,
) {
    val context = LocalContext.current
    remember { ensureOsmdroidConfigured(context) }
    val density = LocalDensity.current.density

    // Grouping reads screen positions, so it has to re-run after every pan and
    // zoom - including the deferred initial fit, which lands after the first pass.
    var viewportRevision by remember { mutableIntStateOf(0) }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                applyBaseSetup(interactive = true)
                addMapListener(object : MapListener {
                    override fun onScroll(event: ScrollEvent?): Boolean {
                        viewportRevision++
                        return false
                    }

                    override fun onZoom(event: ZoomEvent?): Boolean {
                        viewportRevision++
                        return false
                    }
                })
            }
        },
        update = { map ->
            @Suppress("UNUSED_EXPRESSION")
            viewportRevision
            map.overlays.clear()

            groupOverlapping(items, map, density).forEach { group ->
                val marker = Marker(map).apply {
                    position = GeoPoint(group.latitude, group.longitude)
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                }
                if (group.items.size > 1) {
                    val isSelected = group.items.any { it.userID == selectedPlayerID }
                    marker.icon = BitmapDrawable(
                        map.context.resources,
                        countBubbleBitmap(group.items.size, isSelected, density),
                    )
                    marker.setOnMarkerClickListener { _, _ ->
                        // MapKit zooms into a cluster; here the first member is
                        // selected so the grid below scrolls to a real player.
                        if (isEnabled) onSelect(group.items.first().userID)
                        true
                    }
                } else {
                    val item = group.items.first()
                    marker.icon = BitmapDrawable(
                        map.context.resources,
                        playerCardBitmap(item, item.userID == selectedPlayerID, density),
                    )
                    marker.setOnMarkerClickListener { _, _ ->
                        if (isEnabled) onSelect(item.userID)
                        true
                    }
                }
                map.overlays.add(marker)
            }

            if (map.tag != PLAYERS_VIEWPORT_SET && items.isNotEmpty()) {
                map.tag = PLAYERS_VIEWPORT_SET
                map.fitPoints(items.map { GeoPoint(it.coordinate.latitude, it.coordinate.longitude) })
            }
            map.invalidate()
        },
    )
}

private const val PLAYERS_VIEWPORT_SET = "discover-players-viewport-set"

private data class PlayerGroup(
    val latitude: Double,
    val longitude: Double,
    val items: List<DiscoverPlayerMapItem>,
)

/** `collisionMode = .rectangle` — cards whose rectangles would overlap merge. */
private fun groupOverlapping(
    items: List<DiscoverPlayerMapItem>,
    map: MapView,
    density: Float,
): List<PlayerGroup> {
    if (items.isEmpty()) return emptyList()
    val projection = map.projection
        ?: return items.map { PlayerGroup(it.coordinate.latitude, it.coordinate.longitude, listOf(it)) }

    // Two centre-anchored rectangles intersect while their centres are closer
    // than a full card apart, which is what `collisionMode = .rectangle` merges.
    val cardWidth = 182f * density
    val cardHeight = 92f * density
    val groups = mutableListOf<MutableList<DiscoverPlayerMapItem>>()
    val anchors = mutableListOf<Pair<Float, Float>>()

    items.forEach { item ->
        val point = projection.toPixels(GeoPoint(item.coordinate.latitude, item.coordinate.longitude), null)
        val x = point.x.toFloat()
        val y = point.y.toFloat()
        val index = anchors.indexOfFirst { (gx, gy) -> abs(gx - x) < cardWidth && abs(gy - y) < cardHeight }
        if (index >= 0) {
            groups[index].add(item)
        } else {
            groups.add(mutableListOf(item))
            anchors.add(x to y)
        }
    }

    return groups.map { group ->
        PlayerGroup(
            latitude = group.sumOf { it.coordinate.latitude } / group.size,
            longitude = group.sumOf { it.coordinate.longitude } / group.size,
            items = group,
        )
    }
}

/** Port of `DiscoverPlayerAnnotationView.layoutSubviews` + `configure`. */
private fun playerCardBitmap(item: DiscoverPlayerMapItem, selected: Boolean, density: Float): Bitmap {
    val width = 182f * density
    val height = 92f * density
    val bitmap = Bitmap.createBitmap(width.toInt(), height.toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    val surface = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (selected) PlayerCardAccent.toArgb() else 0xFF1A1A1A.toInt()
    }
    val radius = 15f * density
    canvas.drawRoundRect(RectF(0f, 0f, width, height), radius, radius, surface)

    val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * density
        color = Color.White.copy(alpha = if (selected) 0.9f else 0.2f).toArgb()
    }
    canvas.drawRoundRect(
        RectF(border.strokeWidth / 2, border.strokeWidth / 2, width - border.strokeWidth / 2, height - border.strokeWidth / 2),
        radius,
        radius,
        border,
    )

    // The avatar is loaded asynchronously on iOS; the initials tile is what
    // shows until then, and is what a rasterised marker can carry here.
    val avatarRect = RectF(9f * density, 10f * density, 41f * density, 42f * density)
    val avatarFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.White.copy(alpha = 0.09f).toArgb()
    }
    canvas.drawRoundRect(avatarRect, 16f * density, 16f * density, avatarFill)

    val initialsPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        textSize = 15f * density
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    canvas.drawText(
        initialsOf(item.displayName),
        avatarRect.centerX(),
        avatarRect.centerY() - (initialsPaint.descent() + initialsPaint.ascent()) / 2f,
        initialsPaint,
    )

    val namePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (selected) android.graphics.Color.BLACK else android.graphics.Color.WHITE
        textSize = 13f * density
        isFakeBoldText = true
    }
    val textLeft = 49f * density
    val textWidth = width - 58f * density
    canvas.drawText(
        ellipsize(item.displayName, namePaint, textWidth),
        textLeft,
        9f * density - namePaint.ascent(),
        namePaint,
    )

    val sportsPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (selected) {
            Color.Black.copy(alpha = 0.75f).toArgb()
        } else {
            PlayerCardAccent.toArgb()
        }
        textSize = 10.5f * density
    }
    canvas.drawText(
        ellipsize(sportsSummary(item), sportsPaint, textWidth),
        textLeft,
        9f * density + (namePaint.descent() - namePaint.ascent()) + 3f * density - sportsPaint.ascent(),
        sportsPaint,
    )

    val areaPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (selected) {
            Color.Black.copy(alpha = 0.65f).toArgb()
        } else {
            Color.White.copy(alpha = 0.65f).toArgb()
        }
        textSize = 10f * density
    }
    canvas.drawText(
        ellipsize(item.areaLabel, areaPaint, width - 18f * density),
        9f * density,
        height - 10f * density,
        areaPaint,
    )

    return bitmap
}

/** Port of `DiscoverPlayerClusterAnnotationView.configure(count:selected:)`. */
private fun countBubbleBitmap(count: Int, selected: Boolean, density: Float): Bitmap {
    val diameter = 54f * density
    val bitmap = Bitmap.createBitmap(diameter.toInt(), diameter.toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val rect = RectF(2f * density, 2f * density, diameter - 2f * density, diameter - 2f * density)

    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (selected) PlayerCardAccent.toArgb() else 0xFF262626.toInt()
    }
    canvas.drawOval(rect, fill)

    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f * density
        color = Color.White.copy(alpha = 0.9f).toArgb()
    }
    canvas.drawOval(rect, stroke)

    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (selected) android.graphics.Color.BLACK else android.graphics.Color.WHITE
        textSize = 18f * density
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    canvas.drawText(
        count.toString(),
        diameter / 2f,
        diameter / 2f - (text.descent() + text.ascent()) / 2f,
        text,
    )

    return bitmap
}

/** Port of `DiscoverPlayerAnnotationView.sportsSummary(_:includeAll:)`. */
private fun sportsSummary(item: DiscoverPlayerMapItem, includeAll: Boolean = false): String {
    if (item.sports.isEmpty()) return L10n.string("Sport not specified", "Спорт не указан")
    val sports = if (includeAll) item.sports else item.sports.take(2)
    val summary = sports.joinToString(" · ") { sport ->
        sport.title + (item.sportLevels[sport.wire]?.let { " $it/10" } ?: "")
    }
    return summary + if (!includeAll && item.sports.size > 2) " +${item.sports.size - 2}" else ""
}

private fun initialsOf(name: String): String =
    name.split(" ").take(2).mapNotNull { it.firstOrNull()?.uppercase() }.joinToString("")

/** `lineBreakMode = .byTruncatingTail`. */
private fun ellipsize(text: String, paint: Paint, maxWidth: Float): String {
    if (paint.measureText(text) <= maxWidth) return text
    val kept = paint.breakText(text, true, maxWidth - paint.measureText("…"), null)
    return text.take(min(kept, text.length)).trimEnd() + "…"
}
