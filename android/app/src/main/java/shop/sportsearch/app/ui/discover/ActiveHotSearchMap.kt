package shop.sportsearch.app.ui.discover

import android.content.Context
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
import org.osmdroid.views.overlay.Polygon
import shop.sportsearch.app.core.LatLng
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.districtAreasById
import shop.sportsearch.app.ui.maps.applyBaseSetup
import shop.sportsearch.app.ui.maps.ensureOsmdroidConfigured
import shop.sportsearch.app.ui.maps.fitDiameter
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Port of `activeHotSearchSportUIColor(for:)`. */
private fun sportMarkerColor(sport: Sport): Int = when (sport) {
    Sport.TENNIS -> 0xFFF0C72E.toInt()
    Sport.PADEL -> 0xFF1CB86E.toInt()
    Sport.FOOTBALL -> 0xFF248CF5.toInt()
    Sport.BADMINTON -> 0xFF7A61F5.toInt()
    Sport.TABLE_TENNIS -> 0xFFF2594D.toInt()
    Sport.RUNNING -> 0xFFFA732E.toInt()
    Sport.SUPBOARD -> 0xFF29B8DB.toInt()
    else -> 0xFF38DB8C.toInt()
}

/** `UIColor(red: 0.12, green: 0.86, blue: 0.55)` — clusters and the viewer's pin. */
private const val ClusterGreen = 0xFF1EDB8C.toInt()

/**
 * Port of `ActiveHotSearchMapView`.
 *
 * MapKit clusters annotations for free; osmdroid does not, so pins within
 * `clusterRadiusPx` of each other on screen are grouped here into one marker
 * that carries their ids, reproducing `MKClusterAnnotation` closely enough that
 * `onSelectCluster` receives the same list.
 */
@Composable
fun ActiveHotSearchMapView(
    items: List<HotSearchMapPin>,
    selectedItemId: String?,
    highlightedDistrictIds: List<String>,
    viewerMapCenter: LatLng,
    viewerMapDiameterMeters: Double,
    userCoordinate: LatLng?,
    userName: String,
    modifier: Modifier = Modifier,
    onSelect: (String) -> Unit,
    onSelectCluster: (List<String>) -> Unit,
) {
    val context = LocalContext.current
    remember { ensureOsmdroidConfigured(context) }
    val density = LocalDensity.current.density

    // Clustering reads screen positions, so it has to re-run after every pan and
    // zoom - including the deferred initial fit, which lands after the first pass.
    var viewportRevision by remember { mutableIntStateOf(0) }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                applyBaseSetup(interactive = true)
                setMultiTouchControls(true)
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

            // `MKPolygonRenderer` for each highlighted district.
            highlightedDistrictIds.mapNotNull(districtAreasById::get).forEach { area ->
                map.overlays.add(
                    Polygon(map).apply {
                        points = area.polygon.map { GeoPoint(it.first, it.second) }
                        fillPaint.color = area.color.copy(alpha = 0.22f).toArgb()
                        outlinePaint.color = area.color.copy(alpha = 0.92f).toArgb()
                        outlinePaint.strokeWidth = 2.4f * density
                        setOnClickListener { _, _, _ -> false }
                    },
                )
            }

            clusterPins(items, map, density).forEach { group ->
                val marker = Marker(map).apply {
                    position = GeoPoint(group.latitude, group.longitude)
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                }
                if (group.ids.size > 1) {
                    marker.icon = BitmapDrawable(
                        map.context.resources,
                        clusterMarkerBitmap(map.context, group.ids.size, density),
                    )
                    marker.setOnMarkerClickListener { _, _ ->
                        onSelectCluster(group.ids)
                        true
                    }
                } else {
                    val pin = group.pins.first()
                    val isSelected = pin.id == selectedItemId
                    marker.icon = BitmapDrawable(
                        map.context.resources,
                        sportMarkerBitmap(map.context, pin.sport, isSelected, density),
                    )
                    marker.setOnMarkerClickListener { _, _ ->
                        onSelect(pin.id)
                        true
                    }
                }
                map.overlays.add(marker)
            }

            if (userCoordinate != null) {
                map.overlays.add(
                    Marker(map).apply {
                        position = GeoPoint(userCoordinate.latitude, userCoordinate.longitude)
                        setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                        icon = BitmapDrawable(
                            map.context.resources,
                            userMarkerBitmap(map.context, userName, density),
                        )
                        setOnMarkerClickListener { _, _ -> true }
                    },
                )
            }

            // `setVisibleMapRect` once, on the viewer's own city.
            if (map.tag != VIEWPORT_SET) {
                map.tag = VIEWPORT_SET
                map.controller.setCenter(GeoPoint(viewerMapCenter.latitude, viewerMapCenter.longitude))
                map.fitDiameter(viewerMapDiameterMeters)
            }
            map.invalidate()
        },
    )
}

private const val VIEWPORT_SET = "hot-search-viewport-set"

/** One search's position on the map. */
data class HotSearchMapPin(
    val id: String,
    val sport: Sport,
    val latitude: Double,
    val longitude: Double,
)

private data class PinCluster(
    val latitude: Double,
    val longitude: Double,
    val pins: List<HotSearchMapPin>,
) {
    val ids: List<String> get() = pins.map { it.id }
}

/**
 * Groups pins that would overlap on screen. `MKMapView` clusters by annotation
 * view size; 48dp is the marker diameter used here.
 */
