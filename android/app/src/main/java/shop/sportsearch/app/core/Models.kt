package shop.sportsearch.app.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlin.math.roundToInt

/**
 * Wire models ported from ios/TennisSearchIOS/Core/AppModels.swift.
 *
 * Where Swift writes `decodeIfPresent(Sport.self) ?? .tennis`, this port keeps
 * the raw string on the data class and exposes a typed accessor with the same
 * fallback. That way an unrecognised value from the server degrades exactly the
 * way it does on iOS instead of failing the whole response.
 */

// MARK: - Flexible decoding helpers (KeyedDecodingContainer extensions on iOS)

/** `decodeFlexibleIntDictionary`: accepts ints, doubles and nulls as values. */
object FlexibleIntMapSerializer : KSerializer<Map<String, Int>> {
    override val descriptor: SerialDescriptor =
        MapSerializer(String.serializer(), Int.serializer()).descriptor

    override fun serialize(encoder: Encoder, value: Map<String, Int>) {
        val jsonEncoder = encoder as? JsonEncoder ?: error("FlexibleIntMap requires JSON")
        jsonEncoder.encodeJsonElement(JsonObject(value.mapValues { JsonPrimitive(it.value) }))
    }

    override fun deserialize(decoder: Decoder): Map<String, Int> {
        val jsonDecoder = decoder as? JsonDecoder ?: return emptyMap()
        val element = jsonDecoder.decodeJsonElement() as? JsonObject ?: return emptyMap()
        return buildMap {
            element.forEach { (key, raw) ->
                val primitive = raw as? JsonPrimitive ?: return@forEach
                val number = primitive.intOrNull ?: primitive.doubleOrNull?.roundToInt()
                if (number != null) put(key, number)
            }
        }
    }
}

/** `decodeFlexibleStringArrayDictionary`. */
object FlexibleStringListMapSerializer : KSerializer<Map<String, List<String>>> {
    override val descriptor: SerialDescriptor =
        MapSerializer(String.serializer(), ListSerializer(String.serializer())).descriptor

    override fun serialize(encoder: Encoder, value: Map<String, List<String>>) {
        val jsonEncoder = encoder as? JsonEncoder ?: error("FlexibleStringListMap requires JSON")
        jsonEncoder.encodeJsonElement(
            JsonObject(value.mapValues { entry -> JsonArray(entry.value.map { JsonPrimitive(it) }) }),
        )
    }

    override fun deserialize(decoder: Decoder): Map<String, List<String>> {
        val jsonDecoder = decoder as? JsonDecoder ?: return emptyMap()
        val element = jsonDecoder.decodeJsonElement() as? JsonObject ?: return emptyMap()
        return buildMap {
            element.forEach { (key, raw) ->
                val array = raw as? JsonArray ?: return@forEach
                put(key, array.mapNotNull { (it as? JsonPrimitive)?.content })
            }
        }
    }
}

/** `decodeFlexibleSportArray`: unknown sports are dropped rather than throwing. */
object SportListSerializer : KSerializer<List<Sport>> {
    override val descriptor: SerialDescriptor = ListSerializer(String.serializer()).descriptor

    override fun serialize(encoder: Encoder, value: List<Sport>) {
        val jsonEncoder = encoder as? JsonEncoder ?: error("SportList requires JSON")
        jsonEncoder.encodeJsonElement(JsonArray(value.map { JsonPrimitive(it.wire) }))
    }

    override fun deserialize(decoder: Decoder): List<Sport> {
        val jsonDecoder = decoder as? JsonDecoder ?: return emptyList()
        val array = jsonDecoder.decodeJsonElement() as? JsonArray ?: return emptyList()
        return array.mapNotNull { Sport.from((it as? JsonPrimitive)?.content) }
    }
}

// MARK: - Geo

@Serializable
data class GeoCountry(val code: String, val name: String) {
    val flagEmoji: String
        get() {
            val normalized = code.trim().uppercase()
            if (normalized.length != 2 || normalized.any { it !in 'A'..'Z' }) return "🌐"
            val first = 0x1F1E6 + (normalized[0].code - 'A'.code)
            val second = 0x1F1E6 + (normalized[1].code - 'A'.code)
            return String(Character.toChars(first)) + String(Character.toChars(second))
        }
}

