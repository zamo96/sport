package shop.sportsearch.app.ui.auth

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import shop.sportsearch.app.R
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppAvailabilityWeekEditor
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.components.appShadow
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.location.GlobalLocationPickerSheet
import shop.sportsearch.app.ui.profile.ProfileMapVisibilityControl
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `struct AuthView`: the intro hero, the two onboarding steps, the
 * sign-in card and the OTP step.
 *
 * One deliberate platform difference: iOS offers Sign in with Apple as the
 * primary action. Android has no Apple sign-in, so the same slot holds Sign in
 * with Google (`POST /auth/google`), with email + OTP below it as on iOS.
 */
@Composable
fun AuthScreen(
    appModel: AppViewModel,
    initialStep: AuthStep,
    embedded: Boolean,
) {
    var step by remember { mutableStateOf(initialStep) }
    var draft by remember { mutableStateOf(appModel.guestDraft) }
    var code by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    // Onboarding location state, mirroring `AuthView`'s own.
    var levelPickerSport by remember { mutableStateOf<Sport?>(null) }
    var locationChoice by remember { mutableStateOf<OnboardingLocationChoice?>(null) }
    var isDetectedDistrictConfirmed by remember { mutableStateOf(false) }
    var showsLocationPicker by remember { mutableStateOf(false) }
    var locationPickerRequestsAutomatically by remember { mutableStateOf(false) }
    var showsDistrictPicker by remember { mutableStateOf(false) }
    var automaticallyDetectedDistrict by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(appModel.presentedAuthStep) {
        appModel.presentedAuthStep?.let { step = it }
    }

    LaunchedEffect(appModel.currentUser?.id) {
        if (appModel.isAuthenticated && !appModel.canEnterApp) {
            draft = appModel.guestDraft
            step = if (draft.hasProfileBasics) AuthStep.AVAILABILITY else AuthStep.PROFILE
        }
    }

    fun persistDraft() = appModel.updateGuestDraft(draft)

    levelPickerSport?.let { sport ->
        OnboardingLevelPickerSheet(level = draft.sportLevels[sport.wire] ?: 5) { level ->
            val sports = if (draft.preferredSports.contains(sport)) {
                draft.preferredSports
            } else {
                draft.preferredSports + sport
            }
            draft = draft.copy(preferredSports = sports, sportLevels = draft.sportLevels + (sport.wire to level))
            persistDraft()
            levelPickerSport = null
        }
        return
    }

    if (showsLocationPicker) {
        GlobalLocationPickerSheet(
            repository = appModel.repository,
            initialLocation = draft.location,
            automaticallyRequestsLocation = locationPickerRequestsAutomatically,
            onDismiss = { showsLocationPicker = false },
            onSelect = { place, source ->
                // Port of `applySelectedLocation(_:source:)`.
                val previousPlaceId = draft.location?.id
                val isGeolocation = source == LocationSource.GEOLOCATION
                draft = draft.copy(
                    location = place,
                    locationSourceRaw = source.wire,
                    city = place.coverage.legacyCity ?: place.city,
                    district = if (previousPlaceId != place.id) null else draft.district,
                    preferredDistricts = if (previousPlaceId != place.id) {
                        emptyList()
                    } else {
                        draft.preferredDistricts
                    },
                )
                locationChoice = if (isGeolocation) {
                    OnboardingLocationChoice.NEARBY
                } else {
                    OnboardingLocationChoice.DISTRICTS
                }
                isDetectedDistrictConfirmed = !isGeolocation
                automaticallyDetectedDistrict = null
                persistDraft()
                appModel.considerLocaleRecommendation(place)
                showsLocationPicker = false
            },
        )
        return
    }

    if (showsDistrictPicker) {
        OnboardingDistrictPickerSheet(
            selectedCity = draft.city,
            selectedDistricts = draft.preferredDistricts,
            automaticallyDetectedDistrict = automaticallyDetectedDistrict,
            startsWithDistricts = true,
            onDetectAutomatically = {
                showsDistrictPicker = false
                locationChoice = OnboardingLocationChoice.NEARBY
                isDetectedDistrictConfirmed = false
                automaticallyDetectedDistrict = null
                draft = draft.copy(city = "", preferredDistricts = emptyList(), district = null)
                locationPickerRequestsAutomatically = true
                showsLocationPicker = true
            },
            onDone = { city, districts ->
                draft = draft.copy(city = city, preferredDistricts = districts)
                persistDraft()
                showsDistrictPicker = false
                locationChoice = if (city.isBlank() && districts.isEmpty()) {
                    null
                } else {
                    OnboardingLocationChoice.DISTRICTS
                }
            },
        )
        return
    }

    when (step) {
        AuthStep.INTRO -> IntroStep(
            appModel = appModel,
            onStart = { step = AuthStep.PROFILE },
            onSignIn = { step = AuthStep.EMAIL },
        )

        AuthStep.PROFILE -> ProfileStep(
            draft = draft,
            embedded = embedded,
            onDraftChange = { draft = it },
            onSelectLevel = { levelPickerSport = it },
            onBack = { step = AuthStep.INTRO },
            onNext = {
                if (draft.hasProfileBasics) {
                    persistDraft()
                    step = AuthStep.AVAILABILITY
                }
            },
        )

        AuthStep.AVAILABILITY -> AvailabilityStep(
            draft = draft,
            embedded = embedded,
            locationChoice = locationChoice,
            isDetectedDistrictConfirmed = isDetectedDistrictConfirmed,
            onDraftChange = { draft = it },
            onNearby = {
                locationChoice = OnboardingLocationChoice.NEARBY
                isDetectedDistrictConfirmed = false
                automaticallyDetectedDistrict = null
                locationPickerRequestsAutomatically = true
                showsLocationPicker = true
            },
            onDistricts = {
                locationChoice = OnboardingLocationChoice.DISTRICTS
                isDetectedDistrictConfirmed = false
                locationPickerRequestsAutomatically = false
                showsDistrictPicker = true
            },
            onBack = {
                persistDraft()
                step = AuthStep.PROFILE
            },
            onFinish = {
                // `finishGuestOnboarding()` - the two checks report different
                // problems, and only the first one sends you back a step.
                scope.launch {
                    if (!draft.hasProfileBasics) {
                        appModel.errorMessage = L10n.string(
                            "Enter your name, an age from 18 to 100, and at least one sport.",
                            "Укажи имя, возраст от 18 до 100 и хотя бы один вид спорта.",
                        )
                        step = AuthStep.PROFILE
                        return@launch
                    }
                    if (!draft.hasSelectedCity) {
                        appModel.errorMessage = L10n.string(
                            "Choose a country and city.",
                            "Выбери страну и город.",
                        )
                        return@launch
                    }
                    if (!appModel.completeGuestOnboarding(draft.copy(onboardingCompleted = true))) {
                        return@launch
                    }
                    appModel.queueDiscoverSimilarPlayersHint()
                    if (!embedded) appModel.dismissPresentedAuth()
                }
            },
        )

        AuthStep.EMAIL -> EmailStep(
            appModel = appModel,
            embedded = embedded,
            onBack = {
                persistDraft()
                step = if (draft.hasProfileBasics) AuthStep.AVAILABILITY else AuthStep.INTRO
            },
            onRequestCode = {
                persistDraft()
                scope.launch {
                    if (appModel.requestCode(userAgreementAccepted = true)) {
                        step = AuthStep.CODE
                    }
                }
            },
            onHaveCode = {
                if (appModel.authEmail.trim().isEmpty()) {
                    appModel.errorMessage = L10n.string("Enter your email first.", "Сначала укажи email для входа.")
                } else {
                    step = AuthStep.CODE
                }
            },
        )

        AuthStep.CODE -> CodeStep(
            appModel = appModel,
            code = code,
            onCodeChange = { code = it },
            onChangeEmail = { step = AuthStep.EMAIL },
            onVerify = {
                persistDraft()
                scope.launch { appModel.verify(code, userAgreementAccepted = true) }
            },
        )
    }
}