private fun clusterPins(items: List<HotSearchMapPin>, map: MapView, density: Float): List<PinCluster> {
    if (items.isEmpty()) return emptyList()

    val projection = map.projection ?: return items.map { PinCluster(it.latitude, it.longitude, listOf(it)) }
    val radiusPx = 48f * density
    val groups = mutableListOf<MutableList<HotSearchMapPin>>()
    val screenPoints = mutableListOf<Pair<Float, Float>>()

    items.forEach { pin ->
        val point = projection.toPixels(GeoPoint(pin.latitude, pin.longitude), null)
        val x = point.x.toFloat()
        val y = point.y.toFloat()
        val index = screenPoints.indexOfFirst { (gx, gy) ->
            abs(gx - x) <= radiusPx && abs(gy - y) <= radiusPx
        }
        if (index >= 0) {
            groups[index].add(pin)
        } else {
            groups.add(mutableListOf(pin))
            screenPoints.add(x to y)
        }
    }

    return groups.map { group ->
        PinCluster(
            latitude = group.sumOf { it.latitude } / group.size,
            longitude = group.sumOf { it.longitude } / group.size,
            pins = group,
        )
    }
}

/** Port of `activeHotSearchMarkerImage(for:isSelected:)`. */
private fun sportMarkerBitmap(context: Context, sport: Sport, isSelected: Boolean, density: Float): Bitmap {
    val sizePx = ((if (isSelected) 54f else 46f) * density).toInt()
    val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val inset = 4f * density
    val rect = RectF(inset, inset, sizePx - inset, sizePx - inset)

    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xAD000000.toInt() }
    canvas.drawOval(rect, fill)

    val innerInset = (if (isSelected) 4f else 5f) * density
    fill.color = sportMarkerColor(sport)
    canvas.drawOval(RectF(rect).apply { inset(innerInset, innerInset) }, fill)

    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = (if (isSelected) 3f else 2f) * density
        color = Color.White.copy(alpha = if (isSelected) 0.95f else 0.72f).toArgb()
    }
    canvas.drawOval(RectF(rect).apply { inset(1.2f * density, 1.2f * density) }, stroke)

    // The SF Symbol is drawn as the sport's first letter; Android has no
    // matching glyph set and a vector drawable cannot be rasterised here.
    val side = (if (isSelected) 24f else 21f) * density
    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        textSize = side * 0.78f
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    val glyph = sport.title.take(1).uppercase()
    canvas.drawText(glyph, sizePx / 2f, sizePx / 2f - (text.descent() + text.ascent()) / 2f, text)

    return bitmap
}

/** Port of `activeHotSearchClusterMarkerImage(count:)`. */
private fun clusterMarkerBitmap(context: Context, count: Int, density: Float): Bitmap {
    val sizePx = (58f * density).toInt()
    val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val inset = 3f * density
    val rect = RectF(inset, inset, sizePx - inset, sizePx - inset)

    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xC2000000.toInt() }
    canvas.drawOval(rect, fill)

    fill.color = ClusterGreen
    canvas.drawOval(RectF(rect).apply { inset(5f * density, 5f * density) }, fill)

    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2.5f * density
        color = Color.White.copy(alpha = 0.92f).toArgb()
    }
    canvas.drawOval(RectF(rect).apply { inset(1.5f * density, 1.5f * density) }, stroke)

    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.BLACK
        textSize = (if (count > 9) 17f else 20f) * density
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    canvas.drawText(
        min(count, 99).toString(),
        sizePx / 2f,
        sizePx / 2f - (text.descent() + text.ascent()) / 2f,
        text,
    )

    return bitmap
}

/** Port of `activeHotSearchUserMarkerImage(name:avatarImage:)`, initials variant. */
private fun userMarkerBitmap(context: Context, name: String, density: Float): Bitmap {
    val sizePx = (62f * density).toInt()
    val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val outer = RectF(4f * density, 4f * density, 58f * density, 58f * density)
    val inner = RectF(outer).apply { inset(5f * density, 5f * density) }

    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xB8000000.toInt() }
    canvas.drawOval(outer, fill)

    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 3f * density
        color = ClusterGreen
    }
    canvas.drawOval(RectF(outer).apply { inset(1.5f * density, 1.5f * density) }, stroke)

    fill.color = 0xFFE0FAEB.toInt()
    canvas.drawOval(inner, fill)

    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF148052.toInt()
        textSize = 17f * density
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    canvas.drawText(
        userMarkerInitials(name),
        inner.centerX(),
        inner.centerY() - (text.descent() + text.ascent()) / 2f,
        text,
    )

    fill.color = android.graphics.Color.WHITE
    canvas.drawOval(RectF(42f * density, 42f * density, 56f * density, 56f * density), fill)
    fill.color = ClusterGreen
    canvas.drawOval(RectF(45f * density, 45f * density, 53f * density, 53f * density), fill)

    return bitmap
}

/** Port of `activeHotSearchInitials(from:)`. */
private fun userMarkerInitials(name: String): String {
    val initials = name.split(" ")
        .take(2)
        .mapNotNull { it.firstOrNull()?.uppercase() }
        .joinToString("")
    return initials.ifEmpty { shop.sportsearch.app.core.L10n.string("YOU", "ВЫ") }
}

/** Unused today, kept so the cluster maths above stays readable. */
private fun spanOf(values: List<Double>): Double = max(values.max() - values.min(), 0.0)