@Serializable
data class LocationCoverage(
    val isSupported: Boolean = false,
    val clubsEnabled: Boolean = false,
    val districtsEnabled: Boolean = false,
    val legacyCity: String? = null,
) {
    companion object {
        val unavailable = LocationCoverage()
    }
}

@Serializable
data class GeoPlace(
    val id: String,
    val provider: String = "",
    val countryCode: String = "",
    val countryName: String = "",
    val region: String? = null,
    val city: String = "",
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    val coverage: LocationCoverage = LocationCoverage.unavailable,
    val recommendedLocale: String? = null,
) {
    val displayTitle: String get() = city

    /**
     * The catalog stores country names in English, so the display name comes from
     * the country code in the language the app is currently showing.
     */
    val localizedCountryName: String
        get() = runCatching {
            @Suppress("DEPRECATION")
            java.util.Locale("", countryCode)
                .getDisplayCountry(java.util.Locale.forLanguageTag(LocaleStore.current.code))
        }.getOrNull()?.takeIf { it.isNotBlank() && it != countryCode } ?: countryName

    val displaySubtitle: String
        get() = listOfNotNull(region?.trim(), localizedCountryName.trim())
            .filter { it.isNotEmpty() && !it.equals(city, ignoreCase = true) }
            .joinToString(", ")
}

@Serializable
enum class LocationSource(val wire: String) {
    @SerialName("manual") MANUAL("manual"),
    @SerialName("geolocation") GEOLOCATION("geolocation"),
    @SerialName("legacy") LEGACY("legacy");

    companion object {
        fun from(value: String?): LocationSource? = entries.firstOrNull { it.wire == value }
    }
}

// MARK: - Auth

@Serializable
data class SessionUser(
    val id: String,
    val email: String = "",
    val onboardingCompleted: Boolean = false,
)

@Serializable
data class AuthChallenge(
    val message: String = "",
    val debugCode: String? = null,
)

// MARK: - Profile

@Serializable
data class GuestOnboardingDraft(
    val name: String = "",
    val age: Int = 0,
    @SerialName("gender") val genderRaw: String? = null,
    val city: String = "",
    val location: GeoPlace? = null,
    @SerialName("locationSource") val locationSourceRaw: String? = null,
    val district: String? = null,
    val preferredDistricts: List<String> = emptyList(),
    @Serializable(with = SportListSerializer::class) val preferredSports: List<Sport> = emptyList(),
    @Serializable(with = FlexibleIntMapSerializer::class) val sportLevels: Map<String, Int> = emptyMap(),
    @SerialName("preferredPlayFormat") val preferredPlayFormatRaw: String? = null,
    @SerialName("preferredSurface") val preferredSurfaceRaw: String? = null,
    val searchRadiusKm: Int = 20,
    val isLookingForGame: Boolean = true,
    val showOnMap: Boolean = true,
    val availableDays: List<String> = emptyList(),
    val availableTimeRanges: List<String> = emptyList(),
    @Serializable(with = FlexibleStringListMapSerializer::class) val availabilityByDay: Map<String, List<String>> = emptyMap(),
    val onboardingCompleted: Boolean = false,
) {
    val gender: Gender? get() = Gender.from(genderRaw)
    val locationSource: LocationSource? get() = LocationSource.from(locationSourceRaw)
    val preferredPlayFormat: PlayFormat get() = PlayFormat.from(preferredPlayFormatRaw) ?: PlayFormat.BOTH
    val preferredSurface: Surface get() = Surface.from(preferredSurfaceRaw) ?: Surface.ANY

    val hasProfileBasics: Boolean
        get() = name.trim().length >= 2 && age in 18..100 && preferredSports.isNotEmpty()

    val hasSelectedCity: Boolean
        get() = OnboardingRequirements.hasCity(city, location)

    val hasRequiredOnboardingFields: Boolean
        get() = hasProfileBasics && hasSelectedCity

    val hasCompletedOnboarding: Boolean
        get() = onboardingCompleted && hasRequiredOnboardingFields

    companion object {
        val DEFAULT = GuestOnboardingDraft()
    }
}

/** Port of `enum OnboardingMapVisibility`. */
object OnboardingMapVisibility {
    fun resolved(stored: Boolean, draft: Boolean, completed: Boolean): Boolean =
        if (completed) stored else stored && draft
}

