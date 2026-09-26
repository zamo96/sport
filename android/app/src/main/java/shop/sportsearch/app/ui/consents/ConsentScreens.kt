package shop.sportsearch.app.ui.consents

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import shop.sportsearch.app.core.ConsentState
import shop.sportsearch.app.core.ConsentUpdate
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.LegalDocuments
import shop.sportsearch.app.core.RussianPhone
import shop.sportsearch.app.core.UserProfile
import shop.sportsearch.app.core.localizedDistrictName
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.HideBottomBarWhileVisible
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.rememberAppHaptics
import shop.sportsearch.app.ui.profile.ProfileDarkPanel
import shop.sportsearch.app.ui.profile.ProfileSubscreenHeader
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct ConsentScope`. The profile card itself is always shown once the person consents. */
private data class ConsentScope(
    val visibleToGuests: Boolean = true,
    val showsBio: Boolean = true,
    val showsPhotos: Boolean = true,
    val showsVideos: Boolean = true,
    val showsSearches: Boolean = true,
    val showOnMap: Boolean = true,
) {
    companion object {
        /**
         * Before an answer «Choose» offers to show everything: the button consents to what the
         * preview shows and the settings can only narrow it. After an answer it opens with the choice.
         */
        fun from(profile: UserProfile): ConsentScope {
            val consents = profile.consents
            if (consents == null || consents.profileVisibility != "visible") {
                return ConsentScope(showOnMap = profile.showOnMap)
            }
            return ConsentScope(
                visibleToGuests = consents.visibleToGuests,
                showsBio = consents.showsBio,
                showsPhotos = consents.showsPhotos,
                showsVideos = consents.showsVideos,
                showsSearches = consents.showsSearches,
                showOnMap = profile.showOnMap,
            )
        }
    }
}

/** Port of `enum ConsentNameValidator`: at least two words of letters, like the server. */
private object ConsentNameValidator {
    private val pattern = Regex("^\\p{L}[\\p{L}'’-]*(?:\\s+\\p{L}[\\p{L}'’-]*)+$")

    fun normalized(value: String): String? {
        val collapsed = value.trim().split(Regex("\\s+")).joinToString(" ")
        return if (pattern.matches(collapsed)) collapsed else null
    }
}

enum class ConsentReviewMode {
    /** After onboarding or on the first launch: cannot be closed without an answer. */
    REQUIRED,

    /** From profile settings: can be closed without changes. */
    SETTINGS,
}

private val errorColor = Color(0xFFD1493F)

private fun markdownLink(prefix: String, link: String, url: String, suffix: String = ""): AnnotatedString =
    buildAnnotatedString {
        val style = TextLinkStyles(SpanStyle(color = AppTheme.court, fontWeight = FontWeight.SemiBold, textDecoration = TextDecoration.Underline))
        append(prefix)
        withLink(LinkAnnotation.Url(url, style)) { append(link) }
        append(suffix)
    }

/**
 * Port of `struct ConsentReviewView`: consent to showing the profile (art. 10.1 of 152-FZ).
 * «Show my profile» is the consent itself. The new agreement version and analytics are
 * separate checkboxes and separate request fields.
 */
@Composable
fun ConsentReviewScreen(
    appModel: AppViewModel,
    profile: UserProfile,
    mode: ConsentReviewMode,
    onFinished: () -> Unit = {},
) {
    if (mode == ConsentReviewMode.SETTINGS) {
        DismissOnSystemBack(onFinished)
    } else {
        // Required: the system Back must not leave the screen without an answer.
        DismissOnSystemBack {}
    }
    HideBottomBarWhileVisible(appModel)

    val consents = profile.consents ?: ConsentState(profileVisibility = "pending")
    val isLegacy = consents.isLegacy
    val hidesAsSecondary = isLegacy || consents.profileVisibility == "visible"
    val haptics = rememberAppHaptics()
    val scope = rememberCoroutineScope()

    var consentScope by remember { mutableStateOf(ConsentScope.from(profile)) }
    var fullName by remember { mutableStateOf(consents.fullName.orEmpty()) }
    var analytics by remember { mutableStateOf(consents.analytics) }
    var termsAccepted by remember { mutableStateOf(false) }
    var isCustomizing by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var isSaving by remember { mutableStateOf(false) }

    fun submit(visible: Boolean) {
        errorText = null
        if (consents.termsUpdateRequired && !termsAccepted) {
            errorText = L10n.string("Accept the new version of the agreement to continue", "Примите новую редакцию соглашения, чтобы продолжить")
            haptics.warning()
            return
        }
        val profileChoice = if (visible) {
            val name = ConsentNameValidator.normalized(fullName)
            if (name == null) {
                errorText = L10n.string("Enter your surname and first name", "Укажите фамилию и имя")
                haptics.warning()
                return
            }
            ConsentUpdate.Profile(
                decision = "visible",
                fullName = name,
                visibleToGuests = consentScope.visibleToGuests,
                showsBio = consentScope.showsBio,
                showsPhotos = consentScope.showsPhotos,
                showsVideos = consentScope.showsVideos,
                showsSearches = consentScope.showsSearches,
                showOnMap = consentScope.showOnMap,
            )
        } else {
            ConsentUpdate.Profile(decision = "hidden")
        }
        val update = ConsentUpdate(
            acceptAgreementVersion = if (consents.termsUpdateRequired) LegalDocuments.USER_AGREEMENT_VERSION else null,
            profile = profileChoice,
            analytics = analytics,
        )
        isSaving = true
        scope.launch {
            val failure = appModel.submitConsents(update)
            isSaving = false
            if (failure != null) {
                errorText = failure
                haptics.warning()
            } else {
                haptics.success()
                onFinished()
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(AppTheme.pageBackground)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 22.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                if (isLegacy) L10n.string("We've updated our terms", "Мы обновили правила")
                else L10n.string("Show your profile?", "Показывать вашу анкету?"),
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
            )
            if (isLegacy) {
                Text(
                    L10n.string(
                        "Consent to showing your profile is now a separate decision. Right now other players can see your profile.",
                        "Согласие на показ анкеты теперь отдельное решение. Сейчас ваша анкета видна другим игрокам.",
                    ),
                    style = AppText.subheadline,
                    color = AppTheme.mutedInk,
                )
            }

            PreviewCard(profile)

            Text(
                if (consentScope.visibleToGuests) {
                    L10n.string(
                        "Players and guests will see you like this in search and on the map. The map shows a district point, not your location.",
                        "Так вас увидят игроки и гости в поиске и на карте. На карте — точка района, не ваше местоположение.",
                    )
                } else {
                    L10n.string(
                        "Signed-in players will see you like this in search and on the map. The map shows a district point, not your location.",
                        "Так вас увидят игроки, вошедшие в аккаунт, в поиске и на карте. На карте — точка района, не ваше местоположение.",
                    )
                },
                style = AppText.footnote,
                color = AppTheme.mutedInk,
            )

            Row(
                modifier = Modifier.clickable {
                    isCustomizing = !isCustomizing
                    haptics.selection()
                },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    L10n.string("Choose what is shown and to whom", "Настроить, что и кому видно"),
                    style = AppText.subheadlineSemibold.copy(textDecoration = TextDecoration.Underline),
                    color = AppTheme.court,
                )
                Icon(
                    if (isCustomizing) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = AppTheme.court,
                    modifier = Modifier.size(18.dp),
                )
            }

            AnimatedVisibility(visible = isCustomizing) {
                CustomizePanel(consentScope) { consentScope = it }
            }

            if (consents.termsUpdateRequired) {
                ConsentCheckbox(
                    checked = termsAccepted,
                    text = markdownLink(
                        L10n.string("I accept the new version of the ", "Принимаю новую редакцию "),
                        L10n.string("User Agreement", "пользовательского соглашения"),
                        LegalDocuments.userAgreementUrl,
                    ),
                ) {
                    termsAccepted = !termsAccepted
                    haptics.selection()
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(
                    value = fullName,
                    onValueChange = { fullName = it },
                    placeholder = { Text(L10n.string("Surname and first name", "Фамилия и имя")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                    shape = continuousShape(16.dp),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.White,
                        unfocusedContainerColor = Color.White,
                        focusedIndicatorColor = AppTheme.court.copy(alpha = 0.7f),
                        unfocusedIndicatorColor = Color(0xFFD1D1D6),
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
                // The first name comes from the profile; only the surname is left to add.
                val needsSurname = fullName.trim().split(Regex("\\s+")).count { it.isNotEmpty() } == 1
                Text(
                    if (needsSurname) {
                        L10n.string(
                            "Add your surname — your first name is taken from your profile. Not shown on your profile.",
                            "Добавьте фамилию — имя уже взяли из анкеты. В анкете её не покажем.",
                        )
                    } else {
                        L10n.string("Needed for the consent. Not shown on your profile.", "Нужны для согласия. В анкете не показываем.")
                    },
                    style = AppText.caption,
                    color = AppTheme.mutedInk,
                )
            }

            ConsentCheckbox(
                checked = analytics,
                text = markdownLink(
                    L10n.string("Allow usage analytics (", "Разрешить аналитику использования ("),
                    L10n.string("details", "подробнее"),
                    LegalDocuments.analyticsConsentUrl,
                    ")",
                ),
            ) {
                analytics = !analytics
                haptics.selection()
            }

            errorText?.let {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Warning, contentDescription = null, tint = errorColor, modifier = Modifier.size(16.dp))
                    Text(it, style = AppText.footnote.copy(fontWeight = FontWeight.Medium), color = errorColor)
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 4.dp)) {
                PrimaryActionButton(
                    title = when {
                        isSaving -> L10n.string("Saving…", "Сохраняем…")
                        isLegacy -> L10n.string("Keep my profile visible", "Оставить анкету видимой")
                        else -> L10n.string("Show my profile", "Показывать анкету")
                    },
                    onClick = { submit(visible = true) },
                    tint = AppTheme.ink,
                    enabled = !isSaving,
                )
                SecondaryActionButton(
                    title = if (hidesAsSecondary) L10n.string("Hide my profile", "Скрыть анкету")
                    else L10n.string("Not now", "Пока не показывать"),
                    onClick = { submit(visible = false) },
                    tint = AppTheme.ink,
                    enabled = !isSaving,
                )
                if (mode == ConsentReviewMode.SETTINGS) {
                    Text(
                        L10n.string("Cancel", "Отмена"),
                        style = AppText.subheadlineSemibold,
                        color = AppTheme.mutedInk,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().clickable(onClick = onFinished).padding(top = 2.dp),
                    )
                }
                Text(
                    markdownLink(
                        L10n.string("This button is your ", "Кнопка — это "),
                        L10n.string("consent to showing your profile", "согласие на показ"),
                        LegalDocuments.profileVisibilityConsentUrl,
                    ),
                    style = AppText.footnote,
                    color = AppTheme.mutedInk,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun PreviewCard(profile: UserProfile) {
    val name = profile.name?.trim().orEmpty()
    val title = listOfNotNull(name.ifEmpty { null }, profile.age?.toString()).joinToString(", ")
    val sports = profile.preferredSports.joinToString(", ") { sport ->
        profile.sportLevels[sport.wire]?.let { "${sport.title} $it" } ?: sport.title
    }
    val place = listOfNotNull(profile.city, localizedDistrictName(profile.district)).joinToString(" · ")
    val shape = continuousShape(20.dp)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.86f))
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(46.dp).clip(CircleShape).background(AppTheme.court.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(name.take(1).uppercase(), style = AppText.headlineBold, color = AppTheme.court)
        }
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = AppText.headline, color = AppTheme.ink)
            Text(
                listOf(sports, place).filter { it.isNotEmpty() }.joinToString(" · "),
                style = AppText.footnote,
                color = AppTheme.mutedInk,
                maxLines = 2,
            )
        }
    }
}

@Composable
private fun CustomizePanel(scope: ConsentScope, onChange: (ConsentScope) -> Unit) {
    val shape = continuousShape(18.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.7f))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            L10n.string("Switch off anything you don't want to show.", "Выключите то, что не хотите показывать."),
            style = AppText.footnote,
            color = AppTheme.mutedInk,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(L10n.string("Profile card", "Анкета"), style = AppText.subheadlineSemibold, color = AppTheme.ink)
                Text(
                    L10n.string("name, age, city, districts, sport and level, schedule, format", "имя, возраст, город, районы, спорт и уровень, расписание, формат"),
                    style = AppText.caption,
                    color = AppTheme.mutedInk,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = AppTheme.mutedInk, modifier = Modifier.size(13.dp))
                Text(L10n.string("Always", "Всегда"), style = AppText.caption, color = AppTheme.mutedInk)
            }
        }
        ScopeToggle(L10n.string("Description", "Описание"), scope.showsBio) { onChange(scope.copy(showsBio = it)) }
        ScopeToggle(L10n.string("Photos", "Фото"), scope.showsPhotos) { onChange(scope.copy(showsPhotos = it)) }
        ScopeToggle(L10n.string("Videos", "Видео"), scope.showsVideos) { onChange(scope.copy(showsVideos = it)) }
        ScopeToggle(L10n.string("District point on the map", "Точка района на карте"), scope.showOnMap) { onChange(scope.copy(showOnMap = it)) }
        ScopeToggle(L10n.string("My game searches", "Мои игровые поиски"), scope.showsSearches) { onChange(scope.copy(showsSearches = it)) }
        ScopeToggle(L10n.string("Guests without an account", "Гостям без входа"), scope.visibleToGuests) { onChange(scope.copy(visibleToGuests = it)) }
    }
}

@Composable
private fun ScopeToggle(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = AppText.subheadline, color = AppTheme.ink, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(checkedTrackColor = AppTheme.court),
        )
    }
}

@Composable
private fun ConsentCheckbox(checked: Boolean, text: AnnotatedString, onToggle: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Icon(
            imageVector = if (checked) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank,
            contentDescription = null,
            tint = if (checked) AppTheme.court else AppTheme.ink.copy(alpha = 0.45f),
            modifier = Modifier.size(24.dp).clickable(onClick = onToggle),
        )
        Text(text, style = AppText.subheadline, color = AppTheme.ink.copy(alpha = 0.8f))
    }
}

/** Status line shared by the profile menu row and the settings screen. */
fun consentStatusText(consents: ConsentState?): String = when (consents?.profileVisibility) {
    null -> L10n.string("Visible to other players", "Анкета видна другим игрокам")
    "visible" -> if (consents.visibleToGuests) {
        L10n.string("Visible to players and guests", "Анкету видят игроки и гости")
    } else {
        L10n.string("Visible to signed-in players", "Анкету видят игроки, вошедшие в аккаунт")
    }
    "legacy" -> L10n.string("Visible as before. Confirm your choice", "Видна как раньше. Подтвердите выбор")
    else -> L10n.string("Hidden from search and the map", "Скрыта из поиска и с карты")
}

/**
 * Port of `ConsentSettingsScreen`. All state lives on the server: the old «limited profile»
 * mode was stored only on the device and hid nothing.
 */
@Composable
fun ConsentSettingsScreen(appModel: AppViewModel, onBack: () -> Unit) {
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val haptics = rememberAppHaptics()
    var isEditing by remember { mutableStateOf(false) }
    var isSavingAnalytics by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    val profile = appModel.currentUser

    if (isEditing && profile != null) {
        ConsentReviewScreen(appModel, profile, ConsentReviewMode.SETTINGS) { isEditing = false }
        return
    }

    DismissOnSystemBack(onBack)
    HideBottomBarWhileVisible(appModel)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp)
            .padding(top = 16.dp, bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        ProfileSubscreenHeader(title = L10n.string("Visibility and consents", "Видимость и согласия"), onBack = onBack)

        ProfileDarkPanel {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(consentStatusText(profile?.consents), style = AppText.title3Semibold, color = Color.White)
                PrimaryActionButton(
                    title = L10n.string("Change", "Изменить"),
                    onClick = {
                        haptics.selection()
                        isEditing = true
                    },
                    tint = AppTheme.court,
                )
            }
        }

        ProfileDarkPanel {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        L10n.string("Usage analytics", "Аналитика использования"),
                        style = AppText.headline,
                        color = Color.White,
                        modifier = Modifier.weight(1f),
                    )
                    Switch(
                        checked = profile?.consents?.analytics == true,
                        enabled = !isSavingAnalytics,
                        onCheckedChange = { value ->
                            isSavingAnalytics = true
                            errorText = null
                            scope.launch {
                                errorText = appModel.submitConsents(ConsentUpdate(analytics = value))
                                isSavingAnalytics = false
                            }
                        },
                        colors = SwitchDefaults.colors(checkedTrackColor = Color(0xFF34C759)),
                    )
                }
                Text(
                    L10n.string(
                        "Which screens you open and what you tap. No messages, photos, or videos. Kept up to 90 days.",
                        "Какие экраны открываете и что нажимаете. Без переписки, фото и видео. Хранится до 90 дней.",
                    ),
                    style = AppText.footnote,
                    color = Color.White.copy(alpha = 0.62f),
                )
            }
        }

        errorText?.let {
            Text(it, style = AppText.footnote.copy(fontWeight = FontWeight.Medium), color = errorColor)
        }

        ProfileDarkPanel {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L10n.string("Documents", "Документы"), style = AppText.headline, color = Color.White)
                listOf(
                    L10n.string("Consent to showing your profile", "Согласие на показ анкеты") to LegalDocuments.profileVisibilityConsentUrl,
                    L10n.string("Consent to analytics", "Согласие на аналитику") to LegalDocuments.analyticsConsentUrl,
                    L10n.string("User Agreement", "Пользовательское соглашение") to LegalDocuments.userAgreementUrl,
                    L10n.string("Privacy Policy", "Политика конфиденциальности") to LegalDocuments.privacyPolicyUrl,
                ).forEach { (title, url) ->
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable { uriHandler.openUri(url) },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(title, style = AppText.subheadline, color = Color.White.copy(alpha = 0.86f), modifier = Modifier.weight(1f))
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = Color.White.copy(alpha = 0.86f), modifier = Modifier.size(16.dp))
                    }
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Info, contentDescription = null, tint = Color.White.copy(alpha = 0.62f), modifier = Modifier.size(15.dp))
            Text(L10n.string("Changes take effect immediately.", "Изменения действуют сразу."), style = AppText.footnote, color = Color.White.copy(alpha = 0.62f))
        }
        Spacer(Modifier.size(1.dp))
    }
}

/**
 * Port of `struct PhoneLinkView`: links a phone number to the signed-in account.
 * Sign-in in Russia now goes through a phone or VK ID, so without a number the
 * person cannot get back into this account after signing out.
 */
@Composable
fun PhoneLinkScreen(appModel: AppViewModel, isPrompt: Boolean, onFinished: () -> Unit) {
    DismissOnSystemBack(onFinished)
    HideBottomBarWhileVisible(appModel)
    val haptics = rememberAppHaptics()
    val scope = rememberCoroutineScope()
    var phone by remember { mutableStateOf("+7 ") }
    var code by remember { mutableStateOf("") }
    var isCodeSent by remember { mutableStateOf(false) }
    var debugCode by remember { mutableStateOf<String?>(null) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    val displayedPhone = RussianPhone.normalized(phone)?.let(RussianPhone::formatted) ?: phone

    fun submit() {
        errorText = null
        isSaving = true
        scope.launch {
            if (isCodeSent) {
                val failure = appModel.verifyPhoneLink(phone, code.filter(Char::isDigit))
                isSaving = false
                if (failure != null) {
                    errorText = failure
                    haptics.warning()
                } else {
                    haptics.success()
                    onFinished()
                }
            } else {
                val (debug, failure) = appModel.requestPhoneLinkCode(phone)
                isSaving = false
                if (failure != null) {
                    errorText = failure
                    haptics.warning()
                } else {
                    debugCode = debug
                    isCodeSent = true
                }
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(AppTheme.pageBackground)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 22.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(L10n.string("Add your phone number", "Добавьте номер телефона"), fontSize = 28.sp, fontWeight = FontWeight.Bold, color = AppTheme.ink)
            Text(
                L10n.string(
                    "In Russia you now sign in with a phone number or VK ID. Add your number to keep signing in to this account.",
                    "В России вход теперь по номеру телефона или через VK ID. Привяжите номер, чтобы и дальше входить в этот аккаунт.",
                ),
                style = AppText.subheadline,
                color = AppTheme.mutedInk,
            )

            PhoneLinkField(
                value = phone,
                onValueChange = { value -> phone = value.filter { it.isDigit() || it in "+()- " }.take(20) },
                placeholder = "+7 999 123-45-67",
                keyboardType = KeyboardType.Phone,
                enabled = !isCodeSent,
            )

            if (isCodeSent) {
                Text(
                    L10n.string("SMS code sent to $displayedPhone", "Код отправлен по SMS на $displayedPhone"),
                    style = AppText.footnote,
                    color = AppTheme.mutedInk,
                )
                debugCode?.let { Text("Debug OTP: $it", style = AppText.footnote, color = Color(0xFFFF9500)) }
                PhoneLinkField(
                    value = code,
                    onValueChange = { value -> code = value.filter(Char::isDigit).take(6) },
                    placeholder = "000000",
                    keyboardType = KeyboardType.NumberPassword,
                    enabled = true,
                )
            }

            errorText?.let {
                Text(it, style = AppText.footnote.copy(fontWeight = FontWeight.Medium), color = errorColor)
            }

            PrimaryActionButton(
                title = when {
                    isSaving -> L10n.string("Saving…", "Сохраняем…")
                    isCodeSent -> L10n.string("Confirm", "Подтвердить")
                    else -> L10n.string("Get an SMS code", "Получить код по SMS")
                },
                onClick = ::submit,
                tint = AppTheme.ink,
                enabled = !isSaving && (!isCodeSent || code.length == 6),
            )

            if (isCodeSent) {
                SecondaryActionButton(
                    title = L10n.string("Change number", "Изменить номер"),
                    onClick = {
                        isCodeSent = false
                        code = ""
                        errorText = null
                    },
                    tint = AppTheme.ink,
                )
            }

            Text(
                if (isPrompt) L10n.string("Later", "Позже") else L10n.string("Cancel", "Отмена"),
                style = AppText.subheadlineSemibold,
                color = AppTheme.mutedInk,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clickable(onClick = onFinished).padding(top = 2.dp),
            )
        }
    }
}

@Composable
private fun PhoneLinkField(value: String, onValueChange: (String) -> Unit, placeholder: String, keyboardType: KeyboardType, enabled: Boolean) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, fontSize = 20.sp) },
        singleLine = true,
        enabled = enabled,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        shape = continuousShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.White,
            unfocusedContainerColor = Color.White,
            disabledContainerColor = Color.White,
            focusedIndicatorColor = AppTheme.court.copy(alpha = 0.7f),
            unfocusedIndicatorColor = Color(0xFFD1D1D6),
        ),
        modifier = Modifier.fillMaxWidth(),
    )
}
