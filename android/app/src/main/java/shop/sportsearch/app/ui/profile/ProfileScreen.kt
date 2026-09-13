package shop.sportsearch.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.*
import shop.sportsearch.app.ui.location.GlobalLocationPickerSheet
import shop.sportsearch.app.ui.discover.SwipeCard
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme

private const val PROFILE_PREFS = "sportsearch.profile"
private const val VISIBILITY_KEY = "profile.visibilityMode"

/** The subscreen currently pushed on top of the profile tab. */
private enum class ProfileRoute {
    NONE, SPORTS, AVAILABILITY, LOCATION, LOCATION_PICKER, NOTIFICATIONS, LANGUAGE, PRIVACY, ACCOUNT, QR, EDITOR
}

/** Port of `struct ProfileView` in ios/TennisSearchIOS/Views/ProfileView.swift. */
@Composable
fun ProfileScreen(appModel: AppViewModel) {
    val scope = rememberCoroutineScope()
    val androidContext = LocalContext.current
    val prefs = remember {
        androidContext.getSharedPreferences(PROFILE_PREFS, android.content.Context.MODE_PRIVATE)
    }

    var draft by remember(appModel.currentUser?.id) { mutableStateOf(appModel.currentUser) }
    var route by remember { mutableStateOf(ProfileRoute.NONE) }
    var screenMode by remember { mutableStateOf(ProfileScreenMode.EDITING) }
    var saveToastMessage by remember { mutableStateOf<String?>(null) }
    var isUploadingAvatar by remember { mutableStateOf(false) }
    var isUploadingMedia by remember { mutableStateOf(false) }
    var mediaPreview by remember { mutableStateOf<PlayerMediaItem?>(null) }
    var gallery by remember { mutableStateOf<ReportPhotoGalleryItem?>(null) }
    var isDeleteConfirmationPresented by remember { mutableStateOf(false) }
    var visibilityMode by remember {
        mutableStateOf(ProfileVisibilityMode.from(prefs.getString(VISIBILITY_KEY, null)))
    }

    var gameFeedRequests by remember { mutableStateOf<List<MatchGameRequest>>(emptyList()) }
    var gameFeedVisits by remember { mutableStateOf<List<PersonalActivity>>(emptyList()) }
    var isGameFeedLoading by remember { mutableStateOf(false) }
    var isVisitFeedLoading by remember { mutableStateOf(false) }
    var gameFeedError by remember { mutableStateOf<String?>(null) }
    var visitFeedError by remember { mutableStateOf<String?>(null) }

    fun showSaveToast(message: String) {
        saveToastMessage = message
    }

    LaunchedEffect(saveToastMessage) {
        if (saveToastMessage != null) {
            delay(2200)
            saveToastMessage = null
        }
    }

    suspend fun save(successMessage: String = L10n.string("Profile saved", "Профиль сохранён")): Boolean {
        val current = draft ?: return false
        val saved = appModel.saveProfile(current)
        if (saved) showSaveToast(successMessage)
        return saved
    }

    suspend fun loadGames() {
        isGameFeedLoading = true
        runCatching { appModel.repository.fetchMyGameRequests() }
            .onSuccess {
                gameFeedRequests = it
                gameFeedError = null
            }
            .onFailure { gameFeedError = it.message }
        isGameFeedLoading = false
    }

    suspend fun loadVisits() {
        isVisitFeedLoading = true
        runCatching { appModel.repository.fetchPersonalActivities() }
            .onSuccess {
                gameFeedVisits = it
                visitFeedError = null
            }
            .onFailure { visitFeedError = it.message }
        isVisitFeedLoading = false
    }

    LaunchedEffect(appModel.currentUser?.id) {
        draft = appModel.currentUser
        if (appModel.isAuthenticated) {
            loadGames()
            loadVisits()
        }
    }

    val avatarPicker = rememberChatPhotoPicker { picked ->
        val photo = picked.firstOrNull() ?: return@rememberChatPhotoPicker
        scope.launch {
            isUploadingAvatar = true
            runCatching { appModel.repository.uploadAvatar(photo.bytes, photo.fileName, photo.mimeType) }
                .onSuccess { url -> draft = draft?.copy(avatarUrl = url) }
                .onFailure(appModel::present)
            isUploadingAvatar = false
        }
    }

    val photoPicker = rememberChatPhotoPicker { picked ->
        if (picked.isEmpty()) return@rememberChatPhotoPicker
        scope.launch {
            isUploadingMedia = true
            picked.forEach { photo ->
                runCatching { appModel.repository.uploadProfileMedia(photo.bytes, photo.fileName, photo.mimeType) }
                    .onSuccess { result ->
                        draft = draft?.copy(
                            avatarUrl = result.avatarUrl ?: draft?.avatarUrl,
                            profilePhotoUrls = result.profilePhotoUrls,
                            profileVideoUrls = result.profileVideoUrls,
                        )
                    }
                    .onFailure(appModel::present)
            }
            isUploadingMedia = false
        }
    }

    fun removeMedia(item: PlayerMediaItem) {
        scope.launch {
            isUploadingMedia = true
            runCatching { appModel.repository.removeProfileMedia(item.path) }
                .onSuccess { result ->
                    draft = draft?.copy(
                        avatarUrl = result.avatarUrl,
                        profilePhotoUrls = result.profilePhotoUrls,
                        profileVideoUrls = result.profileVideoUrls,
                    )
                }
                .onFailure(appModel::present)
            isUploadingMedia = false
        }
    }

    // --- Subscreen routing, standing in for iOS `NavigationLink` destinations ---
    val profile = draft
    if (profile != null) {
        when (route) {
            ProfileRoute.SPORTS -> {
                ProfileEditorScreen(
                    appModel = appModel,
                    title = L10n.string("Sports profile", "Спортивный профиль"),
                    subtitle = L10n.string("Choose your sports and level.", "Настрой виды спорта и уровень."),
                    icon = Icons.Filled.SportsTennis,
                    tint = AppTheme.court,
                    onBack = { route = ProfileRoute.NONE },
                    onSave = { save() },
                ) {
                    ProfileDarkPanel {
                        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            ProfileEditorMetricStrip(
                                listOf(
                                    ProfileMetricItem(
                                        L10n.string("Sports", "Спортов"),
                                        "${profile.preferredSports.size}",
                                        Icons.Filled.SportsTennis,
                                    ),
                                    ProfileMetricItem(
                                        L10n.string("Search", "Поиск"),
                                        if (profile.isLookingForGame) {
                                            L10n.string("Active", "Активен")
                                        } else {
                                            L10n.string("Hidden", "Скрыт")
                                        },
                                        Icons.Filled.Visibility,
                                    ),
                                ),
                            )

                            ProfileEmbeddedLightCard(
                                title = L10n.string("Sports", "Виды спорта"),
                                subtitle = L10n.string(
                                    "Choose everything you're ready to play and set your level.",
                                    "Выбери всё, во что готов играть, и выставь уровень.",
                                ),
                            ) {
                                AppSportSelectionGrid(
                                    title = L10n.string("Sports profile", "Спортивный профиль"),
                                    sports = Sport.entries,
                                    selectedSports = profile.preferredSports,
                                    levels = profile.sportLevels,
                                    onSelectedSportsChange = { draft = draft?.copy(preferredSports = it) },
                                    onLevelsChange = { draft = draft?.copy(sportLevels = it) },
                                )
                            }

                            ProfileEmbeddedLightCard(
                                title = L10n.string("Visibility", "Видимость"),
                                subtitle = L10n.string(
                                    "You can temporarily hide from active player recommendations.",
                                    "Можно временно скрыться из активной подборки игроков.",
                                ),
                            ) {
                                ProfileMapVisibilityControl(
                                    isOn = profile.showOnMap,
                                    onChange = { draft = draft?.copy(showOnMap = it) },
                                )
                                ToggleCard(
                                    title = L10n.string("Looking for a game now", "Ищу игру сейчас"),
                                    subtitle = L10n.string(
                                        "Show you in active player recommendations.",
                                        "Показывать тебя в активной подборке игроков.",
                                    ),
                                    isOn = profile.isLookingForGame,
                                    onToggle = { draft = draft?.copy(isLookingForGame = it) },
                                )
                            }
                        }
                    }
                }
                return
            }

            ProfileRoute.AVAILABILITY -> {
                val availability = profile.availabilityByDay
                ProfileEditorScreen(
                    appModel = appModel,
                    title = L10n.string("Availability", "Доступность"),
                    subtitle = L10n.string(
                        "Select the days and times when you can actually play.",
                        "Отметь дни и окна времени, когда реально удобно играть.",
                    ),
                    icon = Icons.Filled.AccessTime,
                    tint = Color(0xFF4CAF50),
                    onBack = { route = ProfileRoute.NONE },
                    onSave = { save() },
                ) {
                    ProfileDarkPanel {
                        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            val windows = availability.values.flatten().toSet()
                                .mapNotNull { TimeRange.from(it)?.title }.sorted().joinToString(", ")
                            ProfileEditorMetricStrip(
                                listOf(
                                    ProfileMetricItem(
                                        L10n.string("Days", "Дней"),
                                        "${availability.count { it.value.isNotEmpty() }}",
                                        Icons.Filled.AccessTime,
                                    ),
                                    ProfileMetricItem(
                                        L10n.string("Windows", "Окна"),
                                        windows.ifEmpty { L10n.string("Empty", "Пусто") },
                                        Icons.Filled.AccessTime,
                                    ),
                                    ProfileMetricItem(
                                        L10n.string("Slots", "Слотов"),
                                        "${availability.values.sumOf { it.size }}",
                                        Icons.Filled.CheckCircle,
                                    ),
                                ),
                            )

                            ProfileEmbeddedLightCard(
                                title = L10n.string("Week", "Неделя"),
                                subtitle = L10n.string(
                                    "Use a preset or build your schedule manually.",
                                    "Можно быстро выбрать пресеты или собрать расписание вручную.",
                                ),
                            ) {
                                AppAvailabilityWeekEditor(
                                    availabilityByDay = availability,
                                    onChange = { draft = draft?.copy(availabilityByDay = it) },
                                )
                            }

                            ProfileAvailabilityDarkSummary(availability)
                        }
                    }
                }
                return
            }

            ProfileRoute.LOCATION -> {
                ProfileEditorScreen(
                    appModel = appModel,
                    title = L10n.string("Preferred locations", "Где удобно играть"),
                    subtitle = L10n.string(
                        "Districts are used to recommend players and venues.",
                        "Районы используются в подборе игроков и центров.",
                    ),
                    icon = Icons.Filled.LocationOn,
                    tint = Color(0xFF4CAF50),
                    onBack = { route = ProfileRoute.NONE },
                    onSave = { save() },
                ) {
                    ProfileDarkPanel {
                        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            ProfileEditorMetricStrip(
                                listOf(
                                    ProfileMetricItem(
                                        L10n.string("Districts", "Районов"),
                                        "${activeProfileDistricts(profile).size}",
                                        Icons.Filled.LocationOn,
                                    ),
                                    ProfileMetricItem(
                                        L10n.string("Radius", "Радиус"),
                                        L10n.string("${profile.searchRadiusKm} km", "${profile.searchRadiusKm} км"),
                                        Icons.Filled.Public,
                                    ),
                                    ProfileMetricItem(
                                        L10n.string("City", "Город"),
                                        profile.city ?: L10n.string("Not selected", "Не выбран"),
                                        Icons.Filled.Public,
                                    ),
                                ),
                            )

                            ProfileEmbeddedLightCard(
                                title = L10n.string("City", "Город"),
                                subtitle = L10n.string(
                                    "Clubs and players are selected within the chosen city.",
                                    "Клубы и игроки подбираются внутри выбранного города.",
                                ),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { route = ProfileRoute.LOCATION_PICKER },
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(
                                        Icons.Filled.Public,
                                        null,
                                        tint = AppTheme.court,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Text(
                                            profile.location?.city
                                                ?: profile.city
                                                ?: L10n.string("Choose country and city", "Выбрать страну и город"),
                                            style = AppText.subheadlineSemibold,
                                            color = AppTheme.ink,
                                        )
                                        profile.location?.localizedCountryName?.let {
                                            Text(
                                                it,
                                                style = AppText.captionSemibold,
                                                color = AppTheme.ink.copy(alpha = 0.56f),
                                            )
                                        }
                                    }
                                    Icon(
                                        Icons.Filled.ChevronRight,
                                        null,
                                        tint = AppTheme.ink.copy(alpha = 0.42f),
                                        modifier = Modifier.size(14.dp),
                                    )
                                }
                            }

                            val coveredCity = SupportedCity.resolve(profile.city)
                            if (profileDistrictsEnabled(profile) && coveredCity != null) {
                                ProfileDistrictPickerCard(
                                    selectedDistricts = profile.preferredDistricts,
                                    districts = districtOptions(coveredCity),
                                    onChange = { selected, primary ->
                                        draft = draft?.copy(preferredDistricts = selected, district = primary)
                                    },
                                )
                            } else {
                                ProfileEmbeddedLightCard(
                                    title = L10n.string("Districts", "Районы"),
                                    subtitle = L10n.string(
                                        "For ${profile.city ?: "this city"}, we'll use the selected radius " +
                                            "and distance for now.",
                                        "Для ${profile.city ?: "этого города"} пока используем выбранный радиус " +
                                            "и расстояние до места.",
                                    ),
                                ) {
                                    Text(
                                        L10n.string(
                                            "City districts will be added gradually",
                                            "Районы города добавим постепенно",
                                        ),
                                        style = AppText.subheadlineSemibold,
                                        color = AppTheme.ink.copy(alpha = 0.62f),
                                    )
                                }
                            }

                            ProfileEmbeddedLightCard(
                                title = L10n.string("Search radius", "Радиус поиска"),
                                subtitle = L10n.string(
                                    "If districts are unavailable, distance becomes the main signal.",
                                    "Если районов нет, расстояние станет главным сигналом.",
                                ),
                            ) {
                                RadiusSlider(
                                    value = profile.searchRadiusKm,
                                    onChange = { draft = draft?.copy(searchRadiusKm = it) },
                                )
                            }
                        }
                    }
                }
                return
            }

            ProfileRoute.NOTIFICATIONS -> {
                ProfileEditorScreen(
                    appModel = appModel,
                    title = L10n.string("Notifications", "Уведомления"),
                    subtitle = L10n.string(
                        "Only events that require your attention or response.",
                        "Оставляем только события, где тебе нужно увидеть действие или ответ.",
                    ),
                    icon = Icons.Filled.Notifications,
                    tint = Color(0xFFFFC107),
                    onBack = { route = ProfileRoute.NONE },
                    onSave = {
                        save(L10n.string("Notification settings saved", "Настройки уведомлений сохранены"))
                    },
                ) {
                    ProfileDarkPanel {
                        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            ProfileEditorMetricStrip(
                                listOf(
                                    ProfileMetricItem(
                                        L10n.string("Events", "Событий"),
                                        "${enabledNotificationCount(profile)}/3",
                                        Icons.Filled.CheckCircle,
                                    ),
                                ),
                            )

                            ProfileEmbeddedLightCard(
                                title = L10n.string("Events", "События"),
                                subtitle = L10n.string(
                                    "Actual notifications only, not profile settings.",
                                    "Здесь только реальные уведомления, а не настройки профиля.",
                                ),
                            ) {
                                ToggleCard(
                                    L10n.string("New matches", "Новые мэтчи"),
                                    L10n.string(
                                        "Notify me when there is mutual interest.",
                                        "Сообщать, когда появляется взаимный интерес.",
                                    ),
                                    profile.notificationMatches,
                                ) { draft = draft?.copy(notificationMatches = it) }

                                ToggleCard(
                                    L10n.string("Messages", "Сообщения"),
                                    L10n.string(
                                        "Show new chat messages and replies.",
                                        "Показывать новые сообщения и ответы в чате.",
                                    ),
                                    profile.notificationMessages,
                                ) { draft = draft?.copy(notificationMessages = it) }

                                ToggleCard(
                                    L10n.string("Games and invitations", "Игры и предложения"),
                                    L10n.string(
                                        "Responses, confirmations, cancellations, and game updates.",
                                        "Отклики, подтверждения, отмены и изменения игр.",
                                    ),
                                    profile.notificationGames,
                                ) { draft = draft?.copy(notificationGames = it) }
                            }

                            ProfileEmbeddedLightCard(
                                title = L10n.string("Sound", "Звук"),
                                subtitle = L10n.string(
                                    "Controls notification sounds separately.",
                                    "Отдельно регулирует звуковой сигнал внутри приложения.",
                                ),
                            ) {
                                ToggleCard(
                                    L10n.string("Notification sounds", "Звуковые сигналы"),
                                    L10n.string(
                                        "Play the system notification sound.",
                                        "Воспроизводить звук системного уведомления.",
                                    ),
                                    profile.notificationSound,
                                ) { draft = draft?.copy(notificationSound = it) }
                            }
                        }
                    }
                }
                return
            }

            ProfileRoute.LOCATION_PICKER -> {
                HideBottomBarWhileVisible(appModel)
                GlobalLocationPickerSheet(
                    repository = appModel.repository,
                    initialLocation = profile.location,
                    automaticallyRequestsLocation = false,
                    onDismiss = { route = ProfileRoute.LOCATION },
                    onSelect = { place, source ->
                        // `applyProfileLocation(_:source:)` - a new place clears the districts.
                        // Swift also ORs in a `location == nil` branch, but with no saved
                        // location the id comparison is already true, so it is dropped here.
                        val didChangePlace = profile.location?.id != place.id
                        draft = profile.copy(
                            location = place,
                            coverageRaw = place.coverage,
                            locationSourceRaw = source.wire,
                            city = place.coverage.legacyCity ?: place.city,
                            district = if (didChangePlace) null else profile.district,
                            preferredDistricts = if (didChangePlace) emptyList() else profile.preferredDistricts,
                        )
                        route = ProfileRoute.LOCATION
                    },
                )
                return
            }

            ProfileRoute.LANGUAGE -> {
                ProfileLanguageSettingsScreen(appModel) { route = ProfileRoute.NONE }
                return
            }

            ProfileRoute.PRIVACY -> {
                VisibilitySettingsView(
                    appModel = appModel,
                    selection = visibilityMode,
                    onSelect = { mode ->
                        visibilityMode = mode
                        prefs.edit().putString(VISIBILITY_KEY, mode.wire).apply()
                    },
                    onBack = { route = ProfileRoute.NONE },
                )
                return
            }

            ProfileRoute.ACCOUNT -> {
                ProfileAccountScreen(
                    appModel = appModel,
                    email = appModel.currentUser?.email,
                    isVerified = appModel.currentUser?.isVerified == true,
                    onBack = { route = ProfileRoute.NONE },
                    onLogout = { appModel.logout() },
                    onDelete = { isDeleteConfirmationPresented = true },
                )
                return
            }

            ProfileRoute.QR -> {
                QRProfileView(
                    appModel = appModel,
                    profile = profile,
                    visibilityMode = visibilityMode,
                    onBack = { route = ProfileRoute.NONE },
                    onOpenVisibility = { route = ProfileRoute.PRIVACY },
                )
                return
            }

            ProfileRoute.EDITOR -> {
                ProfileBasicsEditorScreen(
                    appModel = appModel,
                    profile = profile,
                    onChange = { draft = it },
                    onBack = { route = ProfileRoute.NONE },
                    onSave = { save() },
                )
                return
            }

            ProfileRoute.NONE -> Unit
        }
    }

    mediaPreview?.let { item ->
        HideBottomBarWhileVisible(appModel)
        ChatMediaViewer(
            repository = appModel.repository,
            path = item.path,
            onDismiss = { mediaPreview = null },
        )
        return
    }

    gallery?.let { item ->
        HideBottomBarWhileVisible(appModel)
        ReportPhotoGallerySheet(item = item, onDismiss = { gallery = null })
        return
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 16.dp, bottom = 116.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L10n.string("Profile", "Профиль"),
                        fontSize = 34.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                    Spacer(Modifier.weight(1f))
                    if (profile != null) {
                        ProfileHeaderButton(Icons.Filled.QrCodeScanner, AppTheme.court) { route = ProfileRoute.QR }
                    }
                }
            }

            if (profile == null) {
                item { GuestProfileContent(appModel) }
                return@LazyColumn
            }

            item {
                ProfileScreenModePicker(selection = screenMode) { screenMode = it }
            }

            if (screenMode == ProfileScreenMode.PREVIEW) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                L10n.string("Profile in Similar players", "Карточка в «Похожих игроках»"),
                                style = AppText.headlineBold,
                                color = Color.White,
                            )
                            Text(
                                L10n.string(
                                    "Only information from your profile is shown",
                                    "Показаны только данные из вашего профиля",
                                ),
                                style = AppText.captionSemibold,
                                color = Color.White.copy(alpha = 0.58f),
                            )
                        }

                        Box(modifier = Modifier.fillMaxWidth().height(520.dp)) {
                            SwipeCard(
                                user = discoverUserFromProfile(profile),
                                index = 0,
                                dragOffsetX = 0f,
                                decision = null,
                                storyIndex = 0,
                                storyProgress = 0f,
                            )
                        }

                        Text(
                            L10n.string(
                                "Preview: swipes and actions are disabled",
                                "Предпросмотр: свайпы и действия отключены",
                            ),
                            style = AppText.captionSemibold,
                            color = Color.White.copy(alpha = 0.56f),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                return@LazyColumn
            }

            item {
                ProfileSelectionMediaCard(
                    profile = profile,
                    isUploadingAvatar = isUploadingAvatar,
                    isUploading = isUploadingMedia,
                    onPickAvatar = avatarPicker,
                    onPickPhotos = photoPicker,
                    onEdit = { route = ProfileRoute.EDITOR },
                    onPreview = { mediaPreview = it },
                    onRemove = ::removeMedia,
                )
            }

            item {
                val completion = profileCompletionStatus(profile)
                ProfileCompletenessCard(
                    percent = completion.percent,
                    missingSteps = completion.missingSteps,
                    hasVideoBonus = profile.profileVideoUrls.isNotEmpty(),
                )
            }

            item {
                ProfileGameFeedSection(
                    items = ProfileGameFeedItem.make(gameFeedRequests, gameFeedVisits, profile.id),
                    currentUserId = profile.id,
                    isLoading = isGameFeedLoading || isVisitFeedLoading,
                    gameError = gameFeedError,
                    visitError = visitFeedError,
                    onRetryGames = { scope.launch { loadGames() } },
                    onRetryVisits = { scope.launch { loadVisits() } },
                    onOpenGallery = { gallery = it },
                )
            }

            item {
                ProfileMenuGroup {
                    ProfileMenuRow(
                        Icons.Filled.SportsTennis,
                        AppTheme.court,
                        L10n.string("Sports profile", "Спортивный профиль"),
                        sportsSummary(profile),
                    ) { route = ProfileRoute.SPORTS }

                    ProfileMenuRow(
                        Icons.Filled.AccessTime,
                        Color(0xFF4CAF50),
                        L10n.string("Availability", "Доступность"),
                        availabilityHeadline(profile.availabilityByDay),
                    ) { route = ProfileRoute.AVAILABILITY }

                    ProfileMenuRow(
                        Icons.Filled.LocationOn,
                        Color(0xFF4CAF50),
                        L10n.string("Preferred locations", "Где удобно играть"),
                        playLocationSummary(profile),
                    ) { route = ProfileRoute.LOCATION }

                    ProfileMenuRow(
                        Icons.Filled.Visibility,
                        Color(0xFFFFEB3B),
                        L10n.string("Preview profile", "Посмотреть карточку"),
                        activitySummary(profile),
                    ) { screenMode = ProfileScreenMode.PREVIEW }
                }
            }

            item {
                ProfileMenuGroup {
                    ProfileMenuRow(
                        Icons.Filled.Public,
                        Color.White.copy(alpha = 0.82f),
                        "Language / Язык",
                        appModel.localeStore.effectiveLocale.displayName,
                    ) { route = ProfileRoute.LANGUAGE }

                    ProfileMenuRow(
                        Icons.Filled.Notifications,
                        Color.White.copy(alpha = 0.82f),
                        L10n.string("Notifications", "Уведомления"),
                        notificationsSummary(profile),
                    ) { route = ProfileRoute.NOTIFICATIONS }

                    ProfileMenuRow(
                        Icons.Filled.Lock,
                        Color.White.copy(alpha = 0.82f),
                        L10n.string("Privacy", "Приватность"),
                        visibilityMode.title,
                    ) { route = ProfileRoute.PRIVACY }

                    ProfileMenuRow(
                        Icons.Filled.Person,
                        Color.White.copy(alpha = 0.82f),
                        L10n.string("Account", "Аккаунт"),
                        profile.email ?: L10n.string("Email, phone, security", "Почта, телефон, безопасность"),
                    ) { route = ProfileRoute.ACCOUNT }
                }
            }
        }

        saveToastMessage?.let { message ->
            Box(modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 12.dp)) {
                ProfileSaveSuccessToast(message)
            }
        }

        if (isUploadingMedia) {
            ProfileMediaProgressOverlay(
                title = L10n.string("Uploading media", "Медиа загружается"),
                subtitle = L10n.string(
                    "Opening the file and preparing the upload.",
                    "Открываем файл и готовим загрузку.",
                ),
            )
        }
    }

    if (isDeleteConfirmationPresented) {
        AlertDialog(
            onDismissRequest = { isDeleteConfirmationPresented = false },
            containerColor = Color.White,
            title = { Text(L10n.string("Delete profile?", "Удалить профиль?"), color = AppTheme.ink) },
            text = {
                Text(
                    L10n.string(
                        "This action cannot be undone. Your account, searches, matches, and history will be deleted.",
                        "Это действие необратимо. Аккаунт, поиски, мэтчи и история будут удалены.",
                    ),
                    color = AppTheme.ink.copy(alpha = 0.7f),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    isDeleteConfirmationPresented = false
                    scope.launch {
                        runCatching { appModel.repository.deleteAccount() }
                            .onSuccess { appModel.logout() }
                            .onFailure(appModel::present)
                    }
                }) { Text(L10n.string("Delete profile", "Удалить профиль"), color = Color.Red) }
            },
            dismissButton = {
                TextButton(onClick = { isDeleteConfirmationPresented = false }) {
                    Text(L10n.string("Cancel", "Отмена"), color = AppTheme.ink)
                }
            },
        )
    }
}