@Serializable
data class UserProfile(
    val id: String,
    val email: String? = null,
    val name: String? = null,
    val age: Int? = null,
    @SerialName("gender") val genderRaw: String? = null,
    val city: String? = null,
    val location: GeoPlace? = null,
    @SerialName("coverage") val coverageRaw: LocationCoverage? = null,
    @SerialName("locationSource") val locationSourceRaw: String? = null,
    val district: String? = null,
    val preferredDistricts: List<String> = emptyList(),
    val bio: String? = null,
    val avatarUrl: String? = null,
    val profilePhotoUrls: List<String> = emptyList(),
    val profileVideoUrls: List<String> = emptyList(),
    val tennisLevel: Int? = null,
    @Serializable(with = SportListSerializer::class) val preferredSports: List<Sport> = emptyList(),
    @Serializable(with = FlexibleIntMapSerializer::class) val sportLevels: Map<String, Int> = emptyMap(),
    @SerialName("preferredPlayFormat") val preferredPlayFormatRaw: String? = null,
    @SerialName("preferredSurface") val preferredSurfaceRaw: String? = null,
    val availableDays: List<String> = emptyList(),
    val availableTimeRanges: List<String> = emptyList(),
    @Serializable(with = FlexibleStringListMapSerializer::class) val availabilityByDay: Map<String, List<String>> = emptyMap(),
    val isLookingForGame: Boolean = true,
    val showOnMap: Boolean = false,
    val searchRadiusKm: Int = 20,
    val onboardingCompleted: Boolean = false,
    val isVerified: Boolean = false,
    val notificationMatches: Boolean = true,
    val notificationMessages: Boolean = true,
    val notificationGames: Boolean = true,
    val notificationSound: Boolean = true,
    val localeOverride: String? = null,
) {
    val gender: Gender? get() = Gender.from(genderRaw)
    val locationSource: LocationSource? get() = LocationSource.from(locationSourceRaw)
    val preferredPlayFormat: PlayFormat get() = PlayFormat.from(preferredPlayFormatRaw) ?: PlayFormat.BOTH
    val preferredSurface: Surface get() = Surface.from(preferredSurfaceRaw) ?: Surface.ANY

    /** iOS prefers the location's own coverage over the top-level field. */
    val coverage: LocationCoverage
        get() = coverageRaw ?: location?.coverage ?: LocationCoverage.unavailable

    val hasCompletedOnboarding: Boolean
        get() = onboardingCompleted && (name?.trim()?.length ?: 0) >= 2 && age != null && age in 18..100 &&
            preferredSports.isNotEmpty() && OnboardingRequirements.hasCity(city, location)
}

// MARK: - Discovery

@Serializable
data class NearbyResult(
    val originCity: String = "",
    val radiusKm: Double = 0.0,
    val distanceKm: Double = 0.0,
) {
    val areaLabel: String
        get() = L10n.string(
            "Within ${radiusKm.toInt()} km of $originCity",
            "В радиусе ${radiusKm.toInt()} км от $originCity",
        )

    val distanceLabel: String
        get() {
            val value = String.format(java.util.Locale.US, "%.1f", distanceKm)
            return L10n.string("$value km in a straight line", "$value км по прямой")
        }
}

/** Server-authoritative coarse areas; never reconstructed on the client. */
@Serializable
data class DiscoverMapArea(
    val id: String,
    val cityId: String = "",
    val cityName: String = "",
    val kind: String = "",
    val districtId: String? = null,
    val label: String = "",
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
) {
    val mapID: String get() = "$cityId::$id"

    val isValid: Boolean
        get() = id.isNotEmpty() && cityId.isNotEmpty() && cityName.isNotEmpty() && label.isNotEmpty() &&
            (kind == "city" || (kind == "district" && !districtId.isNullOrEmpty())) &&
            latitude.isFinite() && longitude.isFinite() &&
            latitude in -90.0..90.0 && longitude in -180.0..180.0
}

