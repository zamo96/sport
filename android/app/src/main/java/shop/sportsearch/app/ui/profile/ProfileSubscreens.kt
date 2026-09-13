package shop.sportsearch.app.ui.profile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppAvailabilityWeekEditor
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct ProfileEditorScreen`. */
@Composable
fun ProfileEditorScreen(
    appModel: AppViewModel,
    title: String,
    subtitle: String,
    icon: ImageVector,
    tint: Color,
    onBack: () -> Unit,
    onSave: suspend () -> Boolean,
    content: @Composable ColumnScope.() -> Unit,
) {
    DismissOnSystemBack(onBack)
    HideBottomBarWhileVisible(appModel)
    val scope = rememberCoroutineScope()
    var isSaving by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 16.dp, bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        ProfileSubscreenHeader(title = title, onBack = onBack)
        ProfileEditorHero(title = title, subtitle = subtitle, icon = icon, tint = tint)

        content()

        Box(modifier = Modifier.padding(top = 2.dp)) {
            PrimaryActionButton(
                title = L10n.string("Save", "Сохранить"),
                tint = AppTheme.court,
                enabled = !isSaving,
                onClick = {
                    if (isSaving) return@PrimaryActionButton
                    scope.launch {
                        isSaving = true
                        val shouldDismiss = onSave()
                        isSaving = false
                        if (shouldDismiss) onBack()
                    }
                },
            )
            if (isSaving) {
                Box(Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

/** Port of `struct ProfileLanguageSettingsScreen`. */
@Composable
fun ProfileLanguageSettingsScreen(appModel: AppViewModel, onBack: () -> Unit) {
    HideBottomBarWhileVisible(appModel)
    val haptics = rememberAppHaptics()
    val isRussian = appModel.localeStore.effectiveLocale == AppLocale.RU

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        ProfileSubscreenHeader(title = "Language / Язык", onBack = onBack)

        Text(
            if (isRussian) {
                "Язык интерфейса можно выбрать независимо от страны и города."
            } else {
                "You can choose the interface language independently of your country and city."
            },
            style = AppText.subheadline,
            color = Color.White.copy(alpha = 0.62f),
        )

        ProfileDarkPanel {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                AppLocale.entries.forEach { locale ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp)
                            .clip(continuousShape(16.dp))
                            .background(Color.White.copy(alpha = 0.07f))
                            .clickable {
                                appModel.setManualLocale(locale)
                                haptics.selection()
                            }
                            .padding(horizontal = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(locale.displayName, style = AppText.headlineBold, color = Color.White)
                        Spacer(Modifier.weight(1f))
                        if (appModel.localeStore.effectiveLocale == locale) {
                            Icon(
                                Icons.Filled.CheckCircle,
                                null,
                                tint = AppTheme.court,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Port of `struct ProfileAccountScreen`. */
@Composable
fun ProfileAccountScreen(
    appModel: AppViewModel,
    email: String?,
    isVerified: Boolean,
    onBack: () -> Unit,
    onLogout: () -> Unit,
    onDelete: () -> Unit,
) {
    DismissOnSystemBack(onBack)
    HideBottomBarWhileVisible(appModel)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        ProfileSubscreenHeader(title = L10n.string("Account", "Аккаунт"), onBack = onBack)

        ProfileDarkPanel {
            ProfileInfoLine(
                L10n.string("Email", "Почта"),
                email ?: L10n.string("Not provided", "Не указана"),
            )
            ProfileInfoLine(
                L10n.string("Status", "Статус"),
                if (isVerified) L10n.string("Verified", "Подтверждён") else L10n.string("Not verified", "Не подтверждён"),
            )
        }

        SecondaryActionButton(title = L10n.string("Sign out", "Выйти"), onClick = onLogout, tint = Color.White)
        SecondaryActionButton(title = L10n.string("Delete profile", "Удалить профиль"), onClick = onDelete, tint = Color.Red)
    }
}

/** Port of `struct VisibilitySettingsView`. */
@Composable
fun VisibilitySettingsView(
    appModel: AppViewModel,
    selection: ProfileVisibilityMode,
    onSelect: (ProfileVisibilityMode) -> Unit,
    onBack: () -> Unit,
) {
    DismissOnSystemBack(onBack)
    HideBottomBarWhileVisible(appModel)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp)
            .padding(top = 16.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ProfileSubscreenHeader(
            title = L10n.string("Visibility settings", "Настройки видимости"),
            onBack = onBack,
        )

        Text(
            L10n.string(
                "Choose what is visible in your public profile",
                "Выбери, что будет видно в твоём публичном профиле",
            ),
            style = AppText.title3,
            color = Color.White.copy(alpha = 0.72f),
        )

        ProfileVisibilityMode.entries.forEach { mode ->
            VisibilityOptionCard(mode = mode, isSelected = selection == mode) { onSelect(mode) }
        }

        ProfileDarkPanel {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Info, null, tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(15.dp))
                Text(
                    L10n.string(
                        "You can change visibility settings at any time.",
                        "В любой момент можно изменить настройки видимости.",
                    ),
                    style = AppText.footnote,
                    color = Color.White.copy(alpha = 0.72f),
                )
            }
        }
    }
}

@Composable
private fun VisibilityOptionCard(mode: ProfileVisibilityMode, isSelected: Boolean, onSelect: () -> Unit) {
    val haptics = rememberAppHaptics()
    val accent = Color(0xFF4CAF50)

    ProfileDarkPanel(
        modifier = Modifier.clickable {
            haptics.selection()
            onSelect()
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    mode.title,
                    style = AppText.title3Semibold,
                    color = if (isSelected) accent else Color.White,
                )
                Spacer(Modifier.weight(1f))
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .border(2.dp, if (isSelected) accent else Color.White.copy(alpha = 0.38f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    if (isSelected) {
                        Box(Modifier.size(12.dp).clip(CircleShape).background(accent))
                    }
                }
            }

            Text(mode.description, style = AppText.subheadline, color = Color.White.copy(alpha = 0.7f))
        }
    }
}

/** Port of `struct QRProfileView`. */
@Composable
fun QRProfileView(
    appModel: AppViewModel,
    profile: UserProfile,
    visibilityMode: ProfileVisibilityMode,
    onBack: () -> Unit,
    onOpenVisibility: () -> Unit,
) {
    DismissOnSystemBack(onBack)
    HideBottomBarWhileVisible(appModel)
    val androidContext = LocalContext.current
    val haptics = rememberAppHaptics()
    var toast by remember { mutableStateOf<String?>(null) }
    val profileUrl = AppConfig.profileUrl(profile.id)

    LaunchedEffect(toast) {
        if (toast != null) {
            delay(1800)
            toast = null
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = 18.dp)
                .padding(top = 16.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            ProfileSubscreenHeader(title = L10n.string("QR profile", "QR-профиль"), onBack = onBack)

            ProfileDarkPanel {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    Text(
                        L10n.string(
                            "Show this code to share your profile",
                            "Покажи этот код, чтобы поделиться своим профилем",
                        ),
                        style = AppText.title3,
                        color = Color.White.copy(alpha = 0.7f),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )

                    Box(
                        modifier = Modifier
                            .size(246.dp)
                            .clip(continuousShape(18.dp))
                            .background(Color.White),
                        contentAlignment = Alignment.Center,
                    ) {
                        QRCodeImage(text = profileUrl, modifier = Modifier.fillMaxSize().padding(18.dp))
                        Box(
                            modifier = Modifier
                                .clip(continuousShape(18.dp))
                                .background(Color(red = 0.09f, green = 0.1f, blue = 0.1f))
                                .padding(16.dp),
                        ) {
                            Icon(Icons.Filled.Map, null, tint = AppTheme.court, modifier = Modifier.size(34.dp))
                        }
                    }

                    ProfileSmallPublicCard(profile)

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Filled.CheckCircle,
                            null,
                            tint = Color.White.copy(alpha = 0.7f),
                            modifier = Modifier.size(15.dp),
                        )
                        Text(
                            L10n.string(
                                "The QR code opens only your public profile. Personal data is not shown.",
                                "По QR откроется только публичная карточка. Личные данные не показываются.",
                            ),
                            style = AppText.footnote,
                            color = Color.White.copy(alpha = 0.7f),
                        )
                    }
                }
            }

            ProfileMenuGroup {
                ProfileActionRow(Icons.Filled.Link, L10n.string("Share link", "Поделиться ссылкой")) {
                    val clipboard = androidContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("profile", profileUrl))
                    haptics.success()
                    toast = L10n.string("Link copied", "Ссылка скопирована")
                }

                ProfileActionRow(Icons.Filled.Save, L10n.string("Save QR", "Сохранить QR")) {
                    haptics.selection()
                    toast = L10n.string("QR is ready to save", "QR готов к сохранению")
                }

                ProfileActionRow(Icons.Filled.Share, L10n.string("Share", "Поделиться")) {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, profileUrl)
                    }
                    runCatching { androidContext.startActivity(Intent.createChooser(intent, null)) }
                }

                ProfileMenuRow(
                    Icons.Filled.Visibility,
                    Color.White.copy(alpha = 0.72f),
                    L10n.string("Visibility settings", "Настроить видимость"),
                    visibilityMode.title,
                    onClick = onOpenVisibility,
                )
            }
        }

        toast?.let { message ->
            Box(modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 12.dp)) {
                InlineStatusToast(message)
            }
        }
    }
}

/**
 * Port of `struct QRCodeImage`. iOS uses CoreImage's `CIQRCodeGenerator` with
 * correction level M; ZXing is the equivalent on Android.
 */
@Composable
fun QRCodeImage(text: String, modifier: Modifier = Modifier) {
    val bitmap = remember(text) {
        runCatching {
            val size = 512
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
                EncodeHintType.MARGIN to 0,
            )
            val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints)
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).apply {
                for (x in 0 until size) {
                    for (y in 0 until size) {
                        setPixel(x, y, if (matrix[x, y]) AndroidColor.BLACK else AndroidColor.WHITE)
                    }
                }
            }
        }.getOrNull()
    }

    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = modifier,
        )
    }
}

/** Port of `struct ProfileAvailabilityDarkSummary`. */
@Composable
fun ProfileAvailabilityDarkSummary(availabilityByDay: Map<String, List<String>>) {
    val shape = continuousShape(22.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.055f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CheckCircle, null, tint = Color.White, modifier = Modifier.size(16.dp))
            Text(
                L10n.string("Schedule summary", "Итог расписания"),
                style = AppText.headlineBold,
                color = Color.White,
            )
        }

        if (availabilityByDay.isEmpty()) {
            Text(
                L10n.string(
                    "Availability is not set yet. Recommendations will rely less on your schedule.",
                    "Доступность пока не указана. Подбор будет меньше учитывать расписание.",
                ),
                style = AppText.subheadline,
                color = Color.White.copy(alpha = 0.58f),
            )
        } else {
            DayOfWeek.entries.chunked(2).forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEach { day ->
                        val ranges = availabilityByDay[day.wire].orEmpty()
                        if (ranges.isNotEmpty()) {
                            ProfileCapsule(
                                text = "${day.shortTitle} · " +
                                    ranges.mapNotNull { TimeRange.from(it)?.title }.joinToString(", "),
                                tint = AppTheme.court,
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Port of `struct ProfileDistrictPickerCard`. */
@Composable
fun ProfileDistrictPickerCard(
    selectedDistricts: List<String>,
    districts: List<String>,
    onChange: (selected: List<String>, primary: String?) -> Unit,
) {
    val haptics = rememberAppHaptics()

    ProfileEmbeddedLightCard(
        title = L10n.string("Preferred districts", "Предпочтительные районы"),
        subtitle = L10n.string(
            "The first selected district becomes your primary district.",
            "Первый выбранный район станет основным для профиля.",
        ),
    ) {
        districts.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { district ->
                    val isSelected = selectedDistricts.contains(district)
                    val shape = continuousShape(16.dp)
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .clip(shape)
                            .background(if (isSelected) AppTheme.court else AppTheme.cream)
                            .border(
                                1.dp,
                                if (isSelected) AppTheme.court.copy(alpha = 0.42f) else Color.White.copy(alpha = 0.72f),
                                shape,
                            )
                            .clickable {
                                haptics.selection()
                                val next = if (isSelected) {
                                    selectedDistricts.filterNot { it == district }
                                } else {
                                    selectedDistricts + district
                                }
                                onChange(next, next.firstOrNull())
                            }
                            .padding(10.dp),
                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.ChevronRight,
                            null,
                            tint = if (isSelected) Color.White else AppTheme.ink,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            localizedDistrictName(district) ?: district,
                            style = AppText.captionBold,
                            color = if (isSelected) Color.White else AppTheme.ink,
                            maxLines = 1,
                        )
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }

        if (selectedDistricts.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(continuousShape(14.dp))
                    .background(AppTheme.cream)
                    .clickable {
                        haptics.selection()
                        onChange(emptyList(), null)
                    }
                    .padding(vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Close, null, tint = AppTheme.ink, modifier = Modifier.size(15.dp))
                Text(
                    L10n.string("Clear districts", "Сбросить районы"),
                    style = AppText.subheadlineSemibold,
                    color = AppTheme.ink,
                )
            }
        }
    }
}
