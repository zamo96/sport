package shop.sportsearch.app.ui.maps

import android.content.Context
import android.graphics.Color as AndroidColor
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import org.osmdroid.config.Configuration
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.RunningRoutePoint
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.routeDefaultTitle
import shop.sportsearch.app.core.routeFollowsRoads
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * iOS draws every map with MapKit, which needs no credentials. Google Maps on
 * Android does need an API key and this project has none, so the Android port
 * renders OpenStreetMap tiles through osmdroid — same behaviour, no key.
 */
internal fun ensureOsmdroidConfigured(context: Context) {
    val config = Configuration.getInstance()
    if (config.userAgentValue.isNullOrEmpty() || config.userAgentValue == "osmdroid") {
        // osmdroid persists its tile-cache settings; the app's own prefs file avoids
        // the deprecated android.preference.PreferenceManager.
        config.load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
        config.userAgentValue = context.packageName
        config.osmdroidBasePath = context.cacheDir.resolve("osmdroid")
        config.osmdroidTileCache = context.cacheDir.resolve("osmdroid/tiles")
    }
}

internal fun MapView.applyBaseSetup(interactive: Boolean) {
    setTileSource(TileSourceFactory.MAPNIK)
    setMultiTouchControls(interactive)
    isClickable = interactive
    zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
    isHorizontalMapRepetitionEnabled = false
    isVerticalMapRepetitionEnabled = false
}

/** `MKCoordinateRegion(center:latitudinalMeters:longitudinalMeters:)`. */
internal fun MapView.fitDiameter(diameterMeters: Double) {
    // osmdroid has no metres-based API; a bounding box of the same span does it.
    val latSpan = diameterMeters / 111_320.0
    val center = mapCenter
    val lngSpan = latSpan / kotlin.math.cos(Math.toRadians(center.latitude)).coerceAtLeast(0.01)
    post {
        zoomToBoundingBox(
            BoundingBox(
                center.latitude + latSpan / 2,
                center.longitude + lngSpan / 2,
                center.latitude - latSpan / 2,
                center.longitude - lngSpan / 2,
            ),
            false,
        )
    }
}

internal fun MapView.fitPoints(points: List<GeoPoint>, paddingFactor: Double = 1.35) {
    if (points.isEmpty()) return
    if (points.size == 1) {
        controller.setZoom(14.5)
        controller.setCenter(points.first())
        return
    }
    val box = BoundingBox.fromGeoPointsSafe(points).increaseByScale(paddingFactor.toFloat())
    post { zoomToBoundingBox(box, false) }
}

/**
 * Port of `struct RunningRoutePreviewMapView` - the route polyline with optional
 * start/finish pins.
 */
@Composable
fun RunningRoutePreviewMapView(
    points: List<RunningRoutePoint>,
    followsRoads: Boolean,
    modifier: Modifier = Modifier,
    isInteractive: Boolean = false,
    showsAnnotations: Boolean = false,
) {
    val context = LocalContext.current
    remember { ensureOsmdroidConfigured(context) }

    val geoPoints = remember(points) { points.map { GeoPoint(it.lat, it.lng) } }
    val lineColor = remember(followsRoads) {
        if (followsRoads) AppTheme.court.toArgb() else Color(0xFF2F86C9).toArgb()
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                applyBaseSetup(isInteractive)
            }
        },
        update = { map ->
            map.applyBaseSetup(isInteractive)
            map.overlays.clear()

            if (geoPoints.size >= 2) {
                map.overlays.add(
                    Polyline(map).apply {
                        setPoints(geoPoints)
                        outlinePaint.color = lineColor
                        outlinePaint.strokeWidth = 10f
                    },
                )
            }

            if (showsAnnotations && geoPoints.isNotEmpty()) {
                listOfNotNull(geoPoints.firstOrNull(), geoPoints.lastOrNull().takeIf { geoPoints.size > 1 })
                    .forEach { point ->
                        map.overlays.add(
                            Marker(map).apply {
                                position = point
                                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                            },
                        )
                    }
            }

            map.fitPoints(geoPoints)
            map.invalidate()
        },
    )
}

