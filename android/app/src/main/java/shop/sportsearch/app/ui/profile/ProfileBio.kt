package shop.sportsearch.app.ui.profile

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/**
 * Сервер режет описание на 220 символах (`publicText(220)` в validators.ts),
 * длиннее — весь профиль не сохраняется с 400. Как `ProfileBioLimit` в ProfileView.swift.
 */
const val PROFILE_BIO_MAX_LENGTH = 220

/** Port of `struct ProfileBioCard` in ProfileView.swift. */
@Composable
fun ProfileBioCard(bio: String?, onEdit: () -> Unit) {
    val text = bio?.trim()?.takeIf { it.isNotEmpty() }
    if (text == null) {
        ProfileBioEmptyCard(onEdit)
        return
    }

    var isExpanded by remember(text) { mutableStateOf(false) }
    var isTruncated by remember(text) { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.06f), continuousShape(18.dp))
            .padding(14.dp)
            .animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            ProfileBioSectionTitle()
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .clickable(onClick = onEdit),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Edit,
                    contentDescription = L10n.string("Edit description", "Изменить описание"),
                    tint = Color.White.copy(alpha = 0.72f),
                    modifier = Modifier.size(15.dp),
                )
            }
        }

        Text(
            text,
            style = AppText.subheadline,
            color = Color.White.copy(alpha = 0.86f),
            maxLines = if (isExpanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { if (!isExpanded) isTruncated = it.hasVisualOverflow },
        )

        if (isTruncated || isExpanded) {
            Text(
                if (isExpanded) L10n.string("Show less", "Свернуть") else L10n.string("More", "Ещё"),
                style = AppText.captionSemibold,
                color = AppTheme.mint,
                modifier = Modifier.clickable { isExpanded = !isExpanded },
            )
        }
    }
}

@Composable
private fun ProfileBioEmptyCard(onEdit: () -> Unit) {
    val dashColor = Color.White.copy(alpha = 0.22f)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .drawBehind {
                drawRoundRect(
                    color = dashColor,
                    cornerRadius = CornerRadius(18.dp.toPx()),
                    style = Stroke(
                        width = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx())),
                    ),
                )
            }
            .clip(continuousShape(18.dp))
            .clickable(onClick = onEdit)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ProfileBioSectionTitle()
        Text(
            L10n.string("Tell others who you'd like to play with", "Расскажите, с кем хотите играть"),
            style = AppText.subheadlineSemibold,
            color = Color.White,
        )
        Text(
            L10n.string("Players are more likely to reply to a profile with a description.", "На профиль с описанием чаще отвечают."),
            style = AppText.caption,
            color = Color.White.copy(alpha = 0.58f),
        )
        Row(
            modifier = Modifier.padding(top = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = AppTheme.mint, modifier = Modifier.size(14.dp))
            Text(L10n.string("Add description", "Добавить описание"), style = AppText.captionBold, color = AppTheme.mint)
        }
    }
}

@Composable
private fun ProfileBioSectionTitle() {
    Text(
        L10n.string("About me", "О себе").uppercase(),
        style = AppText.captionBold,
        color = Color.White.copy(alpha = 0.52f),
    )
}

/** Port of `struct ProfileBioEditorSheet` in ProfileView.swift. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ProfileBioEditorSheet(
    initialText: String,
    onSave: suspend (String) -> Boolean,
    onDismiss: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val focusRequester = remember { FocusRequester() }
    var text by rememberSaveable { mutableStateOf(initialText.take(PROFILE_BIO_MAX_LENGTH)) }
    var isSaving by remember { mutableStateOf(false) }

    val hints = listOf(
        L10n.string("When I can play", "Когда удобно играть") to L10n.string("I can play ", "Удобно играть "),
        L10n.string("Partner I'm looking for", "Какого партнёра ищу") to L10n.string("Looking for a partner ", "Ищу партнёра "),
        L10n.string("How long I've played", "Сколько играю") to L10n.string("I've been playing for ", "Играю уже "),
        L10n.string("I like doubles", "Люблю парные игры") to L10n.string("I like playing doubles.", "Люблю парные игры."),
        L10n.string("Happy to split the court", "Готов(а) делить корт") to L10n.string("Happy to split the court fee.", "Готов(а) делить стоимость корта."),
    )

    fun append(fragment: String) {
        val base = text.trim()
        text = (if (base.isEmpty()) fragment else "$base $fragment").take(PROFILE_BIO_MAX_LENGTH)
        focusRequester.requestFocus()
    }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.Black,
        shape = continuousShape(28.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp)
                .padding(bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    L10n.string("Cancel", "Отмена"),
                    style = AppText.subheadline,
                    color = Color.White.copy(alpha = 0.72f),
                    modifier = Modifier.clickable(onClick = onDismiss),
                )
                Spacer(Modifier.weight(1f))
                Text(L10n.string("About me", "О себе"), style = AppText.headline, color = Color.White)
                Spacer(Modifier.weight(1f))
                if (isSaving) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                } else {
                    Text(
                        L10n.string("Done", "Готово"),
                        style = AppText.subheadlineSemibold,
                        color = AppTheme.mint,
                        modifier = Modifier.clickable {
                            scope.launch {
                                isSaving = true
                                val didSave = onSave(text)
                                isSaving = false
                                if (didSave) onDismiss()
                            }
                        },
                    )
                }
            }

            OutlinedTextField(
                value = text,
                onValueChange = { text = it.take(PROFILE_BIO_MAX_LENGTH) },
                placeholder = {
                    Text(
                        L10n.string(
                            "I play on weekday evenings and look for a regular sparring partner.",
                            "Играю по вечерам в будни, ищу партнёра на регулярный спарринг.",
                        ),
                        style = AppText.subheadline,
                        color = Color.White.copy(alpha = 0.38f),
                    )
                },
                textStyle = AppText.subheadline.copy(color = Color.White),
                minLines = 5,
                maxLines = 10,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                shape = continuousShape(16.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.White.copy(alpha = 0.07f),
                    unfocusedContainerColor = Color.White.copy(alpha = 0.07f),
                    focusedIndicatorColor = AppTheme.court,
                    unfocusedIndicatorColor = Color.White.copy(alpha = 0.12f),
                    cursorColor = AppTheme.court,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 120.dp)
                    .focusRequester(focusRequester),
            )

            Row(modifier = Modifier.fillMaxWidth()) {
                Text(
                    L10n.string("Everyone who sees your profile can read this.", "Видят все, кому показывается ваш профиль."),
                    style = AppText.caption,
                    color = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.size(8.dp))
                Text(
                    "${text.length}/$PROFILE_BIO_MAX_LENGTH",
                    style = AppText.caption,
                    color = if (text.length >= PROFILE_BIO_MAX_LENGTH - 20) Color(0xFFFF9F0A) else Color.White.copy(alpha = 0.5f),
                )
            }

            Text(
                L10n.string("Hints — tap to add", "Подсказки — нажмите, чтобы добавить").uppercase(),
                style = AppText.captionBold,
                color = Color.White.copy(alpha = 0.52f),
                modifier = Modifier.padding(top = 8.dp),
            )

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                hints.forEach { (title, fragment) ->
                    Text(
                        title,
                        style = AppText.captionSemibold,
                        color = Color.White.copy(alpha = 0.86f),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = 0.08f))
                            .clickable { append(fragment) }
                            .padding(horizontal = 12.dp, vertical = 9.dp),
                    )
                }
            }
        }
    }
}