@Serializable
data class DiscoverUser(
    val id: String,
    val showOnMap: Boolean = false,
    @SerialName("mapAreas") val mapAreasRaw: List<DiscoverMapArea> = emptyList(),
    val name: String? = null,
    val age: Int? = null,
    val city: String? = null,
    val district: String? = null,
    val districtLabel: String? = null,
    val preferredDistricts: List<String> = emptyList(),
    val bio: String? = null,
    val avatarUrl: String? = null,
    val profilePhotoUrls: List<String> = emptyList(),
    val profileVideoUrls: List<String> = emptyList(),
    val lastActiveAt: String? = null,
    val tennisLevel: Int? = null,
    @Serializable(with = SportListSerializer::class) val preferredSports: List<Sport> = emptyList(),
    @Serializable(with = FlexibleIntMapSerializer::class) val sportLevels: Map<String, Int> = emptyMap(),
    @SerialName("preferredPlayFormat") val preferredPlayFormatRaw: String? = null,
    @SerialName("preferredSurface") val preferredSurfaceRaw: String? = null,
    val availableDays: List<String> = emptyList(),
    val availableTimeRanges: List<String> = emptyList(),
    @SerialName("distanceLabel") val distanceLabelRaw: String? = null,
    val nearby: NearbyResult? = null,
    val score: Double? = null,
    val explainabilityReasons: List<String> = emptyList(),
    val gameSearches: List<GameSearch> = emptyList(),
) {
    /** iOS drops map areas entirely when the player opted out of the map. */
    val mapAreas: List<DiscoverMapArea> get() = if (showOnMap) mapAreasRaw else emptyList()

    val preferredPlayFormat: PlayFormat get() = PlayFormat.from(preferredPlayFormatRaw) ?: PlayFormat.BOTH
    val preferredSurface: Surface get() = Surface.from(preferredSurfaceRaw) ?: Surface.ANY
    val distanceLabel: String get() = distanceLabelRaw ?: L10n.string("Nearby", "Рядом")
}

// MARK: - Matches and chat

@Serializable
data class MatchSummary(
    val id: String,
    val status: String = "",
    val createdAt: String = "",
    val otherUser: DiscoverUser,
    val lastMessage: ChatMessage? = null,
    val latestGameRequest: MatchGameRequest? = null,
)

@Serializable
data class ChatMessage(
    val id: String,
    val senderUserId: String,
    val gameRequestId: String? = null,
    val text: String = "",
    val createdAt: String,
    val senderUser: ChatSender? = null,
    val attachments: List<ChatMediaAttachment> = emptyList(),
    val receipt: ChatReceipt? = null,
)

@Serializable
data class ChatMediaAttachment(
    val id: String,
    val kind: String = "image",
    val url: String = "",
    val mimeType: String = "",
    val byteSize: Int = 0,
    val position: Int = 0,
)

@Serializable
data class ChatSender(
    val id: String? = null,
    val name: String? = null,
    val avatarUrl: String? = null,
)

// MARK: - Searches

@Serializable
data class SearchResponse(
    val id: String,
    val status: String = "",
    val responderUser: DiscoverUser,
    val matchId: String? = null,
)

@Serializable
data class SearchResponseUpdateResult(
    val response: SearchResponse,
    val matchId: String? = null,
    val gameRequestId: String? = null,
    val regularPairId: String? = null,
    val gameSearch: SearchStatusUpdate? = null,
)

@Serializable
data class SearchStatusUpdate(
    val id: String,
    val status: String = "",
    val isActive: Boolean? = null,
)

@Serializable
data class SearchLobbyMessage(
    val id: String,
    val senderUserId: String,
    val text: String = "",
    val createdAt: String,
    val senderUser: ChatSender? = null,
    val attachments: List<ChatMediaAttachment> = emptyList(),
    val receipt: ChatReceipt? = null,
)

@Serializable
data class SearchLobbySummary(val gameSearch: SearchLobbyGameSearch)

@Serializable
data class SearchSlotProposalVote(
    val id: String,
    val userId: String,
    val createdAt: String = "",
)

@Serializable
data class SearchSlotProposalOption(
    val id: String,
    val scheduledAt: String,
    val durationMinutes: Int? = null,
    val proposedCourt: Court? = null,
    val votes: List<SearchSlotProposalVote> = emptyList(),
) {
    val voteCount: Int get() = votes.size
}

@Serializable
data class SearchSlotProposalSummary(
    val id: String,
    val comment: String? = null,
    val status: String = "",
    val createdAt: String = "",
    val options: List<SearchSlotProposalOption> = emptyList(),
) {
    fun selectedOptionIDs(userId: String?): Set<String> {
        if (userId == null) return emptySet()
        return options.filter { option -> option.votes.any { it.userId == userId } }
            .map { it.id }
            .toSet()
    }
}

