package shop.sportsearch.app.core

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Port of `struct SimilarPlayersMapMembership`. */
data class SimilarPlayersMapMembership(val user: DiscoverUser, val area: DiscoverMapArea) {
    val id: String get() = "${user.id}::${area.mapID}"
}

/** Port of `enum SimilarPlayersMapData`. */
object SimilarPlayersMapData {
    fun filteredUsers(users: List<DiscoverUser>, sport: Sport?): List<DiscoverUser> {
        val seen = mutableSetOf<String>()
        return users.filter { user ->
            if (!seen.add(user.id)) return@filter false
            sport?.let { user.preferredSports.contains(it) } ?: true
        }
    }

    fun validAreas(user: DiscoverUser): List<DiscoverMapArea> {
        if (!user.showOnMap) return emptyList()
        val seen = mutableSetOf<String>()
        return user.mapAreas.filter { it.isValid && seen.add(it.mapID) }
    }

    fun mapUsers(users: List<DiscoverUser>, sport: Sport?): List<DiscoverUser> =
        filteredUsers(users, sport).filter { validAreas(it).isNotEmpty() }

    fun memberships(users: List<DiscoverUser>, sport: Sport? = null): List<SimilarPlayersMapMembership> =
        filteredUsers(users, sport).flatMap { user ->
            validAreas(user).map { SimilarPlayersMapMembership(user, it) }
        }
}

/**
 * Port of `enum SimilarPlayersDistrictLayout`.
 *
 * These coordinates are presentation slots, never a player's personal location.
 */
object SimilarPlayersDistrictLayout {
    fun positions(
        memberships: List<SimilarPlayersMapMembership>,
        polygon: (DiscoverMapArea) -> List<LatLng>?,
    ): Map<String, LatLng> {
        val groups = memberships.groupBy { it.area.mapID }
        val result = mutableMapOf<String, LatLng>()

        groups.keys.sorted().forEach { key ->
            val group = groups[key] ?: return@forEach
            val seen = mutableSetOf<String>()
            val ordered = group.sortedBy { it.user.id }.filter { seen.add(it.user.id) }
            val area = ordered.firstOrNull()?.area ?: return@forEach
            val anchor = LatLng(area.latitude, area.longitude)
            val slots = polygon(area)?.let { interiorSlots(ordered.size, anchor, it) }
                ?: fallbackSlots(ordered.size, anchor)
            ordered.zip(slots).forEach { (membership, coordinate) -> result[membership.id] = coordinate }
        }

        return result
    }

    fun validatedPolygon(
        area: DiscoverMapArea,
        polygonCity: String,
        coordinates: List<LatLng>,
    ): List<LatLng>? {
        if (area.kind != "district" || area.districtId.isNullOrEmpty()) return null
        val areaCity = knownCity(area.cityName) ?: return null
        if (areaCity != knownCity(polygonCity)) return null
        knownCity(area.cityId)?.let { if (it != areaCity) return null }
        if (coordinates.size < 3) return null
        if (!coordinates.all { it.latitude.isFinite() && it.longitude.isFinite() }) return null

        val minLat = coordinates.minOf { it.latitude }
        val maxLat = coordinates.maxOf { it.latitude }
        val minLon = coordinates.minOf { it.longitude }
        val maxLon = coordinates.maxOf { it.longitude }
        if (minLat >= maxLat || minLon >= maxLon) return null
        if (area.latitude !in minLat..maxLat || area.longitude !in minLon..maxLon) return null
        if (!contains(LatLng(area.latitude, area.longitude), coordinates)) return null

        return coordinates
    }

    private fun knownCity(name: String): String? {
        val normalized = name.lowercase().trim().replace("ё", "е").replace("-", " ")
        return when (normalized) {
            "санкт петербург", "петербург", "спб", "saint petersburg", "st petersburg", "st. petersburg", "spb" -> "spb"
            "москва", "moscow" -> "moscow"
            "казань", "kazan" -> "kazan"
            else -> null
        }
    }

