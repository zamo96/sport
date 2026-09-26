package shop.sportsearch.app.ui

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import shop.sportsearch.app.core.*
import shop.sportsearch.app.data.ApiClient
import shop.sportsearch.app.data.ApiException
import shop.sportsearch.app.data.LiveTennisRepository
import shop.sportsearch.app.data.MockRepository
import shop.sportsearch.app.data.TennisRepository
import java.io.IOException
import java.util.UUID
import shop.sportsearch.app.push.PushOpenStore
import shop.sportsearch.app.push.PushRegistration
import shop.sportsearch.app.ui.auth.GoogleSignIn

/**
 * Port of `@MainActor final class AppModel`. Same published state, same
 * bootstrap/auth/profile flow; an AndroidViewModel replaces ObservableObject.
 */
class AppViewModel(application: Application) : AndroidViewModel(application) {

    data class ServerRecoveryNotice(
        val id: String = UUID.randomUUID().toString(),
        val title: String,
        val message: String,
    )

    data class LocaleRecommendation(val locale: AppLocale)

    val localeStore = LocaleStore(application)

    val isUsingMockData: Boolean = AppConfig.useMockData

    private val apiClient = ApiClient(application) { localeStore.effectiveLocale.code }

    val repository: TennisRepository =
        if (isUsingMockData) MockRepository() else LiveTennisRepository(apiClient)

    private val guestDraftStore = GuestDraftStore(application)
    private val discoverHintStore = DiscoverHintStore(application)
    private val pushOpenStore = PushOpenStore(application)
    private var guestDraftSaveJob: Job? = null

    var currentUser by mutableStateOf<UserProfile?>(null)
    var guestDraft by mutableStateOf(guestDraftStore.load())
        private set
    var isBusy by mutableStateOf(false)
    var authEmail by mutableStateOf("")
    /** Sign-in country: Russia uses a phone or VK ID, everyone else email or Google. */
    var authCountry by mutableStateOf(AuthCountry.suggested(guestDraft.location?.countryCode?.takeIf { it.isNotEmpty() }))
    var authPhone by mutableStateOf("+7 ")
    var authCodeTarget by mutableStateOf(AuthCodeTarget.EMAIL)
    /** The VK ID button shows only once the server has VK_ID_CLIENT_ID. */
    var isVkIdAvailable by mutableStateOf(false)
        private set
    /** «Later» on the phone-link suggestion lasts until the next launch. */
    var isPhoneLinkPromptDismissed by mutableStateOf(false)
        private set
    /** PKCE of the VK ID sign-in in flight: only this app knows the verifier. */
    private var pendingVkSignIn: Pair<String, String>? = null
    var debugCode by mutableStateOf<String?>(null)
    var authMessage by mutableStateOf<String?>(null)
    var errorMessage by mutableStateOf<String?>(null)
    var presentedAuthStep by mutableStateOf<AuthStep?>(null)
    var pendingNavigationTarget by mutableStateOf<AppNavigationTarget?>(null)
    var pendingChatMatchID by mutableStateOf<String?>(null)
    var pendingSearchLobbyID by mutableStateOf<String?>(null)
    var pendingCreateSearchPrefill by mutableStateOf<CreateSearchPrefill?>(null)
    var pendingCourtID by mutableStateOf<String?>(null)
    var bottomBarDisplayMode by mutableStateOf(BottomBarDisplayMode.EXPANDED)
    var pendingHighlightedDiscoverUserID by mutableStateOf<String?>(null)
    var pendingHighlightedSearchID by mutableStateOf<String?>(null)
    var pendingHighlightedGameRequestID by mutableStateOf<String?>(null)
    var pendingDiscoverSimilarPlayersHint by mutableStateOf(discoverHintStore.hasPendingSimilarPlayersHint())
    var pendingDiscoverFirstInterestHint by mutableStateOf(discoverHintStore.hasPendingFirstInterestHint())
    var lastSelectedDiscoverTab by mutableStateOf(DiscoverTab.SWIPE)
    var hasActiveUpcomingGameRequests by mutableStateOf(false)
    var serverRecoveryNotice by mutableStateOf<ServerRecoveryNotice?>(null)
    var pendingLocaleRecommendation by mutableStateOf<LocaleRecommendation?>(null)

