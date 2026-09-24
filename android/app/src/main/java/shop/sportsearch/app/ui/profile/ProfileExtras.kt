package shop.sportsearch.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.*
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.AppAvailabilityWeekEditor
import shop.sportsearch.app.ui.components.AppSportSelectionGrid
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SectionCard
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct ProfileMapVisibilityControl` in UIComponents.swift. */
@Composable
fun ProfileMapVisibilityControl(
    isOn: Boolean,
    onChange: (Boolean) -> Unit,
    isDark: Boolean = false,
    isForNewProfile: Boolean = false,
    isOnboarding: Boolean = false,
) {
    var isInfoPresented by remember { mutableStateOf(false) }
    val title = L10n.string("My profile on the map", "Мой профиль на карте")

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(continuousShape(18.dp))
            .background((if (isDark) Color.White else AppTheme.court).copy(alpha = 0.08f))
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            style = AppText.subheadlineSemibold,
            color = if (isDark) Color.White else AppTheme.ink,
            modifier = Modifier.weight(1f),
        )

        Box(
            modifier = Modifier
                .size(44.dp)
                .clickable { isInfoPresented = true },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.Info,
                contentDescription = L10n.string(
                    "About profile visibility on the map",
                    "О показе профиля на карте",
                ),
                tint = if (isDark) Color.White else AppTheme.ink,
                modifier = Modifier.size(19.dp),
            )
        }

        MapVisibilitySwitch(isOn = isOn, onChange = onChange)
    }

    if (isInfoPresented) {
        var explanation = L10n.string(
            "You see players in the areas where they prefer to play, and your card appears in the areas you " +
                "choose. With no districts selected, you appear in all city districts, or at city level where " +
                "districts are unavailable. Your exact location is not shown. You can switch this off now or " +
                "later in profile settings.",
            "Ты видишь игроков в удобных им районах, а свою карточку показываешь в выбранных тобой. Если районы " +
                "не выбраны — во всех районах города, а где районов нет — на уровне города. Точная геопозиция " +
                "не показывается. Можно выключить сейчас или позже в настройках профиля.",
        )
        if (isOnboarding) {
            explanation += "\n\n" + L10n.string(
                "Map visibility is on by default for a new profile.",
                "Для новой анкеты показ на карте включён по умолчанию.",
            )
        }
        if (isForNewProfile) {
            explanation += "\n\n" + L10n.string(
                "Applies when creating a new profile. Signing in to an existing profile keeps its saved setting.",
                "Для новой анкеты. При входе в существующую анкету сохраняется её настройка.",
            )
        }

        AlertDialog(
            onDismissRequest = { isInfoPresented = false },
            containerColor = Color.White,
            title = { Text(title, color = AppTheme.ink) },
            text = { Text(explanation, color = AppTheme.ink.copy(alpha = 0.7f)) },
            confirmButton = {
                TextButton(onClick = { isInfoPresented = false }) {
                    Text(L10n.string("Got it", "Понятно"), color = AppTheme.court)
                }
            },
        )
    }
}

@Composable
private fun MapVisibilitySwitch(isOn: Boolean, onChange: (Boolean) -> Unit) {
    val haptics = rememberAppHaptics()
    Box(
        modifier = Modifier
            .size(width = 54.dp, height = 32.dp)
            .clip(continuousShape(18.dp))
            .background(if (isOn) AppTheme.court else AppTheme.cream)
            .clickable {
                haptics.selection()
                onChange(!isOn)
            },
        contentAlignment = if (isOn) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(Modifier.padding(horizontal = 4.dp).size(24.dp).clip(CircleShape).background(Color.White))
    }
}

/** `FieldShell` + `Slider` from the location editor. */
@Composable
fun RadiusSlider(value: Int, onChange: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            L10n.string("$value km", "$value км").uppercase(),
            style = AppText.captionSemibold,
            color = AppTheme.ink.copy(alpha = 0.68f),
        )
        Slider(
            value = value.toFloat(),
            onValueChange = { onChange(it.toInt().coerceIn(1, 100)) },
            valueRange = 1f..100f,
            steps = 98,
            colors = SliderDefaults.colors(
                thumbColor = AppTheme.court,
                activeTrackColor = AppTheme.court,
            ),
        )
    }
}

/**
 * Port of `basicsSection(for:)` plus the surrounding `profileEditor` sheet -
 * the pencil button on the media card opens this.
 */
@Composable
fun ProfileBasicsEditorScreen(
    appModel: AppViewModel,
    profile: UserProfile,
    onChange: (UserProfile) -> Unit,
    onBack: () -> Unit,
    onSave: suspend () -> Boolean,
) {
    DismissOnSystemBack(onBack)
    shop.sportsearch.app.ui.components.HideBottomBarWhileVisible(appModel)
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var isSaving by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .navigationBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 16.dp, bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ProfileSubscreenHeader(
            title = L10n.string("Edit profile", "Редактировать профиль"),
            onBack = onBack,
        )

        SectionCard(
            title = L10n.string("Player profile", "Карточка игрока"),
            subtitle = L10n.string(
                "Basic information visible to other players.",
                "Основные данные, которые видят другие игроки.",
            ),
        ) {
            DarkFieldLabel(L10n.string("Name", "Имя"))
            ProfileTextField(
                value = profile.name.orEmpty(),
                placeholder = L10n.string("Anna", "Анна"),
                onValueChange = { onChange(profile.copy(name = it.ifEmpty { null })) },
            )

            DarkFieldLabel(L10n.string("Age", "Возраст"))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                val age = profile.age ?: 25
                Text("$age", style = AppText.headline, color = AppTheme.ink, modifier = Modifier.weight(1f))
                AgeStepper(Icons.Filled.Remove, age > 18) { onChange(profile.copy(age = age - 1)) }
                AgeStepper(Icons.Filled.Add, age < 100) { onChange(profile.copy(age = age + 1)) }
            }

            DarkFieldLabel(L10n.string("Gender", "Пол"))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Gender.entries.forEach { gender ->
                    val selected = profile.gender == gender
                    Text(
                        gender.title,
                        style = AppText.captionSemibold,
                        color = if (selected) Color.White else AppTheme.ink,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (selected) AppTheme.court else AppTheme.cream)
                            .clickable { onChange(profile.copy(genderRaw = gender.wire)) }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                }
            }

            if (profileDistrictsEnabled(profile)) {
                DarkFieldLabel(L10n.string("District", "Район"))
                ProfileTextField(
                    value = profile.district.orEmpty(),
                    placeholder = L10n.string("For example: Central", "Например: Приморский"),
                    onValueChange = { onChange(profile.copy(district = it.ifEmpty { null })) },
                )
            }

            DarkFieldLabel(L10n.string("About me", "О себе"))
            ProfileTextField(
                value = profile.bio.orEmpty(),
                placeholder = L10n.string(
                    "I enjoy intense rallies and evening practice.",
                    "Люблю интенсивные розыгрыши и вечерние тренировки.",
                ),
                onValueChange = { onChange(profile.copy(bio = it.take(PROFILE_BIO_MAX_LENGTH).ifEmpty { null })) },
                minHeight = 96.dp,
            )

            ProfileMapVisibilityControl(
                isOn = profile.showOnMap,
                onChange = { onChange(profile.copy(showOnMap = it)) },
            )
            ToggleCard(
                title = L10n.string("Looking for a game now", "Ищу игру сейчас"),
                subtitle = L10n.string(
                    "Show you in active player recommendations.",
                    "Показывать тебя в активной подборке игроков.",
                ),
                isOn = profile.isLookingForGame,
                onToggle = { onChange(profile.copy(isLookingForGame = it)) },
            )
        }

        SectionCard(
            title = L10n.string("Sports", "Виды спорта"),
            subtitle = L10n.string("Choose a sport and set your level.", "Выбери спорт и сразу настрой уровень."),
        ) {
            AppSportSelectionGrid(
                title = L10n.string("Sports profile", "Спортивный профиль"),
                sports = Sport.entries,
                selectedSports = profile.preferredSports,
                levels = profile.sportLevels,
                onSelectedSportsChange = { onChange(profile.copy(preferredSports = it)) },
                onLevelsChange = { onChange(profile.copy(sportLevels = it)) },
            )
        }

        SectionCard(
            title = L10n.string("Availability", "Доступность"),
            subtitle = L10n.string("Days and times when you can play.", "Дни и окна времени, когда удобно играть."),
        ) {
            AppAvailabilityWeekEditor(
                availabilityByDay = profile.availabilityByDay,
                onChange = { onChange(profile.copy(availabilityByDay = it)) },
            )
        }

        PrimaryActionButton(
            title = L10n.string("Save profile", "Сохранить профиль"),
            tint = AppTheme.court,
            enabled = !isSaving,
            onClick = {
                scope.launch {
                    isSaving = true
                    if (onSave()) onBack()
                    isSaving = false
                }
            },
        )
    }
}

@Composable
private fun DarkFieldLabel(text: String) {
    Text(
        text.uppercase(),
        style = AppText.captionSemibold,
        color = AppTheme.ink.copy(alpha = 0.68f),
    )
}

@Composable
private fun AgeStepper(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(AppTheme.cream)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            null,
            tint = if (enabled) AppTheme.ink else AppTheme.ink.copy(alpha = 0.3f),
            modifier = Modifier.size(15.dp),
        )
    }
}

@Composable
private fun ProfileTextField(
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    minHeight: androidx.compose.ui.unit.Dp = 0.dp,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = AppTheme.ink.copy(alpha = 0.38f), style = AppText.subheadline) },
        textStyle = AppText.subheadline.copy(color = AppTheme.ink),
        shape = continuousShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = AppTheme.creamLight,
            unfocusedContainerColor = AppTheme.creamLight,
            focusedIndicatorColor = AppTheme.court.copy(alpha = 0.4f),
            unfocusedIndicatorColor = Color.Black.copy(alpha = 0.08f),
            cursorColor = AppTheme.court,
        ),
        modifier = Modifier.fillMaxWidth().let { if (minHeight > 0.dp) it.height(minHeight) else it },
    )
}

/** The guest branch of `ProfileView` - a draft you can prepare before verifying email. */
@Composable
fun GuestProfileContent(appModel: AppViewModel) {
    val draft = appModel.guestDraft

    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        ProfileDarkPanel {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                shop.sportsearch.app.ui.components.RemoteAvatarView(
                    name = draft.displayName,
                    path = null,
                    size = 74.dp,
                )
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(draft.displayName, style = AppText.title3Bold, color = Color.White)
                    Text(
                        L10n.string("Guest mode", "Гостевой режим"),
                        style = AppText.subheadline,
                        color = Color.White.copy(alpha = 0.58f),
                    )
                    ProfileCapsule(L10n.string("Profile draft", "Черновик профиля"), AppTheme.court)
                }
            }
        }

        SectionCard(
            title = L10n.string("Sports", "Виды спорта"),
            subtitle = L10n.string("Choose a sport and level.", "Выбери спорт и уровень."),
        ) {
            AppSportSelectionGrid(
                title = L10n.string("Sports profile", "Спортивный профиль"),
                sports = Sport.entries,
                selectedSports = draft.preferredSports,
                levels = draft.sportLevels,
                onSelectedSportsChange = { appModel.updateGuestDraft(draft.copy(preferredSports = it)) },
                onLevelsChange = { appModel.updateGuestDraft(draft.copy(sportLevels = it)) },
            )
        }

        SectionCard(
            title = L10n.string("Availability", "Доступность"),
            subtitle = L10n.string(
                "These time slots will be saved in your draft.",
                "Эти слоты сохранятся в черновике.",
            ),
        ) {
            AppAvailabilityWeekEditor(
                availabilityByDay = draft.availabilityByDay,
                onChange = { appModel.updateGuestDraft(draft.copy(availabilityByDay = it)) },
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(modifier = Modifier.weight(1f)) {
                SecondaryActionButton(
                    title = L10n.string("Save", "Сохранить"),
                    onClick = { appModel.updateGuestDraft(draft) },
                    tint = Color.White,
                )
            }
            Box(modifier = Modifier.weight(1f)) {
                PrimaryActionButton(
                    title = L10n.string("Continue to email", "К email"),
                    onClick = { appModel.presentAuth(AuthStep.EMAIL) },
                    tint = AppTheme.court,
                    enabled = draft.hasProfileBasics,
                )
            }
        }
    }
}