    fun contains(point: LatLng, polygon: List<LatLng>): Boolean {
        if (polygon.size < 3) return false
        var inside = false
        var previous = polygon[polygon.size - 1]
        polygon.forEach { current ->
            if ((current.latitude > point.latitude) != (previous.latitude > point.latitude)) {
                val crossingLongitude = (previous.longitude - current.longitude) *
                    (point.latitude - current.latitude) / (previous.latitude - current.latitude) + current.longitude
                if (point.longitude < crossingLongitude) inside = !inside
            }
            previous = current
        }
        return inside
    }

    private fun interiorSlots(count: Int, anchor: LatLng, polygon: List<LatLng>): List<LatLng>? {
        if (count <= 0 || polygon.size < 3) return null
        val minLat = polygon.minOf { it.latitude }
        val maxLat = polygon.maxOf { it.latitude }
        val minLon = polygon.minOf { it.longitude }
        val maxLon = polygon.maxOf { it.longitude }
        if (minLat >= maxLat || minLon >= maxLon) return null

        var resolution = max(6, ceil(sqrt(count.toDouble())).toInt() * 2)
        var candidates: List<LatLng> = emptyList()
        // Bound work for malformed or extremely thin outlines; their safe fallback is schematic too.
        while (resolution <= 256) {
            candidates = (0 until resolution).flatMap { row ->
                (0 until resolution).mapNotNull { column ->
                    val point = LatLng(
                        minLat + (maxLat - minLat) * (row + 0.5) / resolution,
                        minLon + (maxLon - minLon) * (column + 0.5) / resolution,
                    )
                    point.takeIf { contains(it, polygon) }
                }
            }
            if (candidates.size >= count) break
            resolution *= 2
        }
        if (candidates.size < count) return null

        val longitudeScale = max(0.01, cos(anchor.latitude * PI / 180))
        fun distance(a: LatLng, b: LatLng): Double {
            val x = (a.longitude - b.longitude) * longitudeScale
            val y = a.latitude - b.latitude
            return x * x + y * y
        }

        // Spread slots through the outline, with deterministic ties and no random jitter.
        val selected = mutableListOf<LatLng>()
        val nearest = candidates.map { distance(it, anchor) }.toMutableList()
        var next = nearest.indices.minByOrNull { nearest[it] } ?: 0
        repeat(count) {
            val point = candidates[next]
            selected.add(point)
            candidates.indices.forEach { index ->
                val value = distance(candidates[index], point)
                nearest[index] = if (selected.size == 1) value else min(nearest[index], value)
            }
            nearest[next] = -1.0
            next = nearest.indices.maxByOrNull { nearest[it] } ?: 0
        }

        return selected.sortedWith(compareBy({ it.latitude }, { it.longitude }))
    }

    fun fallbackSlots(count: Int, anchor: LatLng): List<LatLng> {
        if (count <= 0) return emptyList()
        val columns = ceil(sqrt(count.toDouble())).toInt()
        val rows = ceil(count.toDouble() / columns).toInt()
        val latitudeStep = 500.0 / 111_320.0
        val longitudeStep = 700.0 / (111_320.0 * max(0.05, cos(anchor.latitude * PI / 180)))
        // Move the whole grid inward at the poles instead of clamping distinct slots together.
        val halfHeight = (rows - 1) * latitudeStep / 2
        val centerLatitude = min(89.999 - halfHeight, max(-89.999 + halfHeight, anchor.latitude))

        return (0 until count).map { index ->
            val row = index / columns
            val rowCount = min(columns, count - row * columns)
            val longitude = anchor.longitude + (index % columns - (rowCount - 1) / 2.0) * longitudeStep
            val wrappedLongitude = (longitude + 540).mod(360.0) - 180
            LatLng(centerLatitude + (row - (rows - 1) / 2.0) * latitudeStep, wrappedLongitude)
        }
    }
}
