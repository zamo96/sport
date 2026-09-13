package shop.sportsearch.app.ui.searches

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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import shop.sportsearch.app.core.AddressSuggestion
import shop.sportsearch.app.core.Court
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.Sport
import shop.sportsearch.app.core.venueTitle
import shop.sportsearch.app.data.TennisRepository
import shop.sportsearch.app.ui.components.AutoSizeText
import shop.sportsearch.app.ui.components.DismissOnSystemBack
import shop.sportsearch.app.ui.components.PrimaryActionButton
import shop.sportsearch.app.ui.components.SecondaryActionButton
import shop.sportsearch.app.ui.components.SportIconView
import shop.sportsearch.app.ui.maps.ClubsMapView
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Shared close-button header used by the composer, the club picker and the lobby. */
@Composable
fun SheetHeader(
    title: String,
    onClose: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.04f))
                .clickable(onClick = onClose),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Close, contentDescription = null, tint = AppTheme.ink, modifier = Modifier.size(18.dp))
        }

        Text(
            title,
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
            color = AppTheme.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f),
        )

        // `ToolbarItem(placement: .confirmationAction)`, or the balancing gap.
        if (trailing != null) trailing() else Spacer(Modifier.size(44.dp))
    }
}

/** Port of `SearchClubPickerSheet`, list mode. */
@Composable
fun SearchClubPickerSheet(
    sport: Sport,
    courts: List<Court>,
    selectedCourtId: String?,
    onSelect: (Court?) -> Unit,
    onDismiss: () -> Unit,
    selectsImmediately: Boolean = true,
    allowsNoCourt: Boolean = true,
    /**
     * `onSelectCustomAddress` - when the club is not in the list, the typed
     * address becomes the search's venue. Absent, the address block is hidden,
     * exactly as the optional closure does on iOS.
     */
    repository: TennisRepository? = null,
    suggestionCity: String? = null,
    onSelectCustomAddress: ((String) -> Unit)? = null,
) {
    DismissOnSystemBack(onDismiss)
    var query by remember { mutableStateOf("") }
    var addressSuggestions by remember { mutableStateOf<List<AddressSuggestion>>(emptyList()) }
    var isLoadingAddressSuggestions by remember { mutableStateOf(false) }
    val normalizedQuery = query.trim()
    val canSuggestAddresses = repository != null && onSelectCustomAddress != null

    // `scheduleAddressSuggestions(for:)` - 320 ms debounce, three characters minimum.
    LaunchedEffect(normalizedQuery, canSuggestAddresses) {
        addressSuggestions = emptyList()
        if (!canSuggestAddresses || normalizedQuery.length < 3) {
            isLoadingAddressSuggestions = false
            return@LaunchedEffect
        }
        delay(320)
        isLoadingAddressSuggestions = true
        addressSuggestions = runCatching {
            repository!!.fetchAddressSuggestions(normalizedQuery, suggestionCity)
        }.getOrDefault(emptyList())
        isLoadingAddressSuggestions = false
    }
    // `selectsImmediately: false` on iOS turns a tap into a pre-selection that
    // the footer button confirms, so the sheet stays open while you compare.
    var pendingSelectionId by remember(selectedCourtId) { mutableStateOf(selectedCourtId) }
    val effectiveSelectionId = if (selectsImmediately) selectedCourtId else pendingSelectionId

    fun commit(court: Court?) {
        if (selectsImmediately) {
            onSelect(court)
            onDismiss()
        } else {
            pendingSelectionId = court?.id
        }
    }
    val filtered = courts.filter {
        query.isBlank() ||
            it.name.contains(query, ignoreCase = true) ||
            it.address.contains(query, ignoreCase = true) ||
            it.metroNames.any { metro -> metro.contains(query, ignoreCase = true) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
            .padding(horizontal = 18.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        SheetHeader(
            title = L10n.string("${sport.venueTitle} for the game", "${sport.venueTitle} для игры"),
            onClose = onDismiss,
        )

        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = {
                Text(
                    L10n.string("Club, address or metro", "Клуб, адрес или метро"),
                    color = AppTheme.ink.copy(alpha = 0.4f),
                )
            },
            singleLine = true,
            shape = continuousShape(20.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = AppTheme.creamLight,
                unfocusedContainerColor = AppTheme.creamLight,
                focusedTextColor = AppTheme.ink,
                unfocusedTextColor = AppTheme.ink,
                cursorColor = AppTheme.court,
                focusedIndicatorColor = AppTheme.court.copy(alpha = 0.5f),
                unfocusedIndicatorColor = Color.Black.copy(alpha = 0.08f),
            ),
            modifier = Modifier.fillMaxWidth(),
        )

        if (normalizedQuery.isNotEmpty() && onSelectCustomAddress != null) {
            AddressSuggestionsSection(
                isLoading = isLoadingAddressSuggestions,
                suggestions = addressSuggestions,
                canSuggest = canSuggestAddresses,
            ) { suggestion ->
                onSelectCustomAddress(suggestion.address.ifEmpty { suggestion.title })
                onDismiss()
            }

            if (normalizedQuery.length >= 3 && !isLoadingAddressSuggestions && addressSuggestions.isEmpty()) {
                MissingClubAddressHint(normalizedQuery) { address ->
                    onSelectCustomAddress(address)
                    onDismiss()
                }
            }
        }

        // `SearchClubPickerSheet` shows the clubs on a map above the list.
        if (filtered.any { it.locationLat != 0.0 || it.locationLng != 0.0 }) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(190.dp)
                    .clip(continuousShape(22.dp))
                    .border(1.dp, Color.Black.copy(alpha = 0.06f), continuousShape(22.dp)),
            ) {
                ClubsMapView(
                    courts = filtered,
                    focusedCourtId = effectiveSelectionId,
                    modifier = Modifier.fillMaxSize(),
                    onSelectCourt = { id -> filtered.firstOrNull { it.id == id }?.let(::commit) },
                )
            }
        }

        if (allowsNoCourt) {
            SecondaryActionButton(
                title = L10n.string("Without a club", "Без клуба"),
                onClick = { commit(null) },
            )
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            filtered.forEach { court ->
                val isSelected = court.id == effectiveSelectionId
                val shape = continuousShape(22.dp)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(shape)
                        .background(if (isSelected) AppTheme.mint.copy(alpha = 0.5f) else Color.White)
                        .border(
                            1.dp,
                            if (isSelected) AppTheme.court.copy(alpha = 0.4f) else Color.Black.copy(alpha = 0.06f),
                            shape,
                        )
                        .clickable { commit(court) }
                        .padding(14.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clip(continuousShape(16.dp))
                            .background(AppTheme.cream),
                        contentAlignment = Alignment.Center,
                    ) {
                        SportIconView(sport = sport, color = AppTheme.court, size = 22.dp)
                    }

                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            court.name,
                            style = AppText.subheadlineSemibold,
                            color = AppTheme.ink,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            listOfNotNull(court.metroDisplayName, court.distanceLabel, court.address)
                                .joinToString(" · "),
                            style = AppText.caption,
                            color = AppTheme.mutedInk,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }

                    if (isSelected) {
                        Icon(
                            Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = AppTheme.court,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }
        }

        if (!selectsImmediately) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PrimaryActionButton(
                    title = if (pendingSelectionId == null && allowsNoCourt) {
                        L10n.string("Keep no preference", "Оставить без привязки")
                    } else {
                        L10n.string("Choose this club", "Выбрать этот клуб")
                    },
                    tint = AppTheme.ink,
                    enabled = allowsNoCourt || pendingSelectionId != null,
                    onClick = {
                        onSelect(courts.firstOrNull { it.id == pendingSelectionId })
                        onDismiss()
                    },
                )
                Text(
                    L10n.string("You can change the club later", "Клуб можно будет изменить позже"),
                    style = AppText.footnote,
                    color = AppTheme.ink.copy(alpha = 0.38f),
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}



/** Port of `addressSuggestionsSection(onSelectAddress:)`. */
@Composable
private fun AddressSuggestionsSection(
    isLoading: Boolean,
    suggestions: List<AddressSuggestion>,
    canSuggest: Boolean,
    onSelect: (AddressSuggestion) -> Unit,
) {
    if (!canSuggest) return

    if (isLoading) {
        val shape = continuousShape(18.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(Color.White)
                .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(color = AppTheme.court, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
            Text(
                L10n.string("Searching for address", "Ищем адрес"),
                style = AppText.subheadlineSemibold,
                color = AppTheme.ink.copy(alpha = 0.62f),
            )
        }
        return
    }

    if (suggestions.isEmpty()) return

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                L10n.string("Addresses", "Адреса").uppercase(),
                style = AppText.captionSemibold,
                color = AppTheme.ink.copy(alpha = 0.48f),
            )
            Text(
                L10n.string(
                    "If the club isn\u2019t listed, choose the exact address from suggestions.",
                    "Если клуба нет в списке, выберите точный адрес из подсказок.",
                ),
                style = AppText.caption,
                color = AppTheme.ink.copy(alpha = 0.54f),
            )
        }

        suggestions.forEach { suggestion ->
            AddressSuggestionRow(suggestion) { onSelect(suggestion) }
        }
    }
}

