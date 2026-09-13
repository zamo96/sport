package shop.sportsearch.app.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import shop.sportsearch.app.core.AppLocale
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.core.LocaleStore
import shop.sportsearch.app.ui.AppViewModel
import shop.sportsearch.app.ui.theme.AppRadius
import shop.sportsearch.app.ui.theme.AppText
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape

/** Port of `struct ServerRecoveryOverlay`. */
@Composable
fun ServerRecoveryOverlay(
    title: String,
    message: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val transition = rememberInfiniteTransition(label = "serverRecovery")
    val pulse by transition.animateFloat(
        initialValue = 88f,
        targetValue = 110f,
        animationSpec = infiniteRepeatable(tween(1450), RepeatMode.Reverse),
        label = "pulse",
    )
    val drift by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1100), RepeatMode.Reverse),
        label = "drift",
    )
    val cardShape = continuousShape(AppRadius.sheet)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.18f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onDismiss,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 18.dp)
                .appShadow(AppTheme.ink.copy(alpha = 0.16f), radius = 28.dp, offsetY = 18.dp, shape = cardShape)
                .clip(cardShape)
                .background(Color.White.copy(alpha = 0.96f))
                .border(1.dp, Color.White.copy(alpha = 0.78f), cardShape)
                .padding(horizontal = 22.dp, vertical = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Box(modifier = Modifier.height(118.dp), contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .size(pulse.dp)
                        .background(
                            Brush.radialGradient(
                                0f to AppTheme.clay.copy(alpha = 0.22f),
                                1f to Color.Transparent,
                            ),
                            CircleShape,
                        ),
                )
                Box(
                    Modifier
                        .offset(
                            x = (-10 + 24 * drift).dp,
                            y = (12 - 22 * drift).dp,
                        )
                        .size((72 + 12 * drift).dp)
                        .background(
                            Brush.radialGradient(
                                0f to AppTheme.court.copy(alpha = 0.20f),
                                1f to Color.Transparent,
                            ),
                            CircleShape,
                        ),
                )
                Box(
                    Modifier
                        .appShadow(AppTheme.ink.copy(alpha = 0.12f), radius = 16.dp, offsetY = 10.dp, shape = CircleShape)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.92f))
                        .padding(22.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.WifiOff,
                        contentDescription = null,
                        tint = AppTheme.ink,
                        modifier = Modifier.size(28.dp),
                    )
                }
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(title, style = AppText.title3Bold, color = AppTheme.ink, textAlign = TextAlign.Center)
                Text(
                    message,
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.68f),
                    textAlign = TextAlign.Center,
                )
            }

            PrimaryActionButton(
                title = L10n.string("Got it", "Понятно"),
                onClick = onDismiss,
                tint = AppTheme.ink,
            )
        }
    }
}

/**
 * Port of `private struct MenuTabLoadingOverlay` from ContentView.swift: three
 * bouncing, spinning balls on a near-black scrim while a tab loads.
 */
@Composable
fun MenuTabLoadingOverlay(title: String, modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "tabLoading")

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.padding(bottom = 54.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                repeat(3) { index ->
                    val phase by transition.animateFloat(
                        initialValue = 0f,
                        targetValue = 1f,
                        animationSpec = infiniteRepeatable(
                            animation = tween(580, delayMillis = index * 160),
                            repeatMode = RepeatMode.Reverse,
                        ),
                        label = "ball$index",
                    )
                    val spin by transition.animateFloat(
                        initialValue = 0f,
                        targetValue = 360f,
                        animationSpec = infiniteRepeatable(tween(1160), RepeatMode.Restart),
                        label = "spin$index",
                    )

                    Box(
                        modifier = Modifier
                            .offset(y = (10 - 20 * phase).dp)
                            .scale(0.76f + 0.28f * phase)
                            .rotate(spin)
                            .appShadow(
                                color = Color(0xFF30D693).copy(alpha = 0.2f + 0.24f * phase),
                                radius = (6 + 8 * phase).dp,
                                offsetY = 6.dp,
                                shape = CircleShape,
                            )
                            .size(22.dp)
                            .background(AppTheme.loadingBall, CircleShape),
                    )
                }
            }

            val titleAlpha by transition.animateFloat(
                initialValue = 0.62f,
                targetValue = 0.9f,
                animationSpec = infiniteRepeatable(tween(720), RepeatMode.Reverse),
                label = "titleAlpha",
            )
            Text(
                text = title,
                style = AppText.callout.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
                color = Color.White.copy(alpha = titleAlpha),
            )
        }
    }
}

/** Port of `private struct LocaleRecommendationBanner` in TennisSearchIOSApp.swift. */
@Composable
fun LocaleRecommendationBanner(
    recommendation: AppViewModel.LocaleRecommendation,
    onAccept: () -> Unit,
    onDismiss: () -> Unit,
) {
    val isRussian = LocaleStore.current == AppLocale.RU
    val languageName = recommendation.locale.displayName
    val shape = continuousShape(18.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .appShadow(Color.Black.copy(alpha = 0.25f), 16.dp, 0.dp, 8.dp, shape)
            .clip(shape)
            // `.regularMaterial` — a light, near-opaque scrim over whatever is behind.
            .background(AppTheme.creamLight.copy(alpha = 0.97f))
            .border(1.dp, Color.White.copy(alpha = 0.16f), shape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            Icon(
                Icons.Filled.Language,
                contentDescription = null,
                tint = Color(0xFF34C759),
                modifier = Modifier.size(20.dp),
            )

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    if (isRussian) "Язык для вашей локации" else "Language for your location",
                    style = AppText.headline,
                    color = AppTheme.ink,
                )
                Text(
                    when {
                        isRussian && recommendation.locale == AppLocale.RU ->
                            "Для выбранной страны рекомендуем русский язык. Переключить?"
                        isRussian -> "Для выбранной страны рекомендуем English. Переключить?"
                        recommendation.locale == AppLocale.RU ->
                            "Russian is recommended for the selected country. Switch?"
                        else -> "English is recommended for the selected country. Switch?"
                    },
                    style = AppText.subheadline,
                    color = AppTheme.ink.copy(alpha = 0.62f),
                )
            }

            Box(
                modifier = Modifier.size(28.dp).clip(CircleShape).clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = if (isRussian) "Закрыть" else "Close",
                    tint = AppTheme.ink.copy(alpha = 0.62f),
                    modifier = Modifier.size(12.dp),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SecondaryActionButton(
                title = if (isRussian) "Оставить текущий" else "Keep current",
                onClick = onDismiss,
                modifier = Modifier.weight(1f),
            )
            PrimaryActionButton(
                title = if (isRussian) "Переключить на $languageName" else "Switch to $languageName",
                onClick = onAccept,
                modifier = Modifier.weight(1f),
                tint = Color(0xFF34C759),
            )
        }
    }
}
