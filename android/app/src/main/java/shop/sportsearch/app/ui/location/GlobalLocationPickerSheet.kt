package shop.sportsearch.app.ui.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.GeoCountry
import shop.sportsearch.app.core.GeoPlace
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.LocationSource
import shop.sportsearch.app.data.TennisRepository
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.continuousShape

private enum class PickerScreen { COUNTRIES, CITIES, DETECTED }

private val accentGreen = Color(0xFF4CAF50)

/**
 * Port of `struct GlobalLocationPickerSheet` in
 * ios/TennisSearchIOS/Views/LocationPickerView.swift.
 *
 * iOS reads the coordinate through CoreLocation and reverse-geocodes it on the
 * server; Android uses the platform LocationManager's last known fix and calls
 * the same `reverseGeocodeLocation` endpoint.
 */
@SuppressLint("MissingPermission")
@Composable
fun GlobalLocationPickerSheet(
    repository: TennisRepository,
    initialLocation: GeoPlace?,
    automaticallyRequestsLocation: Boolean,
    onDismiss: () -> Unit,
    onSelect: (GeoPlace, LocationSource) -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val scope = rememberCoroutineScope()
    val androidContext = LocalContext.current

    var screen by remember { mutableStateOf(PickerScreen.COUNTRIES) }
    var countries by remember { mutableStateOf<List<GeoCountry>>(emptyList()) }
    var citySuggestions by remember { mutableStateOf<List<GeoPlace>>(emptyList()) }
    var citySearchResults by remember { mutableStateOf<List<GeoPlace>>(emptyList()) }
    var selectedCountry by remember { mutableStateOf<GeoCountry?>(null) }
    var detectedPlace by remember { mutableStateOf<GeoPlace?>(null) }
    var countryQuery by remember { mutableStateOf("") }
    var cityQuery by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var didLoadCitySuggestions by remember { mutableStateOf(false) }
    var didSearchCities by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    suspend fun loadCountries() {
        isLoading = true
        runCatching { repository.fetchLocationCountries(null) }
            .onSuccess {
                countries = it
                errorMessage = null
            }
            .onFailure {
                errorMessage = L10n.string(
                    "Could not load the country list.",
                    "Не удалось загрузить список стран.",
                )
            }
        isLoading = false
    }

    suspend fun loadCitySuggestions(country: GeoCountry) {
        isLoading = true
        runCatching { repository.fetchLocationCities(country.code, "", 20) }
            .onSuccess {
                citySuggestions = it
                didLoadCitySuggestions = true
                errorMessage = null
            }
            .onFailure { errorMessage = it.message }
        isLoading = false
    }

    suspend fun loadCities() {
        val country = selectedCountry ?: return
        val query = cityQuery.trim()
        if (query.length < 2) return
        isLoading = true
        runCatching { repository.fetchLocationCities(country.code, query, 20) }
            .onSuccess {
                citySearchResults = it
                didSearchCities = true
                errorMessage = null
            }
            .onFailure { errorMessage = it.message }
        isLoading = false
    }

    fun detectLocation() {
        errorMessage = null
        isLoading = true

        val granted = ContextCompat.checkSelfPermission(
            androidContext,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        if (!granted) {
            isLoading = false
            errorMessage = L10n.string(
                "Location is unavailable. Choose a country and city manually.",
                "Геопозиция недоступна. Выберите страну и город вручную.",
            )
            return
        }

        val manager = androidContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val fix = manager.getProviders(true)
            .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }

        if (fix == null) {
            isLoading = false
            errorMessage = L10n.string(
                "Location is unavailable. Choose a country and city manually.",
                "Геопозиция недоступна. Выберите страну и город вручную.",
            )
            return
        }

        scope.launch {
            runCatching { repository.reverseGeocodeLocation(fix.latitude, fix.longitude) }
                .onSuccess {
                    detectedPlace = it
                    screen = PickerScreen.DETECTED
                }
                .onFailure {
                    errorMessage = L10n.string(
                        "Location is unavailable. Choose a country and city manually.",
                        "Геопозиция недоступна. Выберите страну и город вручную.",
                    )
                }
            isLoading = false
        }
    }

    val locationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) detectLocation() else isLoading = false }

    LaunchedEffect(Unit) {
        loadCountries()
        if (automaticallyRequestsLocation && initialLocation == null) {
            locationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Color.Black).statusBarsPadding()) {
        // header
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(top = 18.dp, bottom = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (screen != PickerScreen.COUNTRIES) {
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.08f))
                            .clickable {
                                screen = PickerScreen.COUNTRIES
                                detectedPlace = null
                                errorMessage = null
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            null,
                            tint = Color.White,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                Text(
                    L10n.string("Close", "Закрыть"),
                    style = AppText.subheadlineSemibold,
                    color = Color.White,
                    modifier = Modifier.clickable(onClick = onDismiss),
                )
            }

            Text(
                when (screen) {
                    PickerScreen.COUNTRIES -> L10n.string("Choose a country", "Выберите страну")
                    PickerScreen.CITIES -> L10n.string("Choose a city", "Выберите город")
                    PickerScreen.DETECTED -> L10n.string("Location found", "Местоположение найдено")
                },
                fontSize = 28.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
            )

            Text(
                when (screen) {
                    PickerScreen.COUNTRIES -> L10n.string(
                        "Players and clubs are picked inside the chosen city.",
                        "Игроки и клубы подбираются внутри выбранного города.",
                    )
                    PickerScreen.CITIES -> L10n.string(
                        "Pick from the suggestions or search by name.",
                        "Выберите из подсказок или найдите город по названию.",
                    )
                    PickerScreen.DETECTED -> L10n.string(
                        "Confirm the city before we save it.",
                        "Подтвердите город перед сохранением.",
                    )
                },
                style = AppText.subheadline,
                color = Color.White.copy(alpha = 0.58f),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (screen) {
                PickerScreen.COUNTRIES -> {
                    LocationRow(
                        title = if (isLoading) {
                            L10n.string("Finding your location", "Определяем местоположение")
                        } else {
                            L10n.string("Use my location", "Определить автоматически")
                        },
                        subtitle = L10n.string(
                            "We will show the country and city before saving.",
                            "Покажем найденные страну и город перед сохранением",
                        ),
                        icon = Icons.Filled.MyLocation,
                        showsChevron = !isLoading,
                        isBusy = isLoading,
                    ) { locationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION) }

                    errorMessage?.let { message ->
                        ErrorPanel(message, showsRetry = countries.isEmpty(), isLoading = isLoading) {
                            scope.launch { loadCountries() }
                        }
                    }

                    SearchField(
                        placeholder = L10n.string("Search for a country", "Найти страну"),
                        value = countryQuery,
                        onValueChange = { countryQuery = it },
                    )

                    if (isLoading && countries.isEmpty()) {
                        Box(modifier = Modifier.fillMaxWidth().padding(top = 28.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp)
                        }
                    } else {
                        val query = countryQuery.trim()
                        val filtered = if (query.isEmpty()) {
                            countries
                        } else {
                            countries.filter {
                                it.name.contains(query, ignoreCase = true) ||
                                    it.code.contains(query, ignoreCase = true)
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            filtered.forEach { country ->
                                LocationRow(
                                    title = country.name,
                                    subtitle = country.code,
                                    icon = Icons.Filled.Public,
                                    leadingText = country.flagEmoji,
                                    showsChevron = true,
                                ) {
                                    selectedCountry = country
                                    cityQuery = ""
                                    citySuggestions = emptyList()
                                    citySearchResults = emptyList()
                                    didLoadCitySuggestions = false
                                    didSearchCities = false
                                    errorMessage = null
                                    screen = PickerScreen.CITIES
                                    scope.launch { loadCitySuggestions(country) }
                                }
                            }
                        }
                    }
                }

                PickerScreen.CITIES -> {
                    selectedCountry?.let { country ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(country.flagEmoji, fontSize = 24.sp)
                            Text(country.name, style = AppText.subheadlineSemibold, color = accentGreen)
                        }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(modifier = Modifier.weight(1f)) {
                            SearchField(
                                placeholder = L10n.string("Search for a city", "Найти город"),
                                value = cityQuery,
                                onValueChange = {
                                    cityQuery = it
                                    citySearchResults = emptyList()
                                    didSearchCities = false
                                    errorMessage = null
                                },
                            )
                        }
                        Box(
                            modifier = Modifier
                                .size(50.dp)
                                .clip(RoundedCornerShape(16.dp))
                                .background(accentGreen)
                                .clickable(enabled = cityQuery.trim().length >= 2 && !isLoading) {
                                    scope.launch { loadCities() }
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.Search, null, tint = Color.Black, modifier = Modifier.size(18.dp))
                        }
                    }

                    when {
                        isLoading -> Box(
                            modifier = Modifier.fillMaxWidth().padding(top = 28.dp),
                            contentAlignment = Alignment.Center,
                        ) { CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp) }

                        errorMessage != null -> ErrorPanel(errorMessage!!, showsRetry = true, isLoading = isLoading) {
                            scope.launch {
                                if (cityQuery.trim().isEmpty()) {
                                    selectedCountry?.let { loadCitySuggestions(it) }
                                } else {
                                    loadCities()
                                }
                            }
                        }

                        else -> {
                            val displayed = if (cityQuery.trim().isEmpty()) citySuggestions else citySearchResults
                            if (displayed.isEmpty()) {
                                val query = cityQuery.trim()
                                val message = when {
                                    query.isEmpty() && didLoadCitySuggestions -> L10n.string(
                                        "No city suggestions are ready for this country yet. Search by name.",
                                        "Для этой страны пока нет готовых предложений. Найдите город по названию.",
                                    )
                                    query.isEmpty() -> L10n.string(
                                        "Loading available cities…",
                                        "Загружаем доступные города…",
                                    )
                                    query.length < 2 -> L10n.string(
                                        "Enter at least 2 characters and tap search.",
                                        "Введите минимум 2 символа и нажмите кнопку поиска",
                                    )
                                    didSearchCities -> L10n.string(
                                        "City not found. Check the spelling.",
                                        "Город не найден. Проверьте написание.",
                                    )
                                    else -> L10n.string(
                                        "Tap search to find a city.",
                                        "Нажмите кнопку поиска, чтобы найти город",
                                    )
                                }
                                Text(
                                    message,
                                    style = AppText.subheadline,
                                    color = Color.White.copy(alpha = 0.52f),
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.fillMaxWidth().padding(top = 28.dp),
                                )
                            } else {
                                Text(
                                    if (cityQuery.trim().isEmpty()) {
                                        L10n.string("Major cities", "Крупные города")
                                    } else {
                                        L10n.string("Search results", "Результаты поиска")
                                    },
                                    style = AppText.captionBold,
                                    color = Color.White.copy(alpha = 0.52f),
                                )
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    displayed.forEach { place ->
                                        LocationRow(
                                            title = place.city,
                                            subtitle = place.displaySubtitle,
                                            icon = Icons.Filled.Apartment,
                                            showsChevron = true,
                                        ) { onSelect(place, LocationSource.MANUAL) }
                                    }
                                }
                            }
                        }
                    }

                    Text(
                        L10n.string("City data: SimpleMaps", "Данные о городах: SimpleMaps"),
                        style = AppText.caption2,
                        color = Color.White.copy(alpha = 0.42f),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    )
                }

                PickerScreen.DETECTED -> {
                    val place = detectedPlace
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(top = 40.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        Icon(
                            Icons.Filled.MyLocation,
                            null,
                            tint = accentGreen,
                            modifier = Modifier.size(58.dp),
                        )

                        if (place != null) {
                            Text(
                                L10n.string("Is ${place.city} your city?", "Ваш город — ${place.city}?"),
                                style = AppText.title2Bold,
                                color = Color.White,
                                textAlign = TextAlign.Center,
                            )
                            Text(
                                place.displaySubtitle,
                                style = AppText.subheadline,
                                color = Color.White.copy(alpha = 0.58f),
                            )

                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(56.dp)
                                    .clip(RoundedCornerShape(18.dp))
                                    .background(accentGreen)
                                    .clickable { onSelect(place, LocationSource.GEOLOCATION) },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    L10n.string("Yes, that's right", "Да, всё верно"),
                                    style = AppText.headlineBold,
                                    color = Color.Black,
                                )
                            }

                            Text(
                                L10n.string("Choose manually", "Выбрать вручную"),
                                style = AppText.headlineBold,
                                color = Color.White,
                                modifier = Modifier.clickable {
                                    detectedPlace = null
                                    screen = PickerScreen.COUNTRIES
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchField(placeholder: String, value: String, onValueChange: (String) -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.10f), shape)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Search, null, tint = Color.White.copy(alpha = 0.48f), modifier = Modifier.size(17.dp))
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (value.isEmpty()) {
                Text(placeholder, style = AppText.subheadline, color = Color.White.copy(alpha = 0.42f))
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = AppText.body.copy(color = Color.White),
                cursorBrush = SolidColor(accentGreen),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun LocationRow(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    leadingText: String? = null,
    showsChevron: Boolean,
    isBusy: Boolean = false,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 66.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.07f))
            .border(1.dp, Color.White.copy(alpha = 0.10f), shape)
            .clickable(enabled = !isBusy, onClick = onClick)
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(40.dp), contentAlignment = Alignment.Center) {
            if (leadingText != null) {
                Text(leadingText, fontSize = 27.sp)
            } else {
                Box(
                    modifier = Modifier.size(40.dp).clip(CircleShape).background(accentGreen.copy(alpha = 0.14f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, null, tint = accentGreen, modifier = Modifier.size(19.dp))
                }
            }
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = AppText.headlineBold, color = Color.White)
            if (subtitle.isNotEmpty()) {
                Text(subtitle, style = AppText.captionSemibold, color = Color.White.copy(alpha = 0.54f))
            }
        }

        if (isBusy) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        } else if (showsChevron) {
            Icon(
                Icons.Filled.ChevronRight,
                null,
                tint = Color.White.copy(alpha = 0.42f),
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

@Composable
private fun ErrorPanel(message: String, showsRetry: Boolean, isLoading: Boolean, onRetry: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFFFF9800).copy(alpha = 0.12f))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            Icon(
                Icons.Filled.WarningAmber,
                null,
                tint = Color(0xFFFF9800),
                modifier = Modifier.size(15.dp),
            )
            Text(message, style = AppText.captionSemibold, color = Color(0xFFFF9800))
        }

        if (showsRetry) {
            Box(
                modifier = Modifier
                    .height(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(accentGreen)
                    .clickable(enabled = !isLoading, onClick = onRetry)
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    L10n.string("Try again", "Повторить"),
                    style = AppText.subheadlineSemibold,
                    color = Color.Black,
                )
            }
        }
    }
}