    private val tabContentLoadingKeys = mutableStateListOf<String>()

    var activitySummary by mutableStateOf(ActivitySummary())
        private set

    val isAuthenticated: Boolean get() = currentUser != null

    val isGuestModeAvailable: Boolean
        get() = !isAuthenticated && guestDraft.hasCompletedOnboarding

    val canEnterApp: Boolean
        get() = currentUser?.hasCompletedOnboarding == true || isGuestModeAvailable

    // MARK: - Bootstrap

    fun bootstrap() {
        if (isUsingMockData) return
        viewModelScope.launch {
            val user = runCatching { repository.fetchCurrentUser() }
                .getOrNull()
                ?.let { reconcileLocalePreference(it) }
            if (user != null && !user.hasCompletedOnboarding) {
                updateGuestDraft(OnboardingRequirements.resumeDraft(user, guestDraft))
            }
            currentUser = user
            if (currentUser != null) {
                refreshActivitySummary()
                registerForPush()
            }
        }
    }

    /** `AppModel.registerForRemoteNotifications()` - only ever for a real session. */
    private fun registerForPush() {
        if (isUsingMockData) return
        viewModelScope.launch {
            PushRegistration.register(getApplication(), repository)
        }
        // Taps queued before the session came back belong to this user now.
        flushPushOpens()
    }

    /** `NotificationManager.recordPushOpened(deliveryId:)` on iOS. */
    fun recordPushOpened(deliveryId: String) {
        if (isUsingMockData) return
        pushOpenStore.add(deliveryId)
        if (currentUser != null) flushPushOpens()
    }

    /**
     * Sends queued opens one by one and keeps whatever failed for the next
     * session. Two overlapping flushes may report an id twice; the server only
     * stamps the first one, so that costs a request, not a wrong metric.
     */
    private fun flushPushOpens() {
        viewModelScope.launch {
            for (deliveryId in pushOpenStore.pending()) {
                val reported = runCatching { repository.reportPushOpened(deliveryId) }.isSuccess
                if (!reported) return@launch
                pushOpenStore.remove(deliveryId)
            }
        }
    }

    fun refreshActivitySummary() {
        viewModelScope.launch {
            runCatching { repository.fetchActivitySummary() }.getOrNull()?.let { activitySummary = it }
        }
    }

    // MARK: - Locale

    fun considerLocaleRecommendation(place: GeoPlace) {
        if (localeStore.hasManualOverride) return
        val recommendation = AppLocale.from(place.recommendedLocale) ?: return
        if (recommendation == localeStore.effectiveLocale) return
        pendingLocaleRecommendation = LocaleRecommendation(recommendation)
    }

    fun acceptLocaleRecommendation() {
        val recommendation = pendingLocaleRecommendation ?: return
        setManualLocale(recommendation.locale)
        pendingLocaleRecommendation = null
    }

    fun dismissLocaleRecommendation() {
        pendingLocaleRecommendation = null
    }

    fun setManualLocale(locale: AppLocale) {
        localeStore.setManualOverride(locale)
        currentUser?.let { user ->
            currentUser = user.copy(localeOverride = locale.code)
            viewModelScope.launch { runCatching { repository.updateLocaleOverride(locale.code) } }
        }
    }

    private suspend fun reconcileLocalePreference(user: UserProfile): UserProfile {
        AppLocale.from(user.localeOverride)?.let { accountLocale ->
            localeStore.setManualOverride(accountLocale)
            return user
        }

        val localLocale = localeStore.manualOverride ?: return user
        val saved = runCatching { repository.updateLocaleOverride(localLocale.code) }.isSuccess
        return if (saved) user.copy(localeOverride = localLocale.code) else user
    }

    // MARK: - Guest draft

    fun updateGuestDraft(draft: GuestOnboardingDraft) {
        guestDraft = draft
        guestDraftSaveJob?.cancel()
        guestDraftSaveJob = viewModelScope.launch {
            delay(180)
            guestDraftStore.save(draft)
        }
    }

    fun resetGuestDraft() {
        guestDraftSaveJob?.cancel()
        guestDraft = GuestOnboardingDraft.DEFAULT
        guestDraftStore.clear()
    }

    // MARK: - Auth