@Serializable
data class SearchLobbyGameSearch(
    val id: String,
    val createdByUserId: String = "",
    val createdByUser: DiscoverUser? = null,
    @SerialName("searchType") val searchTypeRaw: String? = null,
    val status: String = "",
    val isActive: Boolean = false,
    @SerialName("sport") val sportRaw: String? = null,
    @SerialName("format") val formatRaw: String? = null,
    val preferredDistricts: List<String> = emptyList(),
    val preferredDays: List<String> = emptyList(),
    val preferredTimeRanges: List<String> = emptyList(),
    val hotStartsAt: String? = null,
    val durationMinutes: Int? = null,
    val playersNeeded: Int = 1,
    val desiredLevelMin: Int? = null,
    val desiredLevelMax: Int? = null,
    val comment: String? = null,
    val scheduledAt: String? = null,
    val scheduledDurationMinutes: Int? = null,
    val preferredCourt: Court? = null,
    val scheduledCourt: Court? = null,
    val activeSlotProposal: SearchSlotProposalSummary? = null,
    val responses: List<SearchResponse> = emptyList(),
    val messages: List<SearchLobbyMessage> = emptyList(),
) {
    val searchType: SearchType get() = SearchType.from(searchTypeRaw) ?: SearchType.HOT
    val sport: Sport get() = Sport.from(sportRaw) ?: Sport.TENNIS
    val format: PlayFormat get() = PlayFormat.from(formatRaw) ?: PlayFormat.SINGLES

    val preferredDistrictsLabel: String
        get() {
            val names = preferredDistricts.mapNotNull(::localizedDistrictName)
            return if (names.isEmpty()) L10n.string("Any district", "Любой район") else names.joinToString(", ")
        }
}

@Serializable
data class SearchGameScheduleResult(
    val gameSearch: GameSearch,
    val gameRequestId: String? = null,
)

@Serializable
data class RegularPairSummary(
    val id: String,
    val matchId: String,
    val partnerUser: DiscoverUser,
    val preferredCourt: Court? = null,
    val preferredDays: List<String> = emptyList(),
    val preferredTimeRanges: List<String> = emptyList(),
    val comment: String? = null,
    val occurrences: List<RegularPairOccurrence> = emptyList(),
)

@Serializable
data class RegularPairOccurrence(
    val id: String,
    val scheduledAt: String,
    val scheduleAnchor: String? = null,
    val durationMinutes: Int? = null,
    val status: String = "",
    val proposedCourt: Court? = null,
    val confirmations: List<RegularPairOccurrenceConfirmation> = emptyList(),
)

@Serializable
data class RegularPairOccurrenceConfirmation(
    val id: String,
    val user: DiscoverUser,
    val status: String = "",
)

// MARK: - Game requests

@Serializable
data class MatchGameRequest(
    val id: String,
    val matchId: String? = null,
    val rootRequestId: String? = null,
    val searchLobbyId: String? = null,
    val sourceType: String? = null,
    val regularPairId: String? = null,
    val status: String = "",
    val proposedDatetime: String = "",
    val createdByUserId: String? = null,
    val matchedUserId: String? = null,
    val durationMinutes: Int? = null,
    val comment: String? = null,
    val outcome: String? = null,
    val report: GameReport? = null,
    @SerialName("sport") val sportRaw: String? = null,
    @SerialName("format") val formatRaw: String? = null,
    val runningRoute: String? = null,
    val runningRoutePoints: List<RunningRoutePoint> = emptyList(),
    val proposedCourt: Court? = null,
    val createdByUser: ChatSender? = null,
    val matchedUser: ChatSender? = null,
    val participants: List<DiscoverUser> = emptyList(),
    val invitees: List<GameRequestInvitee> = emptyList(),
) {
    val sport: Sport get() = Sport.from(sportRaw) ?: Sport.TENNIS
    val format: PlayFormat get() = PlayFormat.from(formatRaw) ?: PlayFormat.SINGLES

    val effectivePlayersNeeded: Int get() = maxOf(participants.size - 1, 1)

    val effectiveFormatTitle: String
        get() = sport.formatTitle(format, effectivePlayersNeeded)
}

@Serializable
data class GameRequestInvitee(
    val id: String,
    val matchId: String? = null,
    val status: String = "",
    val user: DiscoverUser,
)

