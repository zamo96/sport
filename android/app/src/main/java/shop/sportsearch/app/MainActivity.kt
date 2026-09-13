package shop.sportsearch.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import androidx.core.view.WindowCompat
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
                LaunchedEffect(Unit) { appModel.bootstrap() }
                RootScreen(appModel)
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        intent.data?.let(appModel::handleIncomingUri)
    }
}