    fun presentAuth(step: AuthStep) {
        presentedAuthStep = step
    }

    fun dismissPresentedAuth() {
        presentedAuthStep = null
    }

    suspend fun requestCode(
        userAgreementAccepted: Boolean,
        userAgreementVersion: String = LegalDocuments.USER_AGREEMENT_VERSION,
    ): Boolean {
        if (authEmail.trim().isEmpty()) {
            errorMessage = L10n.string("Enter your email", "Укажи email")
            return false
        }
        if (!userAgreementAccepted) {
            errorMessage = LegalDocuments.acceptanceError
            return false
        }

        isBusy = true
        return try {
            val challenge = repository.requestCode(authEmail, userAgreementAccepted, userAgreementVersion)
            authMessage = challenge.message
            debugCode = challenge.debugCode
            errorMessage = null
            true
        } catch (error: Throwable) {
            present(error)
            false
        } finally {
            isBusy = false
        }
    }

    suspend fun verify(
        code: String,
        userAgreementAccepted: Boolean,
        userAgreementVersion: String = LegalDocuments.USER_AGREEMENT_VERSION,
    ) {
        if (authEmail.trim().isEmpty()) {
            errorMessage = L10n.string("Enter your email first", "Сначала укажи email")
            return
        }
        if (!userAgreementAccepted) {
            errorMessage = LegalDocuments.acceptanceError
            return
        }

        isBusy = true
        try {
            repository.verifyCode(
                email = authEmail,
                code = code,
                userAgreementAccepted = userAgreementAccepted,
                userAgreementVersion = userAgreementVersion,
                showOnMap = guestDraft.showOnMap,
            )
            completeSignIn()
        } catch (error: Throwable) {
            present(error)
        } finally {
            isBusy = false
        }
    }

    /**
     * Sign in with Google - on Android it takes the place Sign in with Apple
     * holds on iOS. [context] must be an Activity: Credential Manager shows its
     * account picker over it.
     */
    suspend fun signInWithGoogle(
        context: android.content.Context,
        userAgreementAccepted: Boolean,
        userAgreementVersion: String = LegalDocuments.USER_AGREEMENT_VERSION,
    ) {
        if (!userAgreementAccepted) {
            errorMessage = LegalDocuments.acceptanceError
            return
        }

        isBusy = true
        try {
            val idToken = GoogleSignIn.requestIdToken(context) ?: return
            repository.signInWithGoogle(
                idToken = idToken,
                userAgreementAccepted = userAgreementAccepted,
                userAgreementVersion = userAgreementVersion,
                showOnMap = guestDraft.showOnMap,
            )
            completeSignIn()
        } catch (error: Throwable) {
            present(error)
        } finally {
            isBusy = false
        }
    }

    // MARK: - Sign-in for Russia: phone and VK ID (149-FZ art. 8 part 10)

    suspend fun requestPhoneCode(): Boolean {
        val phone = RussianPhone.normalized(authPhone)
        if (phone == null) {
            errorMessage = L10n.string("Enter a Russian mobile number: +7 9XX XXX-XX-XX", "Укажите российский мобильный номер: +7 9XX XXX-XX-XX")
            return false
        }
        isBusy = true
        return try {
            val challenge = repository.requestPhoneCode(phone, LegalDocuments.USER_AGREEMENT_VERSION)
            authCodeTarget = AuthCodeTarget.PHONE
            authMessage = challenge.message
            debugCode = challenge.debugCode
            errorMessage = null
            true
        } catch (error: Throwable) {
            present(error)
            false
        } finally {
            isBusy = false
        }
    }

    suspend fun verifyPhone(code: String) {
        val phone = RussianPhone.normalized(authPhone)
        if (phone == null) {
            errorMessage = L10n.string("Enter your phone number first", "Сначала укажите номер телефона")
            return
        }
        isBusy = true
        try {
            repository.verifyPhoneCode(phone, code, LegalDocuments.USER_AGREEMENT_VERSION, guestDraft.showOnMap)
            completeSignIn()
        } catch (error: Throwable) {
            present(error)
        } finally {
            isBusy = false
        }
    }