// MARK: - Intro

@Composable
private fun IntroStep(
    appModel: AppViewModel,
    onStart: () -> Unit,
    onSignIn: () -> Unit,
) {
    var registeredPlayers by remember { mutableStateOf(315) }
    LaunchedEffect(Unit) {
        runCatching { appModel.repository.fetchAppStats() }
            .getOrNull()
            ?.let { registeredPlayers = it.registeredPlayersCount }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val isCompact = maxHeight < 760.dp
        val showsPrivacyNote = maxHeight >= 800.dp
        val horizontalPadding = if (isCompact) 16.dp else 20.dp
        val heroHeight = if (isCompact) {
            (maxHeight * 0.38f).coerceIn(270.dp, 304.dp)
        } else {
            (maxHeight * 0.49f).coerceIn(400.dp, 440.dp)
        }
        val titleFontSize = if (isCompact) 38f else 44f
        val typewriterFontSize = if (isCompact) 33f else 38f

        OnboardingIntroBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = horizontalPadding),
            verticalArrangement = Arrangement.spacedBy(if (isCompact) 8.dp else 10.dp),
        ) {
            Spacer(Modifier.height(if (isCompact) 18.dp else 30.dp))

            Text(
                text = L10n.string("Find a partner", "Найди напарника"),
                fontSize = titleFontSize.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
                maxLines = 1,
            )

            OnboardingTypewriterLine(fontSize = typewriterFontSize)

            // seekingPlayersStatus
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .background(
                            Brush.radialGradient(
                                listOf(OnboardingStepPalette.lime.copy(alpha = 0.22f), Color.Transparent),
                            ),
                            CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .size(14.dp)
                            .appShadow(OnboardingStepPalette.lime.copy(alpha = 0.86f), 12.dp, shape = CircleShape)
                            .background(OnboardingStepPalette.lime, CircleShape),
                    )
                }
                Text(
                    text = L10n.string(
                        "$registeredPlayers players are looking for a game nearby",
                        "$registeredPlayers игроков ищут игру рядом",
                    ),
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.78f),
                    maxLines = 1,
                )
            }

            OnboardingMotionHero(height = heroHeight, modifier = Modifier.fillMaxWidth())

            Spacer(Modifier.weight(1f))

            LiquidStartButton(
                title = L10n.string("Start searching", "Начать поиск"),
                subtitle = L10n.string("Step 1 of 2", "Шаг 1 из 2"),
                onClick = onStart,
            )

            ExistingAccountButton(onSignIn)

            if (showsPrivacyNote) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Filled.Lock,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.48f),
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.size(10.dp))
                    Text(
                        L10n.string(
                            "We don't publish your data or location",
                            "Мы не публикуем ваши данные и местоположение",
                        ),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.48f),
                        maxLines = 1,
                    )
                }
            }

            Spacer(Modifier.height(if (isCompact) 4.dp else 8.dp))
        }
    }
}

