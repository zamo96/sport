package shop.sportsearch.app.core

/**
 * City and district helpers ported from ios/TennisSearchIOS/Core/AppModels.swift.
 * District ids are server-side identifiers; the display names live on the client
 * on both platforms, so they must stay in sync.
 */

data class LatLng(val latitude: Double, val longitude: Double)

enum class SupportedCity(val wire: String) {
    SAINT_PETERSBURG("Санкт-Петербург"),
    MOSCOW("Москва"),
    KAZAN("Казань");

    val mapCenter: LatLng
        get() = when (this) {
            SAINT_PETERSBURG -> LatLng(59.9386, 30.3141)
            MOSCOW -> LatLng(55.7558, 37.6173)
            KAZAN -> LatLng(55.7961, 49.1064)
        }

    val mapDiameterMeters: Double
        get() = when (this) {
            SAINT_PETERSBURG -> 70_000.0
            MOSCOW -> 90_000.0
            KAZAN -> 55_000.0
        }

    val supportsDistrictSelection: Boolean get() = true

    companion object {
        val selectableCases = listOf(SAINT_PETERSBURG, MOSCOW)

        fun resolve(value: String?): SupportedCity? {
            val normalized = (value ?: "")
                .trim()
                .lowercase()
                .replace("ё", "е")
                .replace("-", " ")

            return when {
                normalized.contains("петербург") || normalized.contains("petersburg") -> SAINT_PETERSBURG
                normalized.contains("москва") || normalized.contains("moscow") -> MOSCOW
                normalized.contains("казан") || normalized.contains("kazan") -> KAZAN
                else -> null
            }
        }
    }
}

private val districtDisplayNamesMap: Map<String, String> = mapOf(
    "admiralteysky" to "Адмиралтейский",
    "vasileostrovsky" to "Василеостровский",
    "vyborgsky" to "Выборгский",
    "kalininsky" to "Калининский",
    "kirovsky" to "Кировский",
    "kolpinsky" to "Колпинский",
    "krasnogvardeysky" to "Красногвардейский",
    "krasnoselsky" to "Красносельский",
    "kronshtadtsky" to "Кронштадтский",
    "kurortny" to "Курортный",
    "moskovsky" to "Московский",
    "nevsky" to "Невский",
    "petrogradsky" to "Петроградский",
    "petrodvortsovy" to "Петродворцовый",
    "primorsky" to "Приморский",
    "pushkinsky" to "Пушкинский",
    "frunzensky" to "Фрунзенский",
    "central" to "Центральный",
    "moscow_central" to "Центральный административный округ",
    "moscow_northern" to "Северный административный округ",
    "moscow_northeastern" to "Северо-Восточный административный округ",
    "moscow_eastern" to "Восточный административный округ",
    "moscow_southeastern" to "Юго-Восточный административный округ",
    "moscow_southern" to "Южный административный округ",
    "moscow_southwestern" to "Юго-Западный административный округ",
    "moscow_western" to "Западный административный округ",
    "moscow_northwestern" to "Северо-Западный административный округ",
    "moscow_zelenograd" to "Зеленоградский административный округ",
    "moscow_novomoskovsky" to "Новомосковский административный округ",
    "moscow_troitsky" to "Троицкий административный округ",
    "kazan_aviastroitelny" to "Авиастроительный",
    "kazan_vakhitovsky" to "Вахитовский",
    "kazan_kirovsky" to "Кировский",
    "kazan_moskovsky" to "Московский",
    "kazan_novo_savinovsky" to "Ново-Савиновский",
    "kazan_privolzhsky" to "Приволжский",
    "kazan_sovetsky" to "Советский",
)

val allDistrictIds: List<String> get() = districtDisplayNamesMap.keys.toList()

fun localizedDistrictName(value: String?): String? {
    if (value.isNullOrEmpty()) return null
    districtDisplayNamesMap[value.lowercase()]?.let { return it }
    return value.replace("_", " ").replaceFirstChar { it.uppercase() }
}

fun districtBelongsToCity(districtID: String, city: SupportedCity): Boolean = when (city) {
    SupportedCity.SAINT_PETERSBURG -> !districtID.startsWith("moscow_") && !districtID.startsWith("kazan_")
    SupportedCity.MOSCOW -> districtID.startsWith("moscow_")
    SupportedCity.KAZAN -> districtID.startsWith("kazan_")
}

private val districtAliases: Map<String, List<String>> = mapOf(
    "moscow_central" to listOf("цао", "центральный административный"),
    "moscow_northern" to listOf("сао", "северный административный"),
    "moscow_northeastern" to listOf("свао", "северо восточный административный"),
    "moscow_eastern" to listOf("вао", "восточный административный"),
    "moscow_southeastern" to listOf("ювао", "юго восточный административный"),
    "moscow_southern" to listOf("юао", "южный административный"),
    "moscow_southwestern" to listOf("юзао", "юго западный административный"),
    "moscow_western" to listOf("зао", "западный административный"),
    "moscow_northwestern" to listOf("сзао", "северо западный административный"),
    "moscow_zelenograd" to listOf("зелено град", "зеленоград"),
    "moscow_novomoskovsky" to listOf("нао", "новомосков"),
    "moscow_troitsky" to listOf("тао", "троиц"),
    "kazan_aviastroitelny" to listOf("авиастроитель"),
    "kazan_vakhitovsky" to listOf("вахитов"),
    "kazan_kirovsky" to listOf("киров"),
    "kazan_moskovsky" to listOf("москов"),
    "kazan_novo_savinovsky" to listOf("ново савинов"),
    "kazan_privolzhsky" to listOf("приволж"),
    "kazan_sovetsky" to listOf("советск"),
)

/** Short okrug codes must match a whole token, or "ЗАО" swallows "ЮЗАО". */
private val exactOnlyAliases = setOf("цао", "сао", "свао", "вао", "ювао", "юао", "юзао", "зао", "сзао", "нао", "тао")

fun resolvedDistrictID(displayName: String?, city: SupportedCity? = null): String? {
    if (displayName == null) return null

    val normalized = displayName
        .trim()
        .lowercase()
        .replace("ё", "е")
        .replace("-", " ")
        .replace("_", " ")
        .replace(",", " ")
        .replace(".", " ")

    if (normalized.isEmpty()) return null

    val eligibleIDs = districtDisplayNamesMap.keys.filter { id ->
        city?.let { districtBelongsToCity(id, it) } ?: true
    }

    val normalizedTokens = normalized.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.toSet()

    eligibleIDs.firstOrNull { districtID ->
        districtAliases[districtID].orEmpty().any { alias ->
            if (exactOnlyAliases.contains(alias)) {
                normalized == alias || normalizedTokens.contains(alias)
            } else {
                normalized.contains(alias)
            }
        }
    }?.let { return it }

    return districtDisplayNamesMap.entries.firstOrNull { (districtID, name) ->
        if (!eligibleIDs.contains(districtID)) return@firstOrNull false
        normalized.contains(name.lowercase().replace("ё", "е").replace("-", " "))
    }?.key
}

/** Port of `profileDistrictOptions(for:)` - every district id in the city, sorted by label. */
fun districtsForCity(city: SupportedCity): List<String> =
    allDistrictIds.filter { districtBelongsToCity(it, city) }
