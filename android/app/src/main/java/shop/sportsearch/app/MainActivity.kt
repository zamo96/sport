package shop.sportsearch.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import androidx.core.view.WindowCompat
import shop.sportsearch.app.core.AppNavigationTarget
import shop.sportsearch.app.push.SportSearchMessagingService
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.RootScreen
import shop.sportsearch.app.ui.theme.SportSearchTheme

class MainActivity : ComponentActivity() {

    private val appModel: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        // The iOS app runs a light UI over a black tab bar; keep the same
        // treatment instead of letting the system tint the bars.
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = false
        }

        intent?.data?.let(appModel::handleIncomingUri)

        setContent {
            SportSearchTheme {
                LaunchedEffect(Unit) {
                    appModel.bootstrap()
                    routeFromNotification(intent)
                }
                RootScreen(appModel)
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        intent.data?.let(appModel::handleIncomingUri)
        routeFromNotification(intent)
    }

    /** `\.onReceive(.tennisNotificationRouteRequested)` in ContentView.swift:217. */
    private fun routeFromNotification(intent: android.content.Intent?) {
        intent ?: return
        // A notification drawn by onMessageReceived carries our own extras; one
        // FCM drew itself while the app was in the background arrives with the
        // payload's `click_action` and its data keys as they are.
        val fromTray = intent.action == SportSearchMessagingService.ACTION_OPEN_HREF
        val hrefKey =
            if (fromTray) SportSearchMessagingService.TRAY_EXTRA_HREF else SportSearchMessagingService.EXTRA_NOTIFICATION_HREF
        val deliveryIdKey =
            if (fromTray) SportSearchMessagingService.TRAY_EXTRA_DELIVERY_ID else SportSearchMessagingService.EXTRA_NOTIFICATION_DELIVERY_ID

        val href = intent.getStringExtra(hrefKey)
        val deliveryId = intent.getStringExtra(deliveryIdKey)
        intent.removeExtra(hrefKey)
        intent.removeExtra(deliveryIdKey)

        deliveryId?.takeIf { it.isNotBlank() }?.let(appModel::recordPushOpened)
        href?.let { AppNavigationTarget.fromNotificationHref(it)?.let(appModel::navigate) }
    }
}
