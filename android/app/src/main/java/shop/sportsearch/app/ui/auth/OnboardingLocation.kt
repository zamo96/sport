package shop.sportsearch.app.ui.auth

import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import shop.sportsearch.app.R
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.SupportedCity
import shop.sportsearch.app.core.districtAreasById
import shop.sportsearch.app.core.districtBelongsToCity
import shop.sportsearch.app.core.localizedDistrictName
import shop.sportsearch.app.ui.components.AutoSizeText
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.appFontFamily
import shop.sportsearch.app.ui.theme.continuousShape

/** `onboardingDefaultCity` / `onboardingCityOptions` / `onboardingAvailableCities`. */
val onboardingDefaultCity: String = SupportedCity.SAINT_PETERSBURG.wire
val onboardingCityOptions: List<String> = SupportedCity.selectableCases.map { it.wire }

/** Port of `isOnboardingCityAvailable(_:)`. */
fun isOnboardingCityAvailable(city: String): Boolean =
    SupportedCity.resolve(city.trim())?.let { SupportedCity.selectableCases.contains(it) } ?: false

/** Port of `onboardingDistrictOptions(for:)`. */
fun onboardingDistrictOptions(cityName: String): List<String> {
    val city = SupportedCity.resolve(cityName) ?: return emptyList()
    return districtAreasById.values
        .filter { it.city == city }
        .sortedBy { it.label.lowercase() }
        .map { it.id }
}

/** Port of `filteredOnboardingDistricts(_:cityName:)`. */
fun filteredOnboardingDistricts(districts: List<String>, cityName: String): List<String> {
    val city = SupportedCity.resolve(cityName) ?: return emptyList()
    return districts.map { it.lowercase() }.filter { districtBelongsToCity(it, city) }.distinct()
}

/** `onboardingCityImageName(for:)`. */
private fun onboardingCityImage(cityName: String): Int? = when (SupportedCity.resolve(cityName)) {
    SupportedCity.SAINT_PETERSBURG -> R.drawable.onboarding_city_saint_petersburg
    SupportedCity.MOSCOW -> R.drawable.onboarding_city_moscow
    else -> null
}

/** Port of `private enum OnboardingLocationChoice`. */
enum class OnboardingLocationChoice { NEARBY, DISTRICTS }

/** `Color(red: 1.0, green: 0.78, blue: 0.34)` — the "needs attention" amber. */
private val OnboardingAmber = Color(0xFFFFC757)

/** `Color(red: 0.62, green: 0.34, blue: 1.0)` — the districts card's tint. */
private val OnboardingViolet = Color(0xFF9E57FF)

