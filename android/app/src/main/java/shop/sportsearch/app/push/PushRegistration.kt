package shop.sportsearch.app.push

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import shop.sportsearch.app.BuildConfig
import shop.sportsearch.app.core.LocaleStore
import shop.sportsearch.app.data.TennisRepository

/**
 * Registers this device for push, the Android half of
 * `AppModel.registerForRemoteNotifications()` on iOS.
 *
 * Everything here is a no-op until google-services.json is added to app/ and
 * the build picks up the Firebase plugin, so the app ships and runs the same
 * either way - it simply receives no push.
 */
object PushRegistration {
    private const val TAG = "SportSearchPush"

    fun isConfigured(context: Context): Boolean =
        BuildConfig.HAS_FIREBASE_CONFIG && FirebaseApp.getApps(context).isNotEmpty()

    /**
     * Sends the current token to the backend. Safe to call on every sign-in and
     * every launch: the server upserts on the token, so repeats are free.
     */
    suspend fun register(context: Context, repository: TennisRepository) {
        if (!isConfigured(context)) {
            Log.i(TAG, "Push not configured: google-services.json is missing, skipping registration")
            return
        }

        val token = runCatching { currentToken() }
            .onFailure { Log.w(TAG, "Could not read the FCM token", it) }
            .getOrNull() ?: return

        registerToken(context, repository, token)
    }

    /** Shared by [register] and the service's `onNewToken`. */
    suspend fun registerToken(context: Context, repository: TennisRepository, token: String) {
        runCatching {
            repository.registerPushDevice(
                token = token,
                environment = if (BuildConfig.DEBUG) "development" else "production",
                bundleId = context.packageName,
                deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                locale = LocaleStore.current.code,
            )
        }.onFailure { Log.w(TAG, "Could not register the device for push", it) }
    }

    private suspend fun currentToken(): String = suspendCancellableCoroutine { continuation ->
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { token -> if (continuation.isActive) continuation.resume(token) }
            .addOnFailureListener { error -> if (continuation.isActive) continuation.resumeWithException(error) }
    }
}