/** Port of `existingAccountButton`. */
@Composable
private fun ExistingAccountButton(onClick: () -> Unit) {
    val haptics = rememberAppHaptics()
    val shape = continuousShape(28.dp)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(62.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.20f), shape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) {
                haptics.selection()
                onClick()
            }
            .padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(34.dp), contentAlignment = Alignment.Center) {
            Icon(
                Icons.Outlined.Person,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(22.dp),
            )
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .size(9.dp)
                    .background(OnboardingStepPalette.lime, CircleShape),
            )
        }
        Text(
            L10n.string("Already have an account? Sign in", "Уже есть аккаунт? Войти"),
            fontSize = 20.sp,
            fontWeight = FontWeight.Black,
            color = Color.White,
            maxLines = 1,
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = Color.White, modifier = Modifier.size(24.dp))
    }
}

// MARK: - Step 1: profile

@Composable
private fun ProfileStep(
    draft: GuestOnboardingDraft,
    embedded: Boolean,
    onDraftChange: (GuestOnboardingDraft) -> Unit,
    onSelectLevel: (Sport) -> Unit,
    onBack: () -> Unit,
    onNext: () -> Unit,
) {
    DismissOnSystemBack(onBack)
    OnboardingDarkStep(
        stepIndex = 1,
        title = L10n.string("What would you like\nto play?", "Во что хочешь\nсыграть?"),
        subtitle = L10n.string(
            "Choose sports and your level — we'll show suitable players nearby.",
            "Выбери виды спорта и укажи уровень — покажем подходящих игроков рядом.",
        ),
        primaryTitle = L10n.string("Next", "Дальше"),
        primaryEnabled = draft.hasProfileBasics,
        showBack = !embedded,
        onBack = onBack,
        onPrimary = onNext,
    ) {
        OnboardingSectionTitle(L10n.string("Sports", "Виды спорта"))

        OnboardingSportSelectionGrid(
            sports = draft.preferredSports,
            levels = draft.sportLevels,
            cardHeight = if (LocalConfiguration.current.screenHeightDp < 760) 86.dp else 92.dp,
            onToggle = { sport ->
                val sports = draft.preferredSports.toMutableList()
                val levels = draft.sportLevels.toMutableMap()
                if (sports.contains(sport)) {
                    sports.remove(sport)
                    levels.remove(sport.wire)
                } else {
                    sports.add(sport)
                    levels[sport.wire] = levels[sport.wire] ?: 5
                }
                onDraftChange(draft.copy(preferredSports = sports, sportLevels = levels))
            },
            onSelectLevel = onSelectLevel,
        )

        Spacer(Modifier.height(4.dp))
        OnboardingSectionTitle(L10n.string("Name and age", "Имя и возраст"))

        DarkTextField(
            value = draft.name,
            onValueChange = { onDraftChange(draft.copy(name = it)) },
            placeholder = L10n.string("Your name", "Как тебя зовут"),
        )

        DarkTextField(
            value = if (draft.age > 0) draft.age.toString() else "",
            onValueChange = { value ->
                onDraftChange(draft.copy(age = value.filter(Char::isDigit).take(3).toIntOrNull() ?: 0))
            },
            placeholder = L10n.string("Age", "Возраст"),
            keyboardType = KeyboardType.Number,
        )

        Text(
            L10n.string("Age is required: 18 to 100.", "Возраст обязателен: от 18 до 100 лет."),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.54f),
        )

        OnboardingToggleCard(
            title = L10n.string("Show me to other players", "Показывать меня другим игрокам"),
            subtitle = L10n.string(
                "You will appear in search for players who match your criteria.",
                "Ты появишься в подборе у игроков, которые тебе подходят.",
            ),
            checked = draft.isLookingForGame,
            onCheckedChange = { onDraftChange(draft.copy(isLookingForGame = it)) },
        )
    }
}