    suspend fun loadVkIdAvailability() {
        if (isVkIdAvailable) return
        val config = runCatching { repository.fetchVkIdConfig() }.getOrNull() ?: return
        isVkIdAvailable = config.available
    }

    /**
     * Opens VK ID in a Custom Tab. VK returns to /auth/vk/callback, which
     * redirects to sportsearch://auth/vk; MainActivity (singleTask) hands that
     * back to [handleIncomingUri].
     */
    suspend fun startVkSignIn(context: Context) {
        errorMessage = null
        val config = try {
            repository.fetchVkIdConfig()
        } catch (error: Throwable) {
            present(error)
            return
        }
        val clientId = config.clientId
        if (!config.available || clientId == null) {
            errorMessage = L10n.string("VK ID sign-in is not available yet. Use your phone number.", "Вход через VK ID пока недоступен. Войдите по номеру телефона.")
            return
        }
        val verifier = VkIdPkce.randomString(48)
        // The android_ prefix tells the return page to hand the code back to the app.
        val state = "android_" + VkIdPkce.randomString(32)
        pendingVkSignIn = verifier to state
        val uri = android.net.Uri.parse(config.authorizeUrl).buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("redirect_uri", config.redirectUri)
            .appendQueryParameter("state", state)
            .appendQueryParameter("code_challenge", VkIdPkce.challenge(verifier))
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("scope", config.scope)
            .build()
        androidx.browser.customtabs.CustomTabsIntent.Builder().build().launchUrl(context, uri)
    }

    private suspend fun completeVkSignIn(uri: android.net.Uri) {
        val pending = pendingVkSignIn
        pendingVkSignIn = null
        val code = uri.getQueryParameter("code")
        val deviceId = uri.getQueryParameter("device_id")
        val state = uri.getQueryParameter("state")
        if (pending == null || code == null || deviceId == null || state != pending.second) {
            errorMessage = L10n.string("Could not sign in with VK ID. Try again.", "Не удалось войти через VK ID. Попробуйте ещё раз.")
            return
        }
        isBusy = true
        try {
            repository.signInWithVk(code, pending.first, deviceId, state, LegalDocuments.USER_AGREEMENT_VERSION, guestDraft.showOnMap)
            completeSignIn()
        } catch (error: Throwable) {
            present(error)
        } finally {
            isBusy = false
        }
    }

    /** The phone-link suggestion — after the consent screen, once per launch. */
    val isPhoneLinkPromptVisible: Boolean
        get() {
            val user = currentUser ?: return false
            return !isConsentReviewRequired && !isPhoneLinkPromptDismissed && presentedAuthStep == null &&
                user.hasCompletedOnboarding && user.phoneLinkSuggested
        }

    fun dismissPhoneLinkPrompt() {
        isPhoneLinkPromptDismissed = true
    }

    /** Returns (debugCode, error message): the link screen shows them itself. */
    suspend fun requestPhoneLinkCode(rawPhone: String): Pair<String?, String?> {
        val phone = RussianPhone.normalized(rawPhone)
            ?: return null to L10n.string("Enter a Russian mobile number: +7 9XX XXX-XX-XX", "Укажите российский мобильный номер: +7 9XX XXX-XX-XX")
        return try {
            repository.requestPhoneLinkCode(phone).debugCode to null
        } catch (error: Throwable) {
            null to (if (error.isServerIssue) error.serverRecoveryMessage else error.detailedMessage)
        }
    }

    suspend fun verifyPhoneLink(rawPhone: String, code: String): String? {
        val phone = RussianPhone.normalized(rawPhone)
            ?: return L10n.string("Enter your phone number first", "Сначала укажите номер телефона")
        return try {
            currentUser = repository.verifyPhoneLink(phone, code)
            null
        } catch (error: Throwable) {
            if (error.isServerIssue) error.serverRecoveryMessage else error.detailedMessage
        }
    }