/** Port of `private struct OnboardingSearchLocationSection`. */
@Composable
fun OnboardingSearchLocationSection(
    selectedChoice: OnboardingLocationChoice?,
    selectedCity: String,
    selectedDistricts: List<String>,
    isDetectingLocation: Boolean,
    locationDetectionFailed: Boolean,
    isDetectedDistrictConfirmed: Boolean,
    onNearby: () -> Unit,
    onDistricts: () -> Unit,
) {
    val validDistricts = filteredOnboardingDistricts(selectedDistricts, selectedCity)
    val districtsSummary = validDistricts.take(2)
        .joinToString(", ") { localizedDistrictName(it) ?: it }
        .let { if (validDistricts.size > 2) "$it +${validDistricts.size - 2}" else it }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.10f)))

        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Outlined.Place,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.72f),
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    L10n.string("Where should we look for players?", "Где искать игроков?"),
                    fontFamily = appFontFamily,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = Color.White,
                )
            }
            Text(
                L10n.string(
                    "Choose a city first. You can add districts now or later.",
                    "Сначала выбери город. Районы можно добавить сразу или позже.",
                ),
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.56f),
            )
        }

        // `selectedCityPill`
        when {
            selectedCity.isBlank() -> OnboardingStatusPill(
                Icons.Filled.Error,
                L10n.string("City not selected", "Город не выбран"),
                OnboardingAmber,
            )
            !isOnboardingCityAvailable(selectedCity) -> OnboardingStatusPill(
                Icons.Filled.Warning,
                L10n.string("$selectedCity: clubs coming soon", "$selectedCity скоро: добавляем клубы"),
                OnboardingAmber,
            )
            else -> OnboardingStatusPill(Icons.Filled.Apartment, selectedCity, OnboardingStepPalette.lime)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OnboardingLocationChoiceCard(
                title = L10n.string("Near me", "Рядом со мной"),
                subtitle = nearbySubtitle(
                    selectedChoice,
                    selectedCity,
                    districtsSummary,
                    locationDetectionFailed,
                    isDetectedDistrictConfirmed,
                ),
                icon = Icons.Filled.MyLocation,
                tint = OnboardingStepPalette.lime,
                isSelected = selectedChoice == OnboardingLocationChoice.NEARBY,
                modifier = Modifier.weight(1f),
                onClick = onNearby,
            )

            OnboardingLocationChoiceCard(
                title = L10n.string("Choose city and districts", "Выбрать город и районы"),
                subtitle = cityAndDistrictsSummary(selectedCity, validDistricts, districtsSummary),
                icon = Icons.Filled.Map,
                tint = OnboardingViolet,
                isSelected = selectedChoice == OnboardingLocationChoice.DISTRICTS,
                modifier = Modifier.weight(1f),
                onClick = onDistricts,
            )
        }

        // `locationDetectionStatus`
        if (selectedChoice == OnboardingLocationChoice.NEARBY) {
            when {
                districtsSummary.isNotEmpty() -> {
                    val where = listOf(selectedCity.trim(), districtsSummary)
                        .filter { it.isNotEmpty() }
                        .joinToString(" · ")
                    OnboardingStatusPanel(
                        icon = Icons.Filled.CheckCircle,
                        text = L10n.string(
                            "Searching near $where. You can change or add districts.",
                            "Ищем рядом с $where. Можно изменить или добавить районы.",
                        ),
                        tint = OnboardingStepPalette.lime,
                        buttonTitle = L10n.string("Change city and districts", "Изменить город и районы"),
                        buttonIsFilled = false,
                        onButton = onDistricts,
                    )
                }
                isDetectedDistrictConfirmed && selectedCity.isNotBlank() -> OnboardingStatusPill(
                    Icons.Filled.MyLocation,
                    L10n.string("City detected: $selectedCity", "Город определён: $selectedCity"),
                    OnboardingStepPalette.lime,
                )
                isDetectingLocation -> Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(continuousShape(16.dp))
                        .background(Color.White.copy(alpha = 0.07f))
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        color = Color.White.copy(alpha = 0.72f),
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        L10n.string(
                            "Detecting your city and district from your location",
                            "Определяем город и район по геолокации",
                        ),
                        fontFamily = appFontFamily,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.72f),
                    )
                }
                locationDetectionFailed -> OnboardingStatusPanel(
                    icon = Icons.Filled.Warning,
                    text = L10n.string(
                        "We couldn't detect your city and district. Choose them manually.",
                        "Не удалось определить город и район по гео. Выбери вручную.",
                    ),
                    tint = OnboardingAmber,
                    buttonTitle = L10n.string("Choose city and districts", "Выбрать город и районы"),
                    buttonIsFilled = true,
                    onButton = onDistricts,
                )
            }
        }
    }
}