/** Port of `struct ProfileSelectionMediaCard`. */
@Composable
private fun ProfileSelectionMediaCard(
    profile: UserProfile,
    isUploadingAvatar: Boolean,
    isUploading: Boolean,
    onPickAvatar: () -> Unit,
    onPickPhotos: () -> Unit,
    onEdit: () -> Unit,
    onPreview: (PlayerMediaItem) -> Unit,
    onRemove: (PlayerMediaItem) -> Unit,
) {
    val mediaItems = profile.playerCardMediaItems
    val remainingPhotoSlots = maxOf(6 - profile.profilePhotoUrls.size, 0)

    ProfileDarkPanel {
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(L10n.string("Your profile", "Ваш профиль"), style = AppText.headlineBold, color = Color.White)
                    Text(
                        L10n.string("Basic information and media", "Основные данные и медиа"),
                        style = AppText.captionSemibold,
                        color = Color.White.copy(alpha = 0.58f),
                    )
                }
                Spacer(Modifier.weight(1f))
                if (isUploading || isUploadingAvatar) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(8.dp))
                }
                ProfileHeaderButton(Icons.Filled.Edit, Color.White, onEdit)
            }

            Box {
                ProfileHeroImage(
                    name = profile.displayName,
                    path = profile.profileHeroImagePath,
                    height = 264.dp,
                    modifier = Modifier.clickable(
                        enabled = !isUploading && !isUploadingAvatar,
                        onClick = onPickAvatar,
                    ),
                )
                Box(modifier = Modifier.align(Alignment.BottomEnd).padding(12.dp)) {
                    ProfileCapsule(L10n.string("Main photo", "Основное фото"), Color.Black.copy(alpha = 0.64f))
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        profile.age?.let { "${profile.displayName}, $it" } ?: profile.displayName,
                        style = AppText.title2Bold,
                        color = Color.White,
                    )
                    if (profile.isLookingForGame) {
                        ProfileCapsule(L10n.string("Looking for a game", "Ищу игру"), AppTheme.court)
                    }
                }

                Text(
                    profileLocationLine(profile),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.68f),
                )

                if (profile.preferredSports.isEmpty()) {
                    Text(
                        L10n.string("No sports selected yet", "Виды спорта пока не выбраны"),
                        style = AppText.subheadlineSemibold,
                        color = Color.White.copy(alpha = 0.52f),
                    )
                } else {
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        profile.preferredSports.take(4).forEach { sport ->
                            ProfileSportChip(sport, profile.sportLevels[sport.wire] ?: profile.tennisLevel)
                        }
                    }
                }

                Text(
                    profile.bio?.trim()?.takeIf { it.isNotEmpty() }
                        ?: L10n.string("Description is not filled in yet", "Описание пока не заполнено"),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.72f),
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L10n.string("Photos and videos", "Фото и видео"),
                        style = AppText.subheadlineSemibold,
                        color = Color.White,
                    )
                    if (profile.profileVideoUrls.isNotEmpty()) {
                        Spacer(Modifier.weight(1f))
                        Text(
                            L10n.string("Video added", "Видео добавлено"),
                            style = AppText.captionSemibold,
                            color = AppTheme.mint,
                        )
                    }
                }

                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    mediaItems.forEach { item ->
                        ProfileMediaTile(
                            item = item,
                            canRemove = item.kind == PlayerMediaKind.VIDEO ||
                                profile.profilePhotoUrls.contains(item.path),
                            isEnabled = !isUploading && !isUploadingAvatar,
                            onPreview = onPreview,
                            onRemove = onRemove,
                        )
                    }

                    if (remainingPhotoSlots > 0) {
                        ProfileAddMediaTile(
                            title = L10n.string("Photo", "Фото"),
                            icon = Icons.Filled.PhotoCamera,
                            enabled = !isUploading && !isUploadingAvatar,
                            onClick = onPickPhotos,
                        )
                    }
                }
            }

            ProfileMediaAdviceRow()
        }
    }
}

private fun profileLocationLine(profile: UserProfile): String {
    val parts = mutableListOf<String>()
    profile.city?.trim()?.takeIf { it.isNotEmpty() }?.let { parts += it }
    val districts = profile.preferredDistricts.ifEmpty { listOfNotNull(profile.district) }
    districts.mapNotNull(::localizedDistrictName).firstOrNull()?.let { parts += it }
    return parts.ifEmpty { null }?.joinToString(" · ")
        ?: L10n.string("City and district are not set", "Город и район не указаны")
}

private fun districtOptions(city: SupportedCity): List<String> =
    districtsForCity(city).sortedBy { localizedDistrictName(it) ?: it }