    /**
     * Everything after the backend has issued a session, shared by the email
     * code and Google paths so the ordering below cannot drift between them.
     */
    private suspend fun completeSignIn() {
        var user = reconcileLocalePreference(repository.fetchCurrentUser())
        // The session token is already stored, so the account has to be
        // adopted before anything that can throw. Assigning it only after the
        // profile save left `currentUser` null on failure while the token was
        // live: the app fell back to guest mode and still sent authenticated
        // requests. Same shape as `AppModel.verify(code:...)` on iOS.
        currentUser = user

        if (!user.hasCompletedOnboarding && guestDraft.hasCompletedOnboarding) {
            user = repository.updateProfile(makeProfileFromGuestDraft(user))
        }

        if (user.hasCompletedOnboarding) {
            resetGuestDraft()
        } else {
            updateGuestDraft(OnboardingRequirements.resumeDraft(user, guestDraft))
        }
        currentUser = user
        registerForPush()
        authMessage = null
        debugCode = null
        errorMessage = null
        presentedAuthStep = null
        refreshActivitySummary()
    }

    /**
     * The consent screen shows after onboarding while there is no answer, and to
     * accounts created before separate consents — above everything but sign-in.
     */
    val isConsentReviewRequired: Boolean
        get() {
            val user = currentUser ?: return false
            return presentedAuthStep == null && user.hasCompletedOnboarding && user.consents?.reviewRequired == true
        }

    /**
     * Sends the consent-screen answer. Returns an error message: the screen shows
     * it itself, because the shared error dialog would stay underneath.
     */
    suspend fun submitConsents(update: ConsentUpdate): String? =
        try {
            currentUser = repository.updateConsents(update)
            null
        } catch (error: Throwable) {
            if (error.isServerIssue) error.serverRecoveryMessage else error.detailedMessage
        }

    suspend fun saveProfile(profile: UserProfile): Boolean {
        isBusy = true
        return try {
            currentUser = repository.updateProfile(profile)
            errorMessage = null
            serverRecoveryNotice = null
            true
        } catch (error: Throwable) {
            present(error)
            false
        } finally {
            isBusy = false
        }
    }

    fun logout() {
        guestDraftSaveJob?.cancel()
        repository.clearAuthSession()
        currentUser = null
        debugCode = null
        authMessage = null
        errorMessage = null
        authEmail = ""
        authPhone = "+7 "
        authCodeTarget = AuthCodeTarget.EMAIL
        isPhoneLinkPromptDismissed = false
        pendingVkSignIn = null
        presentedAuthStep = null
        pendingNavigationTarget = null
        pendingChatMatchID = null
        pendingSearchLobbyID = null
        pendingCreateSearchPrefill = null
        pendingCourtID = null
        bottomBarDisplayMode = BottomBarDisplayMode.EXPANDED
        pendingHighlightedDiscoverUserID = null
        pendingHighlightedSearchID = null
        pendingHighlightedGameRequestID = null
        pendingDiscoverSimilarPlayersHint = discoverHintStore.hasPendingSimilarPlayersHint()
        pendingDiscoverFirstInterestHint = discoverHintStore.hasPendingFirstInterestHint()
        hasActiveUpcomingGameRequests = false
        serverRecoveryNotice = null
        activitySummary = ActivitySummary()
    }

    // MARK: - Errors

    fun present(error: Throwable) {
        if (error.isServerIssue) {
            errorMessage = null
            serverRecoveryNotice = ServerRecoveryNotice(
                title = L10n.string("Something went wrong", "Что-то пошло не так"),
                message = error.serverRecoveryMessage,
            )
            return
        }

        serverRecoveryNotice = null
        errorMessage = error.detailedMessage
    }

    fun dismissServerRecoveryNotice() {
        serverRecoveryNotice = null
    }

    // MARK: - Tab loading

    fun setTabContentLoading(key: String, isLoading: Boolean) {
        if (isLoading) {
            if (!tabContentLoadingKeys.contains(key)) tabContentLoadingKeys.add(key)
        } else {
            tabContentLoadingKeys.remove(key)
        }
    }

    fun isTabContentLoading(key: String): Boolean = tabContentLoadingKeys.contains(key)

    // MARK: - Discover hints

    fun queueDiscoverSimilarPlayersHint() {
        lastSelectedDiscoverTab = DiscoverTab.SWIPE
        pendingDiscoverSimilarPlayersHint = true
        discoverHintStore.setPendingSimilarPlayersHint(true)
    }

    fun shouldPresentDiscoverSimilarPlayersHint(): Boolean = pendingDiscoverSimilarPlayersHint

