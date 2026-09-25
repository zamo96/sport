package shop.sportsearch.app.core

import android.net.Uri
import shop.sportsearch.app.BuildConfig
import java.time.LocalDate

/** Port of `enum AppConfig`. */
object AppConfig {
    const val PUBLIC_WEB_BASE_URL = "https://sportsearch.shop"

    val apiBaseUrl: String
        get() = "${BuildConfig.API_SCHEME}://${BuildConfig.API_BASE_URL}"

    val useMockData: Boolean get() = BuildConfig.USE_MOCK_DATA

    fun searchInviteUrl(searchId: String) = "$PUBLIC_WEB_BASE_URL/play/searches/invite/$searchId"

    fun profileUrl(userId: String) = "$PUBLIC_WEB_BASE_URL/users/$userId"
}

/** Port of `enum LegalDocuments`. */
object LegalDocuments {
    /** The version without bundled personal-data consent: the sign-in button accepts it. */
    const val USER_AGREEMENT_VERSION = "2026-09-24"

    val acceptanceError: String
        get() = L10n.string(
            "Accept the User Agreement.",
            "Нужно принять пользовательское соглашение.",
        )

    val userAgreementUrl: String get() = "${AppConfig.apiBaseUrl}/legal/terms"
    val privacyPolicyUrl: String get() = "${AppConfig.apiBaseUrl}/legal/privacy"
    val profileVisibilityConsentUrl: String get() = "${AppConfig.apiBaseUrl}/legal/profile-visibility"
    val analyticsConsentUrl: String get() = "${AppConfig.apiBaseUrl}/legal/analytics"
}

/**
 * Port of `struct CreateSearchPrefill`.
 *
 * Прифилл формы создания поиска из пуша «сходить на тренировку». День недели
 * превращается в окно «сегодня/завтра», потому что композер умеет только
 * срочные поиски (`SearchType.userVisibleCases == [hot]`).
 */
data class CreateSearchPrefill(
    val sport: Sport?,
    val hotWindow: HotWindow?,
    val hotStartTime: String?,
) {
    companion object {
        fun from(sport: Sport?, day: String?, timeRange: String?) = CreateSearchPrefill(
            sport = sport,
            hotWindow = window(day),
            hotStartTime = TimeRange.from(timeRange)?.let(::startTime),
        )

        private fun window(day: String?): HotWindow? {
            val target = DayOfWeek.from(day) ?: return null
            val windows = listOf(HotWindow.TODAY, HotWindow.TOMORROW, HotWindow.DAY_AFTER_TOMORROW)
            val today = LocalDate.now()

            windows.forEachIndexed { offset, window ->
                val candidate = today.plusDays(offset.toLong())
                if (weekday(candidate.dayOfWeek) == target) return window
            }
            return null
        }

        private fun weekday(value: java.time.DayOfWeek): DayOfWeek = when (value) {
            java.time.DayOfWeek.MONDAY -> DayOfWeek.MONDAY
            java.time.DayOfWeek.TUESDAY -> DayOfWeek.TUESDAY
            java.time.DayOfWeek.WEDNESDAY -> DayOfWeek.WEDNESDAY
            java.time.DayOfWeek.THURSDAY -> DayOfWeek.THURSDAY
            java.time.DayOfWeek.FRIDAY -> DayOfWeek.FRIDAY
            java.time.DayOfWeek.SATURDAY -> DayOfWeek.SATURDAY
            java.time.DayOfWeek.SUNDAY -> DayOfWeek.SUNDAY
        }

        private fun startTime(range: TimeRange): String = when (range) {
            TimeRange.MORNING -> "09:00"
            TimeRange.DAY -> "14:00"
            TimeRange.EVENING -> "19:00"
        }
    }
}

/** Port of `enum AppNavigationTarget`. */
sealed interface AppNavigationTarget {
    data class Discover(
        val tab: DiscoverTab,
        val highlightedUserID: String? = null,
        val highlightedSearchID: String? = null,
        val highlightedGameRequestID: String? = null,
    ) : AppNavigationTarget

    data object Matches : AppNavigationTarget
    data object Searches : AppNavigationTarget
    data class SearchLobby(val searchId: String) : AppNavigationTarget
    data class CreateSearch(val prefill: CreateSearchPrefill) : AppNavigationTarget
    data class Courts(val sport: Sport?) : AppNavigationTarget
    data class Chat(val matchId: String) : AppNavigationTarget
    data object Profile : AppNavigationTarget

