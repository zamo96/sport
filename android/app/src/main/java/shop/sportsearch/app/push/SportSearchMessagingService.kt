package shop.sportsearch.app.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import shop.sportsearch.app.BuildConfig
import shop.sportsearch.app.MainActivity
import shop.sportsearch.app.R
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.LocaleStore
import shop.sportsearch.app.data.ApiClient
import shop.sportsearch.app.data.LiveTennisRepository

/**
 * Receives pushes sent by src/lib/fcm.ts. The payload carries the same `href`
 * the APNs one does, so a tap lands on the same screen as on iOS.
 */
class SportSearchMessagingService : FirebaseMessagingService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        // Tokens rotate on reinstall and on a data wipe; the server upserts on
        // the token, so the old row is left to age out on its next failure.
        val repository = LiveTennisRepository(ApiClient(applicationContext) { LocaleStore.current.code })
        scope.launch { PushRegistration.registerToken(applicationContext, repository, token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"] ?: return
        val body = message.notification?.body ?: message.data["body"].orEmpty()
        val href = message.data["href"]

        showNotification(applicationContext, title, body, href)
    }

    private fun showNotification(context: Context, title: String, body: String, href: String?) {
        ensureChannel(context)

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            // The href is the server's own path, the same string APNs carries, so
            // it goes to AppNavigationTarget.fromNotificationHref rather than the
            // web deep-link parser.
            href?.let { putExtra(EXTRA_NOTIFICATION_HREF, it) }
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            href.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .build()

        runCatching {
            NotificationManagerCompat.from(context).notify(href.hashCode(), notification)
        }
    }

    companion object {
        const val CHANNEL_ID = "sportsearch.games"
        const val EXTRA_NOTIFICATION_HREF = "shop.sportsearch.app.NOTIFICATION_HREF"

        /** Android 8+ drops a notification whose channel does not exist yet. */
        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return

            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    L10n.string("Games and invites", "Игры и приглашения"),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = L10n.string(
                        "Invites, responses to your searches and chat messages.",
                        "Приглашения, отклики на поиски и сообщения в чате.",
                    )
                },
            )
        }
    }
}