/** Port of `struct RunningRouteDetailSheet`. */
@Composable
fun RunningRouteDetailSheet(
    title: String,
    sport: Sport,
    points: List<RunningRoutePoint>,
    onDismiss: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    Column(modifier = Modifier.fillMaxSize().background(AppTheme.cream).statusBarsPadding()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.White)
                .padding(horizontal = 18.dp)
                .padding(top = 18.dp, bottom = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    title.ifEmpty { sport.routeDefaultTitle },
                    fontSize = 24.sp,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                    color = AppTheme.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    L10n.string(
                        "${points.size} points · ${if (sport.routeFollowsRoads) "street route" else "water route"}",
                        "${points.size} точек · ${if (sport.routeFollowsRoads) "маршрут по улицам" else "маршрут по воде"}",
                    ),
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.56f),
                )
            }

            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.04f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Close, null, tint = AppTheme.ink, modifier = Modifier.size(18.dp))
            }
        }

        RunningRoutePreviewMapView(
            points = points,
            followsRoads = sport.routeFollowsRoads,
            isInteractive = true,
            showsAnnotations = true,
            modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        )
    }
}

/**
 * Port of `SearchClubPickerMapView` - every club as a pin, the focused one
 * highlighted, tapping one reports its id back.
 */
@Composable
fun ClubsMapView(
    courts: List<Court>,
    focusedCourtId: String?,
    modifier: Modifier = Modifier,
    onSelectCourt: (String) -> Unit = {},
) {
    val context = LocalContext.current
    remember { ensureOsmdroidConfigured(context) }

    val pins = remember(courts) {
        courts.filter { it.locationLat != 0.0 || it.locationLng != 0.0 }
    }
    val accent = remember { AppTheme.court.toArgb() }

    AndroidView(
        modifier = modifier,
        factory = { ctx -> MapView(ctx).apply { applyBaseSetup(interactive = true) } },
        update = { map ->
            map.overlays.clear()

            pins.forEach { court ->
                val marker = Marker(map).apply {
                    position = GeoPoint(court.locationLat, court.locationLng)
                    title = court.name
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                    setOnMarkerClickListener { _, _ ->
                        onSelectCourt(court.id)
                        true
                    }
                }
                if (court.id == focusedCourtId) {
                    marker.icon?.setTint(accent)
                }
                map.overlays.add(marker)
            }

            val focused = pins.firstOrNull { it.id == focusedCourtId }
            if (focused != null) {
                map.controller.setZoom(15.0)
                map.controller.setCenter(GeoPoint(focused.locationLat, focused.locationLng))
            } else {
                map.fitPoints(pins.map { GeoPoint(it.locationLat, it.locationLng) })
            }
            map.invalidate()
        },
    )
}

/**
 * Port of `struct RunningRouteEditorMapView` - the editable variant, where a tap
 * on the map appends a point.
 *
 * MapKit switches to imagery with `mapType = .satellite`; osmdroid has no built-in
 * imagery layer, so the satellite toggle swaps in the OSM topographic tiles, which
 * is the closest source that needs no key.
 */
@Composable
fun RunningRouteEditorMapView(
    points: List<RunningRoutePoint>,
    isSatellite: Boolean,
    followsRoads: Boolean,
    modifier: Modifier = Modifier,
    onAddPoint: (RunningRoutePoint) -> Unit,
) {
    val context = LocalContext.current
    remember { ensureOsmdroidConfigured(context) }

    val geoPoints = remember(points) { points.map { GeoPoint(it.lat, it.lng) } }
    val lineColor = remember(followsRoads) {
        if (followsRoads) AppTheme.court.toArgb() else Color(0xFF2F86C9).toArgb()
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                applyBaseSetup(interactive = true)
                // `runningRouteDefaultCenter`, span 0.12 x 0.16.
                controller.setZoom(11.5)
                controller.setCenter(GeoPoint(59.9386, 30.3141))
                overlays.add(
                    MapEventsOverlay(object : MapEventsReceiver {
                        override fun singleTapConfirmedHelper(p: GeoPoint?): Boolean {
                            p?.let { onAddPoint(RunningRoutePoint(it.latitude, it.longitude)) }
                            return true
                        }

                        override fun longPressHelper(p: GeoPoint?): Boolean = false
                    }),
                )
            }
        },
        update = { map ->
            map.setTileSource(
                if (isSatellite) TileSourceFactory.OpenTopo else TileSourceFactory.MAPNIK,
            )
            // The tap receiver is always overlay 0; everything after it is redrawn.
            while (map.overlays.size > 1) map.overlays.removeAt(map.overlays.size - 1)

            if (geoPoints.size >= 2) {
                map.overlays.add(
                    Polyline(map).apply {
                        setPoints(geoPoints)
                        outlinePaint.color = lineColor
                        outlinePaint.strokeWidth = 10f
                    },
                )
            }

            geoPoints.forEach { point ->
                map.overlays.add(
                    Marker(map).apply {
                        position = point
                        setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                        setOnMarkerClickListener { _, _ -> true }
                    },
                )
            }
            map.invalidate()
        },
    )
}