// MARK: - Step 2: availability

@Composable
private fun AvailabilityStep(
    draft: GuestOnboardingDraft,
    embedded: Boolean,
    locationChoice: OnboardingLocationChoice?,
    isDetectedDistrictConfirmed: Boolean,
    onDraftChange: (GuestOnboardingDraft) -> Unit,
    onNearby: () -> Unit,
    onDistricts: () -> Unit,
    onBack: () -> Unit,
    onFinish: () -> Unit,
) {
    DismissOnSystemBack(onBack)
    val canFinish = draft.hasRequiredOnboardingFields

    OnboardingDarkStep(
        stepIndex = 2,
        title = L10n.string("When can you play?", "Когда удобно играть?"),
        subtitle = L10n.string(
            "When are you available to play? You can leave this empty and set it later.",
            "Когда тебе удобно играть. Можно оставить пустым и настроить позже.",
        ),
        primaryTitle = if (embedded) L10n.string("Browse players", "Смотреть игроков") else L10n.string("Continue", "Продолжить"),
        primaryEnabled = canFinish,
        showBack = true,
        onBack = onBack,
        onPrimary = onFinish,
    ) {
        OnboardingAvailabilityEditorCard {
            AppAvailabilityWeekEditor(
                availabilityByDay = draft.availabilityByDay,
                onChange = { onDraftChange(draft.copy(availabilityByDay = it)) },
                caption = L10n.string(
                    "One weekly schedule. Choose a day, then select convenient time windows.",
                    "Одна шкала недели. Выбери день и затем отметь удобные окна времени.",
                ),
            )
        }

        OnboardingSearchLocationSection(
            selectedChoice = locationChoice,
            selectedCity = draft.city,
            selectedDistricts = draft.preferredDistricts,
            isDetectingLocation = false,
            locationDetectionFailed = false,
            isDetectedDistrictConfirmed = isDetectedDistrictConfirmed,
            onNearby = onNearby,
            onDistricts = onDistricts,
        )

        ProfileMapVisibilityControl(
            isOn = draft.showOnMap,
            isDark = true,
            isOnboarding = true,
            onChange = { onDraftChange(draft.copy(showOnMap = it)) },
        )
    }
}