    fun consumeDiscoverSimilarPlayersHint() {
        pendingDiscoverSimilarPlayersHint = false
        discoverHintStore.setPendingSimilarPlayersHint(false)
    }

    fun completeDiscoverSimilarPlayersHint() = consumeDiscoverSimilarPlayersHint()

    fun queueDiscoverFirstInterestHintIfNeeded(): Boolean {
        if (discoverHintStore.hasCompletedFirstInterestHint(currentUser?.id)) return false
        pendingDiscoverFirstInterestHint = true
        discoverHintStore.setPendingFirstInterestHint(true)
        return true
    }

    fun shouldPresentDiscoverFirstInterestHint(): Boolean =
        pendingDiscoverFirstInterestHint && !discoverHintStore.hasCompletedFirstInterestHint(currentUser?.id)

    fun consumeDiscoverFirstInterestHint() {
        pendingDiscoverFirstInterestHint = false
        discoverHintStore.setPendingFirstInterestHint(false)
    }

    fun completeDiscoverFirstInterestHint() {
        consumeDiscoverFirstInterestHint()
        discoverHintStore.setCompletedFirstInterestHint(true, currentUser?.id)
    }

    // MARK: - Navigation

    fun navigate(target: AppNavigationTarget) {
        pendingNavigationTarget = target
    }

    fun handleIncomingUri(uri: android.net.Uri): Boolean {
        if (uri.scheme == "sportsearch" && uri.host == "auth" && uri.path?.startsWith("/vk") == true) {
            viewModelScope.launch { completeVkSignIn(uri) }
            return true
        }
        val target = AppNavigationTarget.fromDeepLink(uri) ?: return false
        navigate(target)
        return true
    }

    fun clearPendingNavigation() {
        pendingNavigationTarget = null
        pendingHighlightedDiscoverUserID = null
        pendingHighlightedSearchID = null
        pendingHighlightedGameRequestID = null
    }

    // MARK: - Onboarding

    suspend fun completeGuestOnboarding(draft: GuestOnboardingDraft): Boolean {
        if (!draft.hasRequiredOnboardingFields) {
            updateGuestDraft(draft.copy(onboardingCompleted = false))
            errorMessage = L10n.string(
                "Enter your name and age, and select a sport and city.",
                "Укажи имя и возраст, выбери вид спорта и город.",
            )
            return false
        }
        updateGuestDraft(draft.copy(onboardingCompleted = true))
        val user = currentUser ?: return true
        if (user.hasCompletedOnboarding) return true
        val saved = saveProfile(makeProfileFromGuestDraft(user))
        if (saved) resetGuestDraft()
        return saved
    }

    private fun makeProfileFromGuestDraft(user: UserProfile): UserProfile = user.copy(
        name = guestDraft.name.trim(),
        age = guestDraft.age,
        genderRaw = guestDraft.gender?.wire,
        city = OnboardingRequirements.submissionCity(guestDraft.city, guestDraft.location),
        location = guestDraft.location,
        coverageRaw = guestDraft.location?.coverage ?: LocationCoverage.unavailable,
        locationSourceRaw = guestDraft.locationSource?.wire,
        district = guestDraft.preferredDistricts.firstOrNull() ?: guestDraft.district,
        preferredDistricts = guestDraft.preferredDistricts,
        tennisLevel = guestDraft.sportLevels[guestDraft.preferredSports.firstOrNull()?.wire ?: ""] ?: 5,
        preferredSports = guestDraft.preferredSports,
        sportLevels = guestDraft.sportLevels,
        preferredPlayFormatRaw = guestDraft.preferredPlayFormat.wire,
        preferredSurfaceRaw = guestDraft.preferredSurface.wire,
        availableDays = guestDraft.availableDays,
        availableTimeRanges = guestDraft.availableTimeRanges,
        availabilityByDay = guestDraft.availabilityByDay,
        isLookingForGame = guestDraft.isLookingForGame,
        showOnMap = OnboardingMapVisibility.resolved(
            stored = user.showOnMap,
            draft = guestDraft.showOnMap,
            completed = user.onboardingCompleted,
        ),
        searchRadiusKm = guestDraft.searchRadiusKm,
        onboardingCompleted = true,
    )
}

// MARK: - Error classification (`extension Error` in AppModel.swift)

