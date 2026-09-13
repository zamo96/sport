package shop.sportsearch.app.core

import androidx.compose.ui.graphics.Color

/**
 * Port of `DistrictMapArea` and `districtAreasByID` in
 * ios/TennisSearchIOS/Views/CourtsView.swift.
 *
 * Each polygon is written latitude-first here; the Swift literal lists the raw
 * pairs longitude-first and flips them in `coordinates`, so the numbers below
 * are the same points already in `(lat, lng)` order.
 */
data class DistrictMapArea(
    val id: String,
    val label: String,
    val color: Color,
    val city: SupportedCity = SupportedCity.SAINT_PETERSBURG,
    /** `(latitude, longitude)` pairs. */
    val polygon: List<Pair<Double, Double>>,
) {
    /** `DistrictMapArea.centerCoordinate` - the polygon's centroid. */
    val centerCoordinate: LatLng
        get() {
            if (polygon.isEmpty()) return LatLng(59.9343, 30.3351)
            return LatLng(polygon.sumOf { it.first } / polygon.size, polygon.sumOf { it.second } / polygon.size)
        }
}

private val districtAreaList = listOf(
    DistrictMapArea(
        id = "admiralteysky",
        label = "Адмиралтейский",
        color = Color(0xFFD47A45),
        polygon = listOf(59.895 to 30.225, 59.895 to 30.35, 59.845 to 30.345, 59.84 to 30.24),
    ),
    DistrictMapArea(
        id = "vasileostrovsky",
        label = "Василеостровский",
        color = Color(0xFF7B61FF),
        polygon = listOf(59.962 to 30.19, 59.962 to 30.276, 59.925 to 30.292, 59.913 to 30.205),
    ),
    DistrictMapArea(
        id = "vyborgsky",
        label = "Выборгский",
        color = Color(0xFF4B7BE5),
        polygon = listOf(60.105 to 30.205, 60.105 to 30.435, 60.01 to 30.43, 60.002 to 30.235),
    ),
    DistrictMapArea(
        id = "kalininsky",
        label = "Калининский",
        color = Color(0xFF23A27A),
        polygon = listOf(60.055 to 30.292, 60.055 to 30.497, 59.982 to 30.478, 59.982 to 30.32),
    ),
    DistrictMapArea(
        id = "kirovsky",
        label = "Кировский",
        color = Color(0xFFA8663A),
        polygon = listOf(59.918 to 30.142, 59.918 to 30.301, 59.833 to 30.305, 59.83 to 30.16),
    ),
    DistrictMapArea(
        id = "kolpinsky",
        label = "Колпинский",
        color = Color(0xFFB47BDA),
        polygon = listOf(59.815 to 30.46, 59.815 to 30.72, 59.665 to 30.74, 59.665 to 30.49),
    ),
    DistrictMapArea(
        id = "krasnogvardeysky",
        label = "Красногвардейский",
        color = Color(0xFFB86482),
        polygon = listOf(59.995 to 30.345, 59.995 to 30.535, 59.91 to 30.54, 59.91 to 30.36),
    ),
    DistrictMapArea(
        id = "krasnoselsky",
        label = "Красносельский",
        color = Color(0xFFD98B5C),
        polygon = listOf(59.885 to 29.98, 59.885 to 30.265, 59.73 to 30.27, 59.73 to 30.03),
    ),
    DistrictMapArea(
        id = "kronshtadtsky",
        label = "Кронштадтский",
        color = Color(0xFF4A92A2),
        polygon = listOf(60.055 to 29.64, 60.055 to 29.86, 59.95 to 29.86, 59.95 to 29.64),
    ),
    DistrictMapArea(
        id = "kurortny",
        label = "Курортный",
        color = Color(0xFF65A06C),
        polygon = listOf(60.18 to 29.76, 60.18 to 30.24, 60.01 to 30.24, 60.01 to 29.78),
    ),
    DistrictMapArea(
        id = "moskovsky",
        label = "Московский",
        color = Color(0xFFC66A63),
        polygon = listOf(59.925 to 30.173, 59.925 to 30.355, 59.81 to 30.35, 59.81 to 30.265),
    ),
    DistrictMapArea(
        id = "nevsky",
        label = "Невский",
        color = Color(0xFFE85B7B),
        polygon = listOf(59.926 to 30.368, 59.926 to 30.57, 59.848 to 30.585, 59.84 to 30.39),
    ),
    DistrictMapArea(
        id = "petrogradsky",
        label = "Петроградский",
        color = Color(0xFF2F7A65),
        polygon = listOf(59.983 to 30.233, 59.983 to 30.332, 59.948 to 30.343, 59.942 to 30.251),
    ),
    DistrictMapArea(
        id = "petrodvortsovy",
        label = "Петродворцовый",
        color = Color(0xFF9B7A45),
        polygon = listOf(59.95 to 29.63, 59.95 to 30.15, 59.78 to 30.14, 59.78 to 29.67),
    ),
    DistrictMapArea(
        id = "primorsky",
        label = "Приморский",
        color = Color(0xFF548BFF),
        polygon = listOf(60.04 to 30.153, 60.04 to 30.318, 59.982 to 30.339, 59.956 to 30.205),
    ),
    DistrictMapArea(
        id = "pushkinsky",
        label = "Пушкинский",
        color = Color(0xFF8C9A4F),
        polygon = listOf(59.79 to 30.17, 59.79 to 30.62, 59.57 to 30.63, 59.57 to 30.22),
    ),
    DistrictMapArea(
        id = "frunzensky",
        label = "Фрунзенский",
        color = Color(0xFFC76A5E),
        polygon = listOf(59.91 to 30.28, 59.91 to 30.46, 59.81 to 30.46, 59.81 to 30.29),
    ),
    DistrictMapArea(
        id = "central",
        label = "Центральный",
        color = Color(0xFFD96A47),
        polygon = listOf(59.948 to 30.314, 59.948 to 30.402, 59.917 to 30.412, 59.907 to 30.33, 59.924 to 30.302),
    ),
    DistrictMapArea(
        id = "moscow_central",
        label = "Центральный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.795 to 37.545, 55.805 to 37.626, 55.775 to 37.704, 55.713 to 37.694, 55.695 to 37.620, 55.724 to 37.548),
    ),
    DistrictMapArea(
        id = "moscow_northern",
        label = "Северный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.925 to 37.455, 55.965 to 37.545, 55.945 to 37.665, 55.806 to 37.704, 55.805 to 37.626, 55.795 to 37.545, 55.825 to 37.475),
    ),
    DistrictMapArea(
        id = "moscow_northeastern",
        label = "Северо-Восточный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.945 to 37.665, 55.925 to 37.835, 55.830 to 37.850, 55.775 to 37.704, 55.806 to 37.704),
    ),
    DistrictMapArea(
        id = "moscow_eastern",
        label = "Восточный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.830 to 37.850, 55.820 to 37.955, 55.705 to 37.970, 55.675 to 37.815, 55.713 to 37.694, 55.775 to 37.704),
    ),
    DistrictMapArea(
        id = "moscow_southeastern",
        label = "Юго-Восточный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.713 to 37.694, 55.675 to 37.815, 55.585 to 37.855, 55.565 to 37.710, 55.650 to 37.625, 55.695 to 37.620),
    ),
    DistrictMapArea(
        id = "moscow_southern",
        label = "Южный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.695 to 37.620, 55.650 to 37.625, 55.565 to 37.710, 55.515 to 37.650, 55.560 to 37.500, 55.650 to 37.515, 55.724 to 37.548),
    ),
    DistrictMapArea(
        id = "moscow_southwestern",
        label = "Юго-Западный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.724 to 37.548, 55.650 to 37.515, 55.560 to 37.500, 55.560 to 37.355, 55.665 to 37.350, 55.735 to 37.455),
    ),
    DistrictMapArea(
        id = "moscow_western",
        label = "Западный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.825 to 37.455, 55.795 to 37.545, 55.724 to 37.548, 55.735 to 37.455, 55.665 to 37.350, 55.700 to 37.260, 55.805 to 37.285),
    ),
    DistrictMapArea(
        id = "moscow_northwestern",
        label = "Северо-Западный административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.805 to 37.285, 55.825 to 37.455, 55.925 to 37.455, 55.930 to 37.315, 55.875 to 37.235),
    ),
    DistrictMapArea(
        id = "moscow_zelenograd",
        label = "Зеленоградский административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(56.030 to 37.130, 56.030 to 37.270, 55.945 to 37.285, 55.940 to 37.145),
    ),
    DistrictMapArea(
        id = "moscow_novomoskovsky",
        label = "Новомосковский административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.700 to 37.260, 55.665 to 37.350, 55.560 to 37.355, 55.560 to 37.500, 55.425 to 37.410, 55.465 to 37.185),
    ),
    DistrictMapArea(
        id = "moscow_troitsky",
        label = "Троицкий административный округ",
        color = Color(0xFF24D68A),
        city = SupportedCity.MOSCOW,
        polygon = listOf(55.465 to 37.185, 55.425 to 37.410, 55.230 to 37.345, 55.220 to 36.815, 55.455 to 36.905),
    ),
    DistrictMapArea(
        id = "kazan_aviastroitelny",
        label = "Авиастроительный",
        color = Color(0xFF24D68A),
        city = SupportedCity.KAZAN,
        polygon = listOf(55.925 to 49.045, 55.925 to 49.205, 55.855 to 49.205, 55.835 to 49.105, 55.865 to 49.025),
    ),
    DistrictMapArea(
        id = "kazan_vakhitovsky",
        label = "Вахитовский",
        color = Color(0xFF24D68A),
        city = SupportedCity.KAZAN,
        polygon = listOf(55.815 to 49.060, 55.825 to 49.145, 55.770 to 49.195, 55.730 to 49.145, 55.750 to 49.055),
    ),
    DistrictMapArea(
        id = "kazan_kirovsky",
        label = "Кировский",
        color = Color(0xFF24D68A),
        city = SupportedCity.KAZAN,
        polygon = listOf(55.900 to 48.825, 55.865 to 49.025, 55.815 to 49.060, 55.750 to 49.055, 55.730 to 48.865, 55.815 to 48.765),
    ),
    DistrictMapArea(
        id = "kazan_moskovsky",
        label = "Московский",
        color = Color(0xFF24D68A),
        city = SupportedCity.KAZAN,
        polygon = listOf(55.865 to 49.025, 55.835 to 49.105, 55.795 to 49.120, 55.815 to 49.060, 55.825 to 48.930),
    ),
    DistrictMapArea(
        id = "kazan_novo_savinovsky",
        label = "Ново-Савиновский",
        color = Color(0xFF24D68A),
        city = SupportedCity.KAZAN,
        polygon = listOf(55.835 to 49.105, 55.850 to 49.245, 55.785 to 49.260, 55.770 to 49.195, 55.825 to 49.145),
    ),
    DistrictMapArea(
        id = "kazan_privolzhsky",
        label = "Приволжский",
        color = Color(0xFF24D68A),
        city = SupportedCity.KAZAN,
        polygon = listOf(55.750 to 49.055, 55.730 to 49.145, 55.655 to 49.250, 55.585 to 49.145, 55.640 to 48.930, 55.730 to 48.865),
    ),
    DistrictMapArea(
        id = "kazan_sovetsky",
        label = "Советский",
        color = Color(0xFF24D68A),
        city = SupportedCity.KAZAN,
        polygon = listOf(55.770 to 49.195, 55.785 to 49.260, 55.775 to 49.385, 55.650 to 49.410, 55.655 to 49.250, 55.730 to 49.145),
    ),
)

val districtAreasById: Map<String, DistrictMapArea> = districtAreaList.associateBy { it.id }