/** Port of `private struct AddressSuggestionRow`. */
@Composable
private fun AddressSuggestionRow(suggestion: AddressSuggestion, onSelect: () -> Unit) {
    val shape = continuousShape(18.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White)
            .border(1.dp, Color.Black.copy(alpha = 0.06f), shape)
            .clickable(onClick = onSelect)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier.size(38.dp).clip(CircleShape).background(AppTheme.mint),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Outlined.Place,
                contentDescription = null,
                tint = AppTheme.court,
                modifier = Modifier.size(17.dp),
            )
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            AutoSizeText(
                text = suggestion.title,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
                maxLines = 1,
                minScale = 0.82f,
            )
            Text(
                suggestion.address,
                style = AppText.subheadlineSemibold,
                color = AppTheme.court,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            suggestion.subtitle?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = AppText.caption, color = AppTheme.ink.copy(alpha = 0.5f), maxLines = 1)
            }
        }

        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = AppTheme.ink.copy(alpha = 0.32f),
            modifier = Modifier.padding(top = 12.dp).size(13.dp),
        )
    }
}

/** Port of `private struct MissingClubAddressHint`. */
@Composable
private fun MissingClubAddressHint(address: String, onUseAddress: (String) -> Unit) {
    val normalized = address.trim()
    val shape = continuousShape(20.dp)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppTheme.mint.copy(alpha = 0.74f))
            .border(1.dp, AppTheme.court.copy(alpha = 0.18f), shape)
            .clickable(enabled = normalized.isNotEmpty()) { onUseAddress(normalized) }
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier.size(38.dp).clip(CircleShape).background(AppTheme.mint),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Outlined.Place,
                contentDescription = null,
                tint = AppTheme.court,
                modifier = Modifier.size(18.dp),
            )
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                L10n.string("Use entered address", "Использовать введённый адрес"),
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = AppTheme.ink,
            )
            Text(normalized, style = AppText.subheadlineSemibold, color = AppTheme.court)
            Text(
                L10n.string(
                    "If the address isn\u2019t in suggestions, we\u2019ll save the entered text as the search location.",
                    "Если адреса нет в подсказках, сохраним введённый текст как место поиска.",
                ),
                style = AppText.caption,
                color = AppTheme.ink.copy(alpha = 0.58f),
            )
        }

        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = AppTheme.ink.copy(alpha = 0.32f),
            modifier = Modifier.padding(top = 12.dp).size(13.dp),
        )
    }
}
