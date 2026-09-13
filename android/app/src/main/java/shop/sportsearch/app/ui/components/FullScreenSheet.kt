package shop.sportsearch.app.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import shop.sportsearch.app.core.BottomBarDisplayMode
import shop.sportsearch.app.ui.AppViewModel

/**
 * SwiftUI `.sheet` / `.fullScreenCover` presentations cover the tab bar. Compose
 * destinations here are drawn inside the tab scaffold instead, so every screen
 * that stands in for one of those sheets hides the bar while it is on screen.
 */
@Composable
fun HideBottomBarWhileVisible(appModel: AppViewModel) {
    DisposableEffect(Unit) {
        val previous = appModel.bottomBarDisplayMode
        appModel.bottomBarDisplayMode = BottomBarDisplayMode.HIDDEN
        onDispose { appModel.bottomBarDisplayMode = previous }
    }
}

/**
 * SwiftUI `.sheet` and `.fullScreenCover` are dismissed by a swipe or the
 * navigation bar's Back button; the Compose destinations that stand in for them
 * are plain screens, so without this the system Back button leaves the app
 * instead of closing the screen.
 *
 * Nested sheets each register their own handler, and the innermost one composes
 * last, so it is the one Back reaches first - the same order as on iOS.
 */
@Composable
fun DismissOnSystemBack(onDismiss: () -> Unit) {
    BackHandler(onBack = onDismiss)
}
