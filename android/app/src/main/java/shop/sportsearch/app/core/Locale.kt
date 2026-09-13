package shop.sportsearch.app.core

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/** Port of `enum AppLocale` in ios/TennisSearchIOS/App/LocaleStore.swift. */
enum class AppLocale(val code: String) {
    EN("en"),
    RU("ru");

    val displayName: String
        get() = when (this) {
            EN -> "English"
            RU -> "Русский"
        }

    companion object {
        fun from(code: String?): AppLocale? =
            entries.firstOrNull { it.code == code?.lowercase() }
    }
}

/**
 * Port of `final class LocaleStore`. The iOS app keeps a manual override in
 * UserDefaults and otherwise follows the device language; anything that is not
 * Russian falls back to English.
 */
class LocaleStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // A public `var manualOverride` with a private setter would generate
    // setManualOverride(AppLocale?), which clashes on the JVM with the
    // setManualOverride(AppLocale) that mirrors the Swift API. Backing the
    // observable state with a private field keeps both names.
    private var overrideState: AppLocale? by mutableStateOf(
        AppLocale.from(context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(MANUAL_OVERRIDE_KEY, null)),
    )

    val manualOverride: AppLocale?
        get() = overrideState

    val effectiveLocale: AppLocale
        get() = overrideState ?: deviceLocale()

    val hasManualOverride: Boolean
        get() = overrideState != null

    fun setManualOverride(locale: AppLocale) {
        prefs.edit().putString(MANUAL_OVERRIDE_KEY, locale.code).apply()
        overrideState = locale
        current = locale
    }

    fun clearManualOverride() {
        prefs.edit().remove(MANUAL_OVERRIDE_KEY).apply()
        overrideState = null
        current = deviceLocale()
    }

    init {
        current = effectiveLocale
    }

    companion object {
        private const val PREFS_NAME = "sportsearch.locale"

        /** Same key the iOS client uses, so the two stay conceptually in sync. */
        private const val MANUAL_OVERRIDE_KEY = "ios.locale-override.v1"

        private fun deviceLocale(): AppLocale =
            if (Locale.getDefault().language.lowercase() == AppLocale.RU.code) AppLocale.RU else AppLocale.EN

        private val currentState = mutableStateOf(deviceLocale())

        /**
         * Mirrors `LocaleStore.currentEffectiveLocale`, and exists so plain model
         * code can call [L10n.string] the way the Swift models do.
         *
         * It is backed by snapshot state on purpose: every `L10n.string()` call
         * reads it, so making it observable is what lets the whole tree switch
         * language at once, the way SwiftUI views do off the @EnvironmentObject.
         * A plain `var` here leaves every already-composed string in the old
         * language until its screen happens to be recreated.
         */
        var current: AppLocale
            get() = currentState.value
            internal set(value) {
                currentState.value = value
            }
    }
}

/** Port of `enum L10n`. */
object L10n {
    fun string(english: String, russian: String, locale: AppLocale = LocaleStore.current): String =
        if (locale == AppLocale.RU) russian else english
}