// MARK: - Email and code

@Composable
private fun EmailStep(
    appModel: AppViewModel,
    embedded: Boolean,
    onBack: () -> Unit,
    onRequestCode: () -> Unit,
    onHaveCode: () -> Unit,
) {
    DismissOnSystemBack(onBack)
    val uriHandler = LocalUriHandler.current
    val haptics = rememberAppHaptics()
    val scope = rememberCoroutineScope()
    // Credential Manager draws its account picker over an Activity.
    val activityContext = LocalContext.current
    val cardShape = continuousShape(32.dp)

    Box(modifier = Modifier.fillMaxSize().background(AppTheme.pageBackground)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 22.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .appShadow(AppTheme.ink.copy(alpha = 0.08f), radius = 30.dp, offsetY = 18.dp, shape = cardShape)
                    .clip(cardShape)
                    .background(Color.White.copy(alpha = 0.92f))
                    .border(1.dp, Color.White.copy(alpha = 0.75f), cardShape)
                    .padding(horizontal = 32.dp, vertical = 40.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                Text(
                    L10n.string("Sign in", "Вход в профиль"),
                    fontSize = 34.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppTheme.ink,
                    maxLines = 1,
                )
                Text(
                    L10n.string(
                        "Sign in with your email to save your profile, matches, chats, and notifications.",
                        "Войди по email, чтобы сохранить профиль, матчи, переписки и уведомления.",
                    ),
                    style = AppText.title3,
                    color = AppTheme.mutedInk,
                )

                // iOS puts Sign in with Apple here. Android has no Apple sign-in,
                // so Google takes the same slot; hidden when the build has no
                // Google client ID configured.
                if (GoogleSignIn.isAvailable) {
                    GoogleSignInButton(enabled = !appModel.isBusy) {
                        scope.launch {
                            appModel.signInWithGoogle(
                                context = activityContext,
                                userAgreementAccepted = true,
                            )
                        }
                    }
                    AuthDividerLabel(L10n.string("or sign in with email", "или войти по Email"))
                }

                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Email", style = AppText.headline, color = AppTheme.ink)
                    OutlinedTextField(
                        value = appModel.authEmail,
                        onValueChange = { appModel.authEmail = it },
                        placeholder = { Text("example@mail.com", fontSize = 22.sp) },
                        leadingIcon = { Icon(Icons.Filled.Email, contentDescription = null) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                        shape = continuousShape(18.dp),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.White,
                            unfocusedContainerColor = Color.White,
                            focusedIndicatorColor = AppTheme.court.copy(alpha = 0.72f),
                            unfocusedIndicatorColor = Color(0xFFD1D1D6),
                        ),
                        modifier = Modifier.fillMaxWidth().height(68.dp),
                    )
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(66.dp)
                        .appShadow(AppTheme.court.copy(alpha = 0.2f), radius = 16.dp, offsetY = 10.dp, shape = continuousShape(18.dp))
                        .clip(continuousShape(18.dp))
                        .background(
                            Brush.linearGradient(
                                listOf(Color(0xFF10523B), AppTheme.court.copy(alpha = 0.95f)),
                            ),
                        )
                        .clickable { onRequestCode() },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        L10n.string("Get a code by email", "Получить код по email"),
                        style = AppText.title3Bold,
                        color = Color.White,
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(
                        L10n.string(
                            "Use email sign-in if you previously registered on the web.",
                            "Email-вход нужен, если ты уже регистрировался раньше.",
                        ),
                        style = AppText.body,
                        color = AppTheme.mutedInk,
                    )
                    Text(
                        L10n.string("I already have a code", "У меня уже есть код"),
                        style = AppText.title3,
                        color = AppTheme.court,
                        modifier = Modifier.clickable { onHaveCode() },
                    )
                }

                LegalNotice()

                appModel.authMessage?.let { AuthInlineMessage(it, AppTheme.court, Icons.Filled.CheckCircle) }
                appModel.errorMessage?.let { AuthInlineMessage(it, Color(0xFFD1493F), Icons.Filled.Warning) }
                appModel.debugCode?.let {
                    AuthInlineMessage("Debug OTP: $it", Color(0xFFFF9500), Icons.Filled.Numbers)
                }
            }

            SecondaryActionButton(
                title = L10n.string("Back", "Назад"),
                onClick = onBack,
            )
        }
    }
}