@Serializable
data class GameReport(
    val id: String,
    val gameRequestId: String = "",
    val createdByUserId: String = "",
    val comment: String? = null,
    val visibility: String = "",
    val status: String = "",
    val createdAt: String = "",
    val updatedAt: String = "",
    val createdByUser: DiscoverUser? = null,
    val photos: List<GameReportPhoto> = emptyList(),
    val confirmations: List<GameReportConfirmation> = emptyList(),
) {
    val photoUrls: List<String> get() = photos.sortedBy { it.position }.map { it.url }

    val confirmedCount: Int get() = confirmations.count { it.status.lowercase() == "confirmed" }

    val statusTitle: String
        get() = when (status.lowercase()) {
            "disputed" -> L10n.string("Disputed", "Есть спор")
            else -> L10n.string("Photo report saved", "Фотоотчёт сохранён")
        }
}

@Serializable
data class GameReportPhoto(val id: String, val url: String, val position: Int = 0)

@Serializable
data class GameReportConfirmation(
    val id: String,
    val userId: String = "",
    val status: String = "",
    val user: DiscoverUser? = null,
)

@Serializable
data class PersonalActivity(
    val id: String,
    val userId: String = "",
    val courtId: String = "",
    @SerialName("sport") val sportRaw: String? = null,
    val scheduledAt: String = "",
    val durationMinutes: Int? = null,
    val comment: String? = null,
    val status: String = "",
    val reportComment: String? = null,
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val court: Court? = null,
    val photos: List<PersonalActivityPhoto> = emptyList(),
) {
    val sport: Sport get() = Sport.from(sportRaw) ?: Sport.TENNIS
    val photoUrls: List<String> get() = photos.sortedBy { it.position }.map { it.url }

    val scheduledInstant: java.time.Instant? get() = parseServerInstant(scheduledAt)

    val hasEnded: Boolean
        get() {
            val start = scheduledInstant ?: return false
            val duration = (durationMinutes ?: sport.defaultDurationMinutes) * 60L
            return java.time.Instant.now().epochSecond - start.epochSecond >= duration
        }

    val isArchivedForTimeline: Boolean get() = status.lowercase() == "canceled"

    val canComplete: Boolean get() = status.lowercase() == "planned" && hasEnded
}

@Serializable
data class PersonalActivityPhoto(val id: String, val url: String, val position: Int = 0)

@Serializable
data class RunningRoutePoint(val lat: Double, val lng: Double)

// MARK: - Game searches

@Serializable
data class GameSearch(
    val id: String,
    val createdByUserId: String? = null,
    val inviteSlug: String? = null,
    val status: String = "",
    @SerialName("searchType") val searchTypeRaw: String? = null,
    @SerialName("hotWindow") val hotWindowRaw: String? = null,
    val hotStartsAt: String? = null,
    val durationMinutes: Int? = null,
    val hasCourtBooked: Boolean = false,
    @SerialName("sport") val sportRaw: String? = null,
    val selfLevel: Int? = null,
    val selfLevelUnknown: Boolean? = null,
    val desiredLevelMin: Int? = null,
    val desiredLevelMax: Int? = null,
    @SerialName("format") val formatRaw: String? = null,
    val playersNeeded: Int = 1,
    val preferredDays: List<String> = emptyList(),
    val preferredTimeRanges: List<String> = emptyList(),
    val comment: String? = null,
    val isActive: Boolean? = null,
    val isExpired: Boolean? = null,
    val preferredCourt: Court? = null,
    val customVenueTitle: String? = null,
    val customVenueAddress: String? = null,
    val runningRoute: String? = null,
    val runningRoutePoints: List<RunningRoutePoint> = emptyList(),
    val preferredDistricts: List<String> = emptyList(),
    val activeSlotProposal: SearchSlotProposalSummary? = null,
    val regularPair: RegularPairSummary? = null,
    val responses: List<SearchResponse> = emptyList(),
) {
    val searchType: SearchType get() = SearchType.from(searchTypeRaw) ?: SearchType.HOT
    val hotWindow: HotWindow? get() = HotWindow.from(hotWindowRaw)
    val sport: Sport get() = Sport.from(sportRaw) ?: Sport.TENNIS
    val format: PlayFormat get() = PlayFormat.from(formatRaw) ?: PlayFormat.SINGLES
}

// MARK: - Empty deck

@Serializable
data class EmptyDeckSection(
    @SerialName("sport") val sportRaw: String? = null,
    val total: Int = 0,
    val courts: List<EmptyDeckCourt> = emptyList(),
) {
    val sport: Sport get() = Sport.from(sportRaw) ?: Sport.TENNIS
    val id: String get() = sport.wire
}