/** `OnboardingSearchLocationSection.nearbySubtitle`. */
private fun nearbySubtitle(
    choice: OnboardingLocationChoice?,
    city: String,
    districtsSummary: String,
    detectionFailed: Boolean,
    isConfirmed: Boolean,
): String {
    if (choice != OnboardingLocationChoice.NEARBY) {
        return L10n.string("Detect city and district", "Определить город и район")
    }
    if (districtsSummary.isNotEmpty()) {
        return "${city.ifEmpty { onboardingDefaultCity }} · $districtsSummary"
    }
    if (detectionFailed) {
        return city.ifEmpty { L10n.string("Could not detect", "Не удалось определить") }
    }
    if (isConfirmed && city.isNotEmpty()) return city
    return if (city.isEmpty()) {
        L10n.string("Detecting city", "Определяем город")
    } else {
        L10n.string("$city · detecting district", "$city · определяем район")
    }
}

/** `OnboardingSearchLocationSection.cityAndDistrictsSummary`. */
private fun cityAndDistrictsSummary(
    selectedCity: String,
    validDistricts: List<String>,
    districtsSummary: String,
): String {
    val city = selectedCity.trim()
    if (city.isEmpty()) return L10n.string("Choose a city", "Открыть выбор города")
    if (!isOnboardingCityAvailable(city)) {
        return L10n.string("$city · clubs coming soon", "$city · добавляем клубы")
    }
    if (validDistricts.isEmpty()) return city
    return "$city · $districtsSummary"
}

@Composable
private fun OnboardingStatusPill(icon: ImageVector, text: String, tint: Color) {
    val shape = continuousShape(16.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(tint.copy(alpha = if (tint == OnboardingStepPalette.lime) 0.12f else 0.11f))
            .border(1.dp, tint.copy(alpha = if (tint == OnboardingStepPalette.lime) 0.24f else 0.22f), shape)
            .padding(horizontal = 12.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(13.dp))
        Text(
            text,
            fontFamily = appFontFamily,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = tint,
        )
    }
}