val Throwable.isServerIssue: Boolean
    get() = when (this) {
        is ApiException.InvalidResponse, is ApiException.InvalidPayload -> true
        is ApiException.Server -> isInternalServerMessage
        is ApiException.InvalidBaseUrl -> false
        is IOException -> true
        else -> false
    }

val Throwable.serverRecoveryMessage: String
    get() = if (this is IOException) {
        L10n.string(
            "The service is temporarily unavailable. We are reconnecting and will fix it shortly.",
            "Сервис временно недоступен. Уже переподключаемся и скоро всё исправим.",
        )
    } else {
        L10n.string(
            "The service is responding unreliably right now. Try again in a couple of seconds.",
            "Сервис временно отвечает нестабильно. Попробуй ещё раз через пару секунд.",
        )
    }

val Throwable.isCancellationLike: Boolean
    get() = this is kotlinx.coroutines.CancellationException ||
        (message?.trim()?.lowercase() ?: "") in setOf("cancelled", "canceled")

val Throwable.detailedMessage: String
    get() {
        val parts = mutableListOf(message ?: this::class.java.simpleName)
        cause?.let { parts.add("Underlying: ${it::class.java.simpleName} ${it.message.orEmpty()}".trim()) }
        return parts.joinToString("\n")
    }

// MARK: - Local stores (`GuestDraftStore` / `DiscoverHintStore` in AppModel.swift)

private class GuestDraftStore(context: Context) {
    private val prefs = context.getSharedPreferences("sportsearch.drafts", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    fun load(): GuestOnboardingDraft {
        val raw = prefs.getString(KEY, null) ?: return GuestOnboardingDraft.DEFAULT
        return runCatching { json.decodeFromString(GuestOnboardingDraft.serializer(), raw) }
            .getOrDefault(GuestOnboardingDraft.DEFAULT)
    }

    fun save(draft: GuestOnboardingDraft) {
        prefs.edit()
            .putString(KEY, json.encodeToString(GuestOnboardingDraft.serializer(), draft))
            .apply()
    }

    fun clear() = prefs.edit().remove(KEY).apply()

    private companion object {
        const val KEY = "ios.guest-onboarding-draft.v1"
    }
}

private class DiscoverHintStore(context: Context) {
    private val prefs = context.getSharedPreferences("sportsearch.hints", Context.MODE_PRIVATE)

    fun hasPendingSimilarPlayersHint() = prefs.getBoolean(SIMILAR_PENDING, false)
    fun setPendingSimilarPlayersHint(value: Boolean) = prefs.edit().putBoolean(SIMILAR_PENDING, value).apply()

    fun hasPendingFirstInterestHint() = prefs.getBoolean(FIRST_INTEREST_PENDING, false)
    fun setPendingFirstInterestHint(value: Boolean) = prefs.edit().putBoolean(FIRST_INTEREST_PENDING, value).apply()

    fun hasCompletedFirstInterestHint(userId: String?) =
        prefs.getBoolean(completedKey(userId), false)

    fun setCompletedFirstInterestHint(value: Boolean, userId: String?) =
        prefs.edit().putBoolean(completedKey(userId), value).apply()

    /** `firstInterestCompletedKey(for:)` - a blank id scopes to the guest, not to "". */
    private fun completedKey(userId: String?): String {
        val scope = userId?.trim().orEmpty().ifEmpty { "guest" }
        return "$FIRST_INTEREST_DONE.$scope"
    }

    private companion object {
        const val SIMILAR_PENDING = "discover.hint.similar-players.pending"
        const val FIRST_INTEREST_PENDING = "discover.hint.first-interest.pending"
        const val FIRST_INTEREST_DONE = "discover.hint.first-interest.completed"
    }
}

/** PKCE for VK ID: the verifier stays in the app, VK only sees its hash. */
private object VkIdPkce {
    private val random = java.security.SecureRandom()

    fun randomString(byteCount: Int): String {
        val bytes = ByteArray(byteCount).also(random::nextBytes)
        return base64Url(bytes)
    }

    fun challenge(verifier: String): String =
        base64Url(java.security.MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))

    private fun base64Url(bytes: ByteArray): String =
        android.util.Base64.encodeToString(bytes, android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
}
