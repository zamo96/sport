package shop.sportsearch.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.ReportGmailerrorred
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.UserSafetyContext
import shop.sportsearch.app.core.UserSafetyReason
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Port of `struct UserSafetyActions` / `UserSafetyMenuButton` /
 * `UserSafetyReportSheet` in ios/TennisSearchIOS/Views/UIComponents.swift.
 *
 * The Swift original hard-codes Russian here instead of going through `L10n`,
 * so these strings stay Russian in the English build on both clients. Copying
 * that keeps the two apps identical; it is worth fixing in both at once.
 */

private enum class SafetyActionMode { REPORT, BLOCK }

@Composable
fun UserSafetyActions(
    appModel: AppViewModel,
    userId: String,
    displayName: String,
    context: UserSafetyContext,
    onBlocked: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var mode by remember { mutableStateOf<SafetyActionMode?>(null) }

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SecondaryActionButton(
            title = "Пожаловаться",
            onClick = { mode = SafetyActionMode.REPORT },
            tint = AppTheme.clay,
        )

        SecondaryActionButton(
            title = "Заблокировать и пожаловаться",
            onClick = { mode = SafetyActionMode.BLOCK },
            tint = Color.Red.copy(alpha = 0.9f),
        )
    }

    mode?.let { selected ->
        UserSafetyReportSheet(
            appModel = appModel,
            userId = userId,
            displayName = displayName,
            context = context,
            mode = selected,
            onDismiss = { mode = null },
            onBlocked = {
                mode = null
                onBlocked()
            },
        )
    }
}

/** Port of `struct UserSafetyMenuButton` - the "…" pill over a player card. */
@Composable
fun UserSafetyMenuButton(
    appModel: AppViewModel,
    userId: String,
    displayName: String,
    context: UserSafetyContext,
    onBlocked: () -> Unit,
    modifier: Modifier = Modifier,
    onPresentationChanged: ((Boolean) -> Unit)? = null,
) {
    var mode by remember { mutableStateOf<SafetyActionMode?>(null) }
    var isMenuExpanded by remember { mutableStateOf(false) }

    fun setMenu(expanded: Boolean) {
        isMenuExpanded = expanded
        onPresentationChanged?.invoke(expanded || mode != null)
    }

    Box(modifier = modifier) {
        Box(
            modifier = Modifier
                .size(42.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.48f))
                .border(1.dp, Color.White.copy(alpha = 0.18f), CircleShape)
                .clickable { setMenu(true) },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.MoreHoriz,
                contentDescription = "Безопасность профиля",
                tint = Color.White,
                modifier = Modifier.size(20.dp),
            )
        }

        DropdownMenu(
            expanded = isMenuExpanded,
            onDismissRequest = { setMenu(false) },
            containerColor = AppTheme.creamLight,
        ) {
            DropdownMenuItem(
                text = { Text("Пожаловаться", style = AppText.subheadline, color = AppTheme.ink) },
                leadingIcon = { Icon(Icons.Filled.ReportGmailerrorred, null, tint = AppTheme.clay) },
                onClick = {
                    isMenuExpanded = false
                    mode = SafetyActionMode.REPORT
                    onPresentationChanged?.invoke(true)
                },
            )
            DropdownMenuItem(
                text = { Text("Заблокировать и пожаловаться", style = AppText.subheadline, color = Color.Red) },
                leadingIcon = { Icon(Icons.Filled.PersonRemove, null, tint = Color.Red) },
                onClick = {
                    isMenuExpanded = false
                    mode = SafetyActionMode.BLOCK
                    onPresentationChanged?.invoke(true)
                },
            )
        }
    }

    mode?.let { selected ->
        UserSafetyReportSheet(
            appModel = appModel,
            userId = userId,
            displayName = displayName,
            context = context,
            mode = selected,
            onDismiss = {
                mode = null
                onPresentationChanged?.invoke(false)
            },
            onBlocked = {
                mode = null
                onPresentationChanged?.invoke(false)
                onBlocked()
            },
        )
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun UserSafetyReportSheet(
    appModel: AppViewModel,
    userId: String,
    displayName: String,
    context: UserSafetyContext,
    mode: SafetyActionMode,
    onDismiss: () -> Unit,
    onBlocked: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()

    var reason by remember { mutableStateOf(UserSafetyReason.HARASSMENT) }
    var details by remember { mutableStateOf("") }
    var isSubmitting by remember { mutableStateOf(false) }
    var successMessage by remember { mutableStateOf<String?>(null) }

    val isBlocking = mode == SafetyActionMode.BLOCK

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.Black,
        shape = continuousShape(32.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .imePadding()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    if (isBlocking) "Заблокировать $displayName" else "Жалоба на $displayName",
                    style = AppText.title2Bold,
                    color = Color.White,
                )
                Text(
                    if (isBlocking) {
                        "Профиль исчезнет из подбора и чатов. Жалоба будет отправлена модератору."
                    } else {
                        "Модератор проверит жалобу в течение 24 часов."
                    },
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.68f),
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Причина", style = AppText.headline, color = Color.White)

                UserSafetyReason.entries.forEach { option ->
                    val selected = reason == option
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color.White.copy(alpha = if (selected) 0.1f else 0.05f))
                            .clickable { reason = option }
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                            contentDescription = null,
                            tint = if (selected) AppTheme.court else Color.White.copy(alpha = 0.42f),
                            modifier = Modifier.size(22.dp),
                        )
                        Text(option.title, style = AppText.subheadline, color = Color.White)
                        Spacer(Modifier.weight(1f))
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Подробности — необязательно", style = AppText.headline, color = Color.White)
                OutlinedTextField(
                    value = details,
                    onValueChange = { details = it },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 110.dp),
                    placeholder = {
                        Text("Опишите, что произошло", color = Color.White.copy(alpha = 0.38f), style = AppText.subheadline)
                    },
                    textStyle = AppText.subheadline.copy(color = Color.White),
                    shape = RoundedCornerShape(16.dp),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.White.copy(alpha = 0.07f),
                        unfocusedContainerColor = Color.White.copy(alpha = 0.07f),
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        cursorColor = AppTheme.court,
                    ),
                )
            }

            successMessage?.let { message ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.CheckCircle, null, tint = AppTheme.mint, modifier = Modifier.size(18.dp))
                    Text(message, style = AppText.subheadlineSemibold, color = AppTheme.mint)
                }
            }

            Box {
                PrimaryActionButton(
                    title = if (isBlocking) "Заблокировать и отправить" else "Отправить жалобу",
                    onClick = {
                        if (isSubmitting || successMessage != null) return@PrimaryActionButton
                        scope.launch {
                            isSubmitting = true
                            val trimmed = details.trim().ifEmpty { null }
                            runCatching {
                                if (isBlocking) {
                                    appModel.repository.blockUser(userId, reason, trimmed, context)
                                } else {
                                    appModel.repository.reportUser(userId, reason, trimmed, context)
                                }
                            }.onSuccess {
                                haptics.success()
                                if (isBlocking) {
                                    successMessage = "Пользователь заблокирован, жалоба отправлена"
                                    delay(650)
                                    onBlocked()
                                } else {
                                    successMessage = "Жалоба отправлена модератору"
                                }
                            }.onFailure(appModel::present)
                            isSubmitting = false
                        }
                    },
                    tint = if (isBlocking) Color.Red else AppTheme.court,
                    enabled = !isSubmitting && successMessage == null,
                )

                if (isSubmitting) {
                    Box(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
    }
}