@Composable
private fun OnboardingStatusPanel(
    icon: ImageVector,
    text: String,
    tint: Color,
    buttonTitle: String,
    buttonIsFilled: Boolean,
    onButton: () -> Unit,
) {
    val shape = continuousShape(16.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(tint.copy(alpha = if (buttonIsFilled) 0.11f else 0.12f))
            .border(1.dp, tint.copy(alpha = if (buttonIsFilled) 0.22f else 0.26f), shape)
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(13.dp))
            Text(
                text,
                fontFamily = appFontFamily,
                fontSize = 12.sp,
                fontWeight = if (buttonIsFilled) FontWeight.SemiBold else FontWeight.Bold,
                color = tint,
            )
        }

        val buttonShape = continuousShape(14.dp)
        Text(
            buttonTitle,
            modifier = Modifier
                .fillMaxWidth()
                .height(38.dp)
                .clip(buttonShape)
                .background(if (buttonIsFilled) OnboardingAmber else Color.White.copy(alpha = 0.10f))
                .then(
                    if (buttonIsFilled) {
                        Modifier
                    } else {
                        Modifier.border(1.dp, Color.White.copy(alpha = 0.12f), buttonShape)
                    },
                )
                .clickable(onClick = onButton)
                .padding(top = 10.dp),
            fontFamily = appFontFamily,
            fontSize = 13.sp,
            fontWeight = FontWeight.ExtraBold,
            color = if (buttonIsFilled) Color.Black.copy(alpha = 0.88f) else Color.White,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

/** Port of `private struct OnboardingLocationChoiceCard`. */
@Composable
private fun OnboardingLocationChoiceCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    tint: Color,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = continuousShape(22.dp)
    Column(
        modifier = modifier
            .heightIn(min = 112.dp)
            .appShadow(
                if (isSelected) tint.copy(alpha = 0.14f) else Color.Black.copy(alpha = 0.18f),
                18.dp,
                0.dp,
                10.dp,
                shape,
            )
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(
                        Color.White.copy(alpha = if (isSelected) 0.10f else 0.07f),
                        OnboardingStepPalette.panelRaised.copy(alpha = 0.88f),
                    ),
                ),
            )
            .border(
                if (isSelected) 1.5.dp else 1.dp,
                if (isSelected) tint else Color.White.copy(alpha = 0.12f),
                shape,
            )
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(
            modifier = Modifier.size(42.dp).clip(CircleShape).background(tint.copy(alpha = 0.14f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        }

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
                AutoSizeText(
                    text = title,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = Color.White,
                    maxLines = 2,
                    minScale = 0.78f,
                    modifier = Modifier.weight(1f),
                )
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier.size(13.dp),
                )
            }

            Text(
                subtitle,
                fontFamily = appFontFamily,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.56f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Port of `private struct OnboardingDistrictPickerSheet`. */
@Composable
fun OnboardingDistrictPickerSheet(
    selectedCity: String,
    selectedDistricts: List<String>,
    automaticallyDetectedDistrict: String?,
    startsWithDistricts: Boolean,
    onDetectAutomatically: () -> Unit,
    onDone: (String, List<String>) -> Unit,
) {
    val haptics = rememberAppHaptics()
    val initialCity = if (isOnboardingCityAvailable(selectedCity)) {
        selectedCity
    } else {
        onboardingCityOptions.firstOrNull().orEmpty()
    }

    var showsDistricts by remember {
        mutableStateOf(startsWithDistricts && isOnboardingCityAvailable(initialCity))
    }
    var draftCity by remember { mutableStateOf(initialCity) }
    var draftDistricts by remember {
        mutableStateOf(filteredOnboardingDistricts(selectedDistricts, initialCity))
    }

    val canSubmit = isOnboardingCityAvailable(draftCity)
    val districtOptions = onboardingDistrictOptions(draftCity)

    Box(modifier = Modifier.fillMaxSize().background(OnboardingStepPalette.panel)) {
        OnboardingIntroBackground(Modifier.fillMaxSize())

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp),
        ) {
            Box(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    modifier = Modifier
                        .width(42.dp)
                        .height(5.dp)
                        .clip(RoundedCornerShape(percent = 50))
                        .background(Color.White.copy(alpha = 0.22f)),
                )
            }

            // `header`
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (showsDistricts) {
                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(Color.White.copy(alpha = 0.08f))
                                .clickable {
                                    showsDistricts = false
                                    haptics.selection()
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                                contentDescription = L10n.string(
                                    "Back to city selection",
                                    "Назад к выбору города",
                                ),
                                tint = Color.White,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }

                    Spacer(Modifier.weight(1f))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        ProgressSegment(true)
                        ProgressSegment(showsDistricts)
                    }
                    Spacer(Modifier.weight(1f))

                    if (showsDistricts) Spacer(Modifier.size(38.dp))
                }

                Text(
                    if (showsDistricts) {
                        L10n.string("Where is it convenient for you to play?", "Где вам удобно играть?")
                    } else {
                        L10n.string("Where will you play?", "Где вы будете играть?")
                    },
                    fontFamily = appFontFamily,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = Color.White,
                )

                Text(
                    if (showsDistricts) {
                        L10n.string(
                            "Choose one or more districts. You can skip this step.",
                            "Выберите один или несколько районов. Этот шаг можно пропустить.",
                        )
                    } else {
                        L10n.string(
                            "Choose a city so we can show nearby games and clubs.",
                            "Выберите город, чтобы мы показывали игры и клубы рядом.",
                        )
                    },
                    fontFamily = appFontFamily,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.62f),
                )

                Text(
                    if (showsDistricts) L10n.string("2 of 2", "2 из 2") else L10n.string("1 of 2", "1 из 2"),
                    modifier = Modifier.fillMaxWidth(),
                    fontFamily = appFontFamily,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White.copy(alpha = 0.52f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(top = 18.dp, bottom = 14.dp),
                verticalArrangement = Arrangement.spacedBy(if (showsDistricts) 20.dp else 22.dp),
            ) {
                if (showsDistricts) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 50.dp)
                            .clip(continuousShape(16.dp))
                            .background(Color.White.copy(alpha = 0.07f))
                            .padding(horizontal = 14.dp, vertical = 13.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Outlined.Place,
                            contentDescription = null,
                            tint = OnboardingStepPalette.lime,
                            modifier = Modifier.size(17.dp),
                        )
                        Text(
                            draftCity,
                            fontFamily = appFontFamily,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }

                    if (districtOptions.isEmpty()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(continuousShape(16.dp))
                                .background(Color.White.copy(alpha = 0.07f))
                                .padding(14.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Icon(
                                Icons.Filled.Info,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.68f),
                                modifier = Modifier.size(16.dp),
                            )
                            Text(
                                L10n.string(
                                    "Districts haven't been added for this city yet. You can continue without them.",
                                    "Для этого города районы пока не добавлены. Можно продолжить без них.",
                                ),
                                fontFamily = appFontFamily,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White.copy(alpha = 0.68f),
                            )
                        }
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            PickerSectionTitle(L10n.string("Districts", "Районы"))
                            districtOptions.forEach { district ->
                                DistrictButton(
                                    district = district,
                                    isSelected = draftDistricts.contains(district),
                                    isAutomaticallyDetected = district == automaticallyDetectedDistrict,
                                ) {
                                    draftDistricts = if (draftDistricts.contains(district)) {
                                        draftDistricts - district
                                    } else {
                                        draftDistricts + district
                                    }
                                    haptics.selection()
                                }
                            }
                        }
                    }

                    if (draftDistricts.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            PickerSectionTitle(L10n.string("Selected places", "Выбранные места"))
                            draftDistricts.forEach { district ->
                                val title = localizedDistrictName(district) ?: district
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .heightIn(min = 52.dp)
                                        .clip(continuousShape(16.dp))
                                        .background(Color.White.copy(alpha = 0.07f))
                                        .padding(horizontal = 14.dp),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(
                                        Icons.Outlined.Place,
                                        contentDescription = null,
                                        tint = OnboardingStepPalette.lime,
                                        modifier = Modifier.size(17.dp),
                                    )
                                    Text(
                                        title,
                                        modifier = Modifier.weight(1f),
                                        fontFamily = appFontFamily,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = Color.White,
                                    )
                                    Box(
                                        modifier = Modifier
                                            .size(34.dp)
                                            .clickable {
                                                draftDistricts = draftDistricts - district
                                                haptics.selection()
                                            },
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(
                                            Icons.Filled.Close,
                                            contentDescription = L10n.string("Remove $title", "Удалить $title"),
                                            tint = Color.White.copy(alpha = 0.72f),
                                            modifier = Modifier.size(13.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // `cityScreen`
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 76.dp)
                            .clip(continuousShape(18.dp))
                            .background(Color.White.copy(alpha = 0.07f))
                            .border(1.dp, Color.White.copy(alpha = 0.10f), continuousShape(18.dp))
                            .clickable(onClick = onDetectAutomatically)
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(42.dp)
                                .clip(CircleShape)
                                .background(OnboardingStepPalette.lime.copy(alpha = 0.12f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Filled.MyLocation,
                                contentDescription = null,
                                tint = OnboardingStepPalette.lime,
                                modifier = Modifier.size(21.dp),
                            )
                        }

                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(
                                L10n.string("Detect automatically", "Определить автоматически"),
                                fontFamily = appFontFamily,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                            )
                            Text(
                                L10n.string(
                                    "Use your current location",
                                    "Используем ваше текущее местоположение",
                                ),
                                fontFamily = appFontFamily,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color.White.copy(alpha = 0.56f),
                            )
                        }

                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = Color.White.copy(alpha = 0.66f),
                            modifier = Modifier.size(15.dp),
                        )
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        PickerSectionTitle(L10n.string("Available cities", "Доступные города"))
                        onboardingCityOptions.forEach { city ->
                            CityButton(city, draftCity == city) {
                                if (draftCity != city) draftDistricts = emptyList()
                                draftCity = city
                                haptics.selection()
                            }
                        }
                    }
                }
            }

            // `primaryButton`
            Text(
                if (showsDistricts) L10n.string("Done", "Готово") else L10n.string("Continue", "Продолжить"),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp, bottom = 10.dp)
                    .height(56.dp)
                    .clip(continuousShape(18.dp))
                    .background(if (canSubmit) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.12f))
                    .clickable(enabled = canSubmit) {
                        if (showsDistricts) {
                            onDone(draftCity, filteredOnboardingDistricts(draftDistricts, draftCity))
                            haptics.success()
                        } else {
                            showsDistricts = true
                            haptics.selection()
                        }
                    }
                    .padding(top = 17.dp),
                fontFamily = appFontFamily,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = if (canSubmit) Color.Black.copy(alpha = 0.88f) else Color.White.copy(alpha = 0.38f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
private fun ProgressSegment(isActive: Boolean) {
    Box(
        modifier = Modifier
            .width(38.dp)
            .height(5.dp)
            .clip(RoundedCornerShape(percent = 50))
            .background(if (isActive) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.16f)),
    )
}