@Serializable
data class EmptyDeckCourt(
    val id: String,
    val name: String = "",
    val city: String? = null,
    val nearby: NearbyResult? = null,
    val distanceLabel: String? = null,
    val activeSearchesCount: Int = 0,
    val memberCount: Int = 0,
    val searchers: List<EmptyDeckSearcher> = emptyList(),
)

@Serializable
data class EmptyDeckSearcher(
    val id: String,
    val name: String? = null,
    val avatarUrl: String? = null,
)

@Serializable
data class EmptyDeckContent(
    val sections: List<EmptyDeckSection> = emptyList(),
    val invite: InviteSummary? = null,
)

/** Личная ссылка-приглашение и её счётчики. */
@Serializable
data class InviteSummary(
    val code: String? = null,
    val url: String = "",
    val visits: Int = 0,
    val registered: Int? = null,
    val joined: Int = 0,
)

// MARK: - Courts

@Serializable
data class Court(
    val id: String,
    val name: String = "",
    val address: String = "",
    val city: String? = null,
    val district: String? = null,
    val locationLat: Double = 0.0,
    val locationLng: Double = 0.0,
    val nearby: NearbyResult? = null,
    val distanceLabel: String? = null,
    val nearestMetroName: String? = null,
    val metroNames: List<String> = emptyList(),
    @Serializable(with = SportListSerializer::class) val supportedSports: List<Sport> = emptyList(),
    val phone: String? = null,
    val workingHours: String? = null,
    val yandexMapsUrl: String? = null,
    val websiteUrl: String? = null,
    val bookingUrl: String? = null,
    val about: String? = null,
    val amenities: List<String> = emptyList(),
    val messengerType: String? = null,
    val messengerUrl: String? = null,
    val photoUrl: String? = null,
    val photoUrls: List<String> = emptyList(),
    val priceRange: String? = null,
    val rating: Double? = null,
    val isMember: Boolean = false,
    val memberCount: Int = 0,
    val members: List<DiscoverUser> = emptyList(),
    val activeSearchesCount: Int = 0,
    val activeSearchPlayersCount: Int = 0,
    val activeSearchPreviewUsers: List<DiscoverUser> = emptyList(),
) {
    val primaryPhotoUrl: String? get() = photoUrls.firstOrNull() ?: photoUrl

    /** Port of `Court.primarySport`. */
    val primarySport: Sport? get() = supportedSports.firstOrNull()

    val metroDisplayName: String? get() = metroNames.takeIf { it.isNotEmpty() }?.joinToString(" · ")

    /** Port of `Court.phoneURL` / `normalizedRussianPhone`. */
    val dialUri: String? get() = normalizedRussianPhone(phone)?.let { "tel:$it" }

    companion object {
        fun normalizedRussianPhone(value: String?): String? {
            if (value == null) return null
            for (candidate in value.split('|', ';', ',', '\n', '/')) {
                val digits = candidate.filter(Char::isDigit)
                when {
                    digits.length == 10 -> return "+7$digits"
                    digits.length == 11 && digits.first() == '7' -> return "+$digits"
                    digits.length == 11 && digits.first() == '8' -> return "+7${digits.drop(1)}"
                }
            }
            return null
        }
    }
}

@Serializable
data class AddressSuggestion(
    val id: String,
    val title: String = "",
    val address: String = "",
    val subtitle: String? = null,
    val lat: Double? = null,
    val lng: Double? = null,
)

// MARK: - Notifications and activity

@Serializable
enum class AppNotificationType(val wire: String) {
    @SerialName("new_match") NEW_MATCH("new_match"),
    @SerialName("new_message") NEW_MESSAGE("new_message"),
    @SerialName("incoming_like") INCOMING_LIKE("incoming_like"),
    @SerialName("search_response") SEARCH_RESPONSE("search_response"),
    @SerialName("application_result") APPLICATION_RESULT("application_result"),
    @SerialName("hot_event") HOT_EVENT("hot_event");

    companion object {
        fun from(value: String?): AppNotificationType? = entries.firstOrNull { it.wire == value }
    }
}

@Serializable
data class AppNotification(
    val id: String,
    @SerialName("type") val typeRaw: String? = null,
    val createdAt: String = "",
    val title: String = "",
    val description: String = "",
    val href: String = "",
    val status: String? = null,
) {
    val type: AppNotificationType? get() = AppNotificationType.from(typeRaw)
}

