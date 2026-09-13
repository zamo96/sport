package shop.sportsearch.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct AvatarPreviewSheet` in UIComponents.swift. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun AvatarPreviewSheet(name: String, path: String?, onDismiss: () -> Unit) {
    DismissOnSystemBack(onDismiss)
    val sheetState = rememberModalBottomSheetState()
    val avatarShape = continuousShape(74.dp)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = AppTheme.cream,
        shape = continuousShape(32.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(AppTheme.pageBackground)
                .navigationBarsPadding()
                .padding(28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            RemoteAvatarView(
                name = name,
                path = path,
                size = 220.dp,
                modifier = Modifier
                    .appShadow(AppTheme.ink.copy(alpha = 0.18f), radius = 28.dp, offsetY = 14.dp, shape = avatarShape)
                    .border(2.dp, androidx.compose.ui.graphics.Color.White.copy(alpha = 0.74f), avatarShape),
            )

            Text(name, style = AppText.title3Bold, color = AppTheme.ink, textAlign = TextAlign.Center)
        }
    }
}
