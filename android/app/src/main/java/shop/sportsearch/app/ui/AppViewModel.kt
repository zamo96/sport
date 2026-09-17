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
import shop.sportsearch.app.push.PushRegistration

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
    private var guestDraftSaveJob: Job? = null

    var currentUser by mutableStateOf<UserProfile?>(null)
    var guestDraft by mutableStateOf(guestDraftStore.load())
        private set
    var isBusy by mutableStateOf(false)
    var authEmail by mutableStateOf("")
    var authUserAgreementAccepted by mutableStateOf(false)
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
        authUserAgreementAccepted = false
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
            authUserAgreementAccepted = false
            authMessage = null
            debugCode = null
            errorMessage = null
            presentedAuthStep = null
            refreshActivitySummary()
        } catch (error: Throwable) {
            present(error)
        } finally {
            isBusy = false
        }
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
        authUserAgreementAccepted = false
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