    companion object {
        /** Port of `init?(deepLinkURL:)`. */
        fun fromDeepLink(uri: Uri): AppNavigationTarget? {
            if (uri.userInfo != null || uri.port != -1) return null

            val scheme = uri.scheme?.lowercase()
            val host = uri.host?.lowercase()
            val segments = validSegments(uri.encodedPath) ?: return null

            return when (scheme) {
                "https" -> {
                    if (host != "sportsearch.shop") return null
                    when {
                        segments.size == 2 && segments[0] == "users" ->
                            Discover(DiscoverTab.SWIPE, highlightedUserID = segments[1])
                        segments.size == 4 && segments[0] == "play" && segments[1] == "searches" && segments[2] == "invite" ->
                            Discover(DiscoverTab.HOT, highlightedSearchID = segments[3])
                        else -> null
                    }
                }
                "sportsearch" -> when {
                    host == "upcoming" && segments.isEmpty() -> Discover(DiscoverTab.UPCOMING)
                    host == "matches" && segments.isEmpty() -> Matches
                    host == "profile" && segments.size == 1 -> Discover(DiscoverTab.SWIPE, highlightedUserID = segments[0])
                    host == "invite" && segments.size == 1 -> Discover(DiscoverTab.HOT, highlightedSearchID = segments[0])
                    else -> null
                }
                else -> null
            }
        }

        /** Port of `init?(notificationHref:)`. */
        fun fromNotificationHref(href: String): AppNavigationTarget? {
            val uri = runCatching { Uri.parse(href) }.getOrNull() ?: return null
            val path = uri.path.orEmpty()

            return when {
                path.startsWith("/inbox/") -> Chat(path.removePrefix("/inbox/"))

                path == "/play/searches/new" || path == "/play/searches/new/" -> CreateSearch(
                    CreateSearchPrefill.from(
                        sport = Sport.from(uri.getQueryParameter("sport")),
                        day = uri.getQueryParameter("day"),
                        timeRange = uri.getQueryParameter("time"),
                    ),
                )

                path.startsWith("/play/searches/") -> SearchLobby(path.removePrefix("/play/searches/"))

                path == "/play/searches" || path.startsWith("/searches") -> Searches

                path.startsWith("/play/games/") ->
                    Discover(DiscoverTab.UPCOMING, highlightedGameRequestID = path.removePrefix("/play/games/"))

                path.startsWith("/discover") -> {
                    val highlight = uri.getQueryParameter("highlight")
                    when (uri.getQueryParameter("view") ?: "swipe") {
                        "likes" -> Discover(DiscoverTab.LIKES, highlightedUserID = highlight)
                        "hot" -> Discover(DiscoverTab.HOT, highlightedSearchID = highlight)
                        "upcoming" -> Discover(DiscoverTab.UPCOMING, highlightedGameRequestID = highlight)
                        "seeking", "regular" -> Discover(DiscoverTab.SEEKING, highlightedSearchID = highlight)
                        else -> Discover(DiscoverTab.SWIPE, highlightedUserID = highlight)
                    }
                }

                path.startsWith("/matches") || path.startsWith("/inbox") -> Matches

                path.startsWith("/onboarding") || path.startsWith("/profile") || path.startsWith("/settings") -> Profile

                else -> null
            }
        }

        /**
         * Deep-link segments are whitelisted to `[A-Za-z0-9_-]`, same as iOS, so
         * a crafted link cannot smuggle path traversal into an API call.
         */
        private fun validSegments(encodedPath: String?): List<String>? {
            if (encodedPath.isNullOrEmpty() || encodedPath == "/") return emptyList()
            if (!encodedPath.startsWith("/")) return null

            val segments = encodedPath.drop(1).split("/")
            val decoded = mutableListOf<String>()
            for (raw in segments) {
                if (raw.isEmpty()) return null
                val value = runCatching { Uri.decode(raw) }.getOrNull() ?: return null
                if (!isValidSegment(value)) return null
                decoded.add(value)
            }
            return decoded
        }

        private fun isValidSegment(segment: String): Boolean {
            if (segment.isEmpty() || segment.toByteArray().size > 200) return false
            return segment.all { it.isDigit() || it in 'A'..'Z' || it in 'a'..'z' || it == '-' || it == '_' }
        }
    }
}

enum class BottomBarDisplayMode { EXPANDED, COMPACT, HIDDEN }