@Serializable
data class RealtimeEvent(
    val id: String? = null,
    val type: String = "",
    val createdAt: String? = null,
    val title: String? = null,
    val body: String? = null,
    val href: String? = null,
    val matchId: String? = null,
    val searchId: String? = null,
    val messageId: String? = null,
    val gameRequestId: String? = null,
    val status: String? = null,
)

@Serializable
data class ActivitySummary(
    val inboxBadgeCount: Int = 0,
    val incomingLikesCount: Int = 0,
    val hotBadgeCount: Int = 0,
    val discoverBadgeCount: Int = 0,
    val activeSearchesCount: Int = 0,
    val searchesBadgeCount: Int = 0,
    val notificationSound: Boolean = true,
)

@Serializable
data class AppStats(
    val registeredPlayersCount: Int = 0,
    val seekingPlayersCount: Int = 0,
)

// MARK: - Safety

@Serializable
data class UserSafetyContext(val type: String, val id: String? = null) {
    companion object {
        fun profile(userId: String) = UserSafetyContext("profile", userId)
        fun chat(messageId: String?) = UserSafetyContext("chat", messageId)
    }
}

@Serializable
data class UserSafetyReport(
    val id: String = "",
    val status: String = "pending",
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val dueAt: String? = null,
)

@Serializable
data class ProfileMediaUploadResult(
    val mediaUrl: String = "",
    val mediaType: String = "",
    val avatarUrl: String? = null,
    val profilePhotoUrls: List<String> = emptyList(),
    val profileVideoUrls: List<String> = emptyList(),
)

@Serializable
data class SearchSimulationResult(
    val createdResponses: Int = 0,
    val createdVotes: Int = 0,
    val finalizedOptions: Int = 0,
    val message: String = "",
)

/** Port of `struct SearchSlotProposalDraftOption`. */
data class SearchSlotProposalDraftOption(
    val scheduledAt: java.time.Instant,
    val proposedCourtId: String? = null,
    val durationMinutes: Int? = null,
)

/** Port of `struct PersonalActivityDraft`. */
data class PersonalActivityDraft(
    val courtId: String,
    val sport: Sport,
    val scheduledAt: java.time.Instant,
    val durationMinutes: Int? = null,
    val comment: String = "",
)

/** Port of `struct PersonalActivityUpdateDraft`. */
data class PersonalActivityUpdateDraft(
    val scheduledAt: java.time.Instant? = null,
    val durationMinutes: Int? = null,
    val comment: String? = null,
    val status: String? = null,
    val reportComment: String? = null,
    val photoUrls: List<String>? = null,
)

// MARK: - Local drafts (not wire types)

/** Port of `struct SearchDraft`. */
data class SearchDraft(
    val inviteSlug: String? = null,
    val preferredCourtId: String? = null,
    val customVenueTitle: String? = null,
    val customVenueAddress: String? = null,
    val runningRoute: String? = null,
    val runningRoutePoints: List<RunningRoutePoint>? = null,
    val preferredDistricts: List<String> = emptyList(),
    val preferredDays: List<String> = emptyList(),
    val preferredTimeRanges: List<String> = emptyList(),
    val searchType: SearchType = SearchType.HOT,
    val hotWindow: HotWindow? = null,
    val hotStartTime: String? = null,
    val hotStartsAt: String? = null,
    val durationMinutes: Int? = null,
    val hasCourtBooked: Boolean = false,
    val sport: Sport = Sport.TENNIS,
    val selfLevel: Int? = null,
    val selfLevelUnknown: Boolean = false,
    val desiredLevelMin: Int = 1,
    val desiredLevelMax: Int = 10,
    val format: PlayFormat = PlayFormat.SINGLES,
    val playersNeeded: Int = 1,
    val comment: String = "",
)

/** Port of `struct GameProposalDraft`. */
data class GameProposalDraft(
    val proposedCourtId: String? = null,
    val proposedDatetime: java.time.Instant,
    val durationMinutes: Int? = null,
    val levelRangeMin: Int? = null,
    val levelRangeMax: Int? = null,
    val sport: Sport,
    val format: PlayFormat,
    val comment: String = "",
)

@Serializable
enum class APNSEnvironment(val wire: String) {
    @SerialName("development") DEVELOPMENT("development"),
    @SerialName("production") PRODUCTION("production"),
}
