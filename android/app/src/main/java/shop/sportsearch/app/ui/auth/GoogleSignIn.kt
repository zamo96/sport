package shop.sportsearch.app.ui.auth

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import shop.sportsearch.app.BuildConfig
import shop.sportsearch.app.core.L10n

/**
 * Obtains a Google ID token through Credential Manager - the Android side of
 * `SignInWithAppleButton` on iOS. The token goes to `POST /auth/google`, which
 * verifies it; nothing here is trusted on its own.
 */
object GoogleSignIn {
    /**
     * The *web* OAuth client ID. The ID token's audience is this value, and it
     * is what the server's GOOGLE_CLIENT_IDS lists. Empty when the build has no
     * Google project configured, in which case the button is not shown at all.
     */
    val webClientId: String get() = BuildConfig.GOOGLE_WEB_CLIENT_ID

    val isAvailable: Boolean get() = webClientId.isNotBlank()

    class Failure(message: String) : Exception(message)

    /** Returns null when the person closes the account picker - not an error. */
    suspend fun requestIdToken(context: Context): String? {
        if (!isAvailable) {
            throw Failure(
                L10n.string(
                    "Google sign-in is not available in this build.",
                    "Вход через Google недоступен в этой сборке.",
                ),
            )
        }

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(GetSignInWithGoogleOption.Builder(webClientId).build())
            .build()

        val credential = try {
            CredentialManager.create(context).getCredential(context, request).credential
        } catch (_: GetCredentialCancellationException) {
            return null
        } catch (_: NoCredentialException) {
            throw Failure(
                L10n.string(
                    "There is no Google account on this device. Add one in Settings or sign in with email.",
                    "На устройстве нет аккаунта Google. Добавьте его в настройках или войдите по email.",
                ),
            )
        }

        if (credential is CustomCredential &&
            credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            return GoogleIdTokenCredential.createFrom(credential.data).idToken
        }

        throw Failure(
            L10n.string(
                "Google returned an unexpected response. Try again or sign in with email.",
                "Google вернул неожиданный ответ. Попробуйте ещё раз или войдите по email.",
            ),
        )
    }
}