@Composable
private fun CodeStep(
    appModel: AppViewModel,
    code: String,
    onCodeChange: (String) -> Unit,
    onChangeEmail: () -> Unit,
    onVerify: () -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize().background(AppTheme.pageBackground)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SectionCard(
                title = L10n.string("Verification", "Подтверждение"),
                subtitle = L10n.string(
                    "Enter the 6-digit code from the email. After verification, your profile will be saved to your account.",
                    "Введи 6 цифр из письма. После проверки профиль будет сохранён в аккаунте.",
                ),
            ) {
                OtpCodeField(code = code, onCodeChange = onCodeChange, modifier = Modifier.fillMaxWidth())

                PrimaryActionButton(
                    title = L10n.string("Sign in", "Войти"),
                    onClick = onVerify,
                    tint = AppTheme.ink,
                    enabled = code.trim().length == 6,
                )

                LegalNotice()
            }

            SecondaryActionButton(
                title = L10n.string("Change email", "Изменить email"),
                onClick = onChangeEmail,
            )

            appModel.errorMessage?.let { AuthInlineMessage(it, Color(0xFFD1493F), Icons.Filled.Warning) }
        }
    }
}

// MARK: - Shared pieces

/** Port of `OnboardingDarkBackground` + the shared step chrome. */
@Composable
private fun OnboardingDarkStep(
    stepIndex: Int,
    title: String,
    subtitle: String,
    primaryTitle: String,
    primaryEnabled: Boolean,
    showBack: Boolean,
    onBack: () -> Unit,
    onPrimary: () -> Unit,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(listOf(Color(0xFF03080A), Color(0xFF000304), Color(0xFF050A0B))),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Spacer(Modifier.height(24.dp))

            // OnboardingStepProgress(current:total:)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                (1..2).forEach { index ->
                    Box(
                        Modifier
                            .weight(1f)
                            .height(6.dp)
                            .background(
                                if (index <= stepIndex) OnboardingStepPalette.lime else Color.White.copy(alpha = 0.16f),
                                RoundedCornerShape(percent = 50),
                            ),
                    )
                }
            }

            Text(
                L10n.string("Step $stepIndex of 2", "Шаг $stepIndex из 2"),
                style = AppText.subheadlineSemibold.copy(fontWeight = FontWeight.Bold),
                color = OnboardingStepPalette.lime,
            )

            // The title is two lines by design; without its own line height it
            // inherits body text's ~22sp and the lines overlap.
            Text(title, fontSize = 31.sp, lineHeight = 37.sp, fontWeight = FontWeight.Black, color = Color.White)

            Text(
                subtitle,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.62f),
            )

            content()

            Spacer(Modifier.height(8.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                if (showBack) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(60.dp)
                            .clip(continuousShape(22.dp))
                            .background(OnboardingStepPalette.panel.copy(alpha = 0.86f))
                            .border(1.dp, Color.White.copy(alpha = 0.12f), continuousShape(22.dp))
                            .clickable(onClick = onBack),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            L10n.string("Back", "Назад"),
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Black,
                            color = Color.White.copy(alpha = 0.78f),
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(60.dp)
                        .clip(continuousShape(22.dp))
                        .background(
                            if (primaryEnabled) {
                                Brush.horizontalGradient(listOf(OnboardingStepPalette.lime, Color(0xFF8CE038)))
                            } else {
                                Brush.horizontalGradient(
                                    listOf(Color.White.copy(alpha = 0.18f), Color.White.copy(alpha = 0.12f)),
                                )
                            },
                        )
                        .clickable(enabled = primaryEnabled, onClick = onPrimary),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            primaryTitle,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Black,
                            color = Color.Black.copy(alpha = if (primaryEnabled) 0.92f else 0.38f),
                        )
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowForward,
                            contentDescription = null,
                            tint = Color.Black.copy(alpha = if (primaryEnabled) 0.92f else 0.38f),
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun OnboardingSectionTitle(text: String) {
    Text(text, style = AppText.headlineBold.copy(fontWeight = FontWeight.Black), color = Color.White)
}

@Composable
private fun OnboardingToggleCard(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val shape = continuousShape(22.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(OnboardingStepPalette.panel.copy(alpha = 0.9f))
            .border(1.dp, OnboardingStepPalette.stroke, shape)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = AppText.subheadlineSemibold, color = Color.White)
            Text(subtitle, style = AppText.caption, color = Color.White.copy(alpha = 0.56f))
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.Black,
                checkedTrackColor = OnboardingStepPalette.lime,
                uncheckedTrackColor = Color.White.copy(alpha = 0.12f),
            ),
        )
    }
}