@Composable
private fun PickerSectionTitle(title: String) {
    Text(
        title,
        fontFamily = appFontFamily,
        fontSize = 15.sp,
        fontWeight = FontWeight.Bold,
        color = Color.White.copy(alpha = 0.72f),
    )
}

/** `OnboardingDistrictPickerSheet.cityButton(_:)`. */
@Composable
private fun CityButton(city: String, isSelected: Boolean, onClick: () -> Unit) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 68.dp)
            .clip(shape)
            .background(if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.07f))
            .border(
                1.dp,
                if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.10f),
                shape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        onboardingCityImage(city)?.let { image ->
            Image(
                painter = painterResource(image),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(56.dp).clip(continuousShape(14.dp)),
            )
        }

        Text(
            city,
            modifier = Modifier.weight(1f),
            fontFamily = appFontFamily,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold,
            color = if (isSelected) Color.Black.copy(alpha = 0.86f) else Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )

        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = null,
            tint = if (isSelected) Color.Black.copy(alpha = 0.82f) else Color.White.copy(alpha = 0.48f),
            modifier = Modifier.size(22.dp),
        )
    }
}

/** `OnboardingDistrictPickerSheet.districtButton(_:)`. */
@Composable
private fun DistrictButton(
    district: String,
    isSelected: Boolean,
    isAutomaticallyDetected: Boolean,
    onClick: () -> Unit,
) {
    val title = localizedDistrictName(district) ?: district
    val shape = continuousShape(16.dp)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(shape)
            .background(if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.07f))
            .border(
                1.dp,
                if (isSelected) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.10f),
                shape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            AutoSizeText(
                text = title,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) Color.Black.copy(alpha = 0.86f) else Color.White,
                maxLines = 1,
                minScale = 0.72f,
            )
            if (isAutomaticallyDetected) {
                AutoSizeText(
                    text = L10n.string("Detected from your location", "Определено по геопозиции"),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (isSelected) Color.Black.copy(alpha = 0.62f) else OnboardingStepPalette.lime,
                    maxLines = 1,
                    minScale = 0.75f,
                )
            }
        }

        Icon(
            if (isSelected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = null,
            tint = if (isSelected) Color.Black.copy(alpha = 0.86f) else Color.White,
            modifier = Modifier.size(20.dp),
        )
    }
}

/** Port of `private struct OnboardingAvailabilityEditorCard`. */
@Composable
fun OnboardingAvailabilityEditorCard(content: @Composable () -> Unit) {
    val shape = continuousShape(24.dp)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .appShadow(Color.Black.copy(alpha = 0.18f), 18.dp, 0.dp, 10.dp, shape)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.94f))
            .border(1.dp, Color.White.copy(alpha = 0.22f), shape)
            .padding(horizontal = 10.dp, vertical = 12.dp),
    ) {
        content()
    }
}