/** Port of `legalAcceptanceControl`. */
/**
 * Port of `LegalDocuments.signInNotice`: pressing a sign-in button accepts the
 * User Agreement. There is no personal-data consent here — it cannot be part of
 * the agreement and is asked separately after onboarding.
 */
@Composable
fun LegalNotice(modifier: Modifier = Modifier) {
    val linkStyle = TextLinkStyles(SpanStyle(color = AppTheme.court, fontWeight = FontWeight.SemiBold, textDecoration = TextDecoration.Underline))
    val text = buildAnnotatedString {
        append(L10n.string("By continuing, you accept the ", "Нажимая кнопку, вы принимаете "))
        withLink(LinkAnnotation.Url(LegalDocuments.userAgreementUrl, linkStyle)) {
            append(L10n.string("User Agreement", "пользовательское соглашение"))
        }
        append(L10n.string(". How we process data is described in the ", ". Как мы обрабатываем данные — в "))
        withLink(LinkAnnotation.Url(LegalDocuments.privacyPolicyUrl, linkStyle)) {
            append(L10n.string("Privacy Policy", "политике конфиденциальности"))
        }
        append(".")
    }
    Text(text, style = AppText.footnote, color = AppTheme.ink.copy(alpha = 0.6f), modifier = modifier.fillMaxWidth())
}

/** Port of `AuthInlineMessage`. */
/**
 * "Continue with Google", in the light style the Sign in with Google branding
 * guidelines prescribe: white fill, neutral border, the four-colour G. Sized
 * like the iOS Apple button it replaces (68pt tall, 18pt corners).
 */
@Composable
private fun GoogleSignInButton(enabled: Boolean, onClick: () -> Unit) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(68.dp)
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color(0xFF747775), shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(R.drawable.ic_google_logo),
            contentDescription = null,
            modifier = Modifier.size(24.dp),
        )
        Spacer(Modifier.width(12.dp))
        Text(
            L10n.string("Continue with Google", "Продолжить с Google"),
            style = AppText.title3Semibold,
            color = Color(0xFF1F1F1F),
            maxLines = 1,
        )
    }
}

/** Port of `private struct AuthDividerLabel`. */
@Composable
private fun AuthDividerLabel(text: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f).height(1.dp).background(Color(0xFFD1D1D6)))
        Text(
            text,
            style = AppText.title3,
            color = AppTheme.mutedInk,
            maxLines = 1,
        )
        Box(Modifier.weight(1f).height(1.dp).background(Color(0xFFD1D1D6)))
    }
}

@Composable
private fun AuthInlineMessage(
    text: String,
    tint: Color,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
) {
    val shape = continuousShape(16.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(tint.copy(alpha = 0.10f))
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(text, style = AppText.footnote, color = tint)
    }
}

@Composable
private fun DarkTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = Color.White.copy(alpha = 0.38f)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        shape = continuousShape(20.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = OnboardingStepPalette.panelRaised,
            unfocusedContainerColor = OnboardingStepPalette.panelRaised,
            focusedTextColor = Color.White,
            unfocusedTextColor = Color.White,
            cursorColor = OnboardingStepPalette.lime,
            focusedIndicatorColor = OnboardingStepPalette.lime.copy(alpha = 0.7f),
            unfocusedIndicatorColor = OnboardingStepPalette.stroke,
        ),
        modifier = Modifier.fillMaxWidth().height(60.dp),
    )
}
