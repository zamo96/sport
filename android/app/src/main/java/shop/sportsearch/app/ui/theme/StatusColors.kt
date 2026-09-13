package shop.sportsearch.app.ui.theme

import androidx.compose.ui.graphics.Color
import shop.sportsearch.app.core.GameRequestInvitee
import shop.sportsearch.app.core.MatchGameRequest
import shop.sportsearch.app.core.RegularPairOccurrence
import shop.sportsearch.app.core.statusLabel

/**
 * Port of the `statusTintColor` / `statusSurfaceColor` pairs in
 * ios/TennisSearchIOS/Core/AppModels.swift.
 *
 * These switch on the already-rendered [statusLabel], matching both the Russian
 * and English spellings, exactly as the Swift originals do.
 */

val MatchGameRequest.statusTintColor: Color
    get() = when (statusLabel) {
        "Поиск", "Search" -> Color(red = 0.34f, green = 0.47f, blue = 0.68f)
        "В процессе набора", "В процессе набора людей", "Подбор игроков", "Recruiting", "Finding players" ->
            Color(red = 0.72f, green = 0.48f, blue = 0.18f)
        "В ожидании принятия", "Ждём подтверждение", "Игра назначается", "Ждёт подтверждения",
        "Awaiting decision", "Awaiting confirmation" -> Color(red = 0.49f, green = 0.45f, blue = 0.78f)
        "Игрок найден", "Игроки найдены", "Игра подтверждена", "Игра прошла",
        "Player found", "Players found", "Game confirmed", "Game played" ->
            Color(red = 0.16f, green = 0.58f, blue = 0.33f)
        "Скоро начнется", "Starting soon" -> Color(red = 0.78f, green = 0.52f, blue = 0.18f)
        "Игра началась", "Игра идет", "Game started", "Game in progress" ->
            Color(red = 0.17f, green = 0.50f, blue = 0.72f)
        "Игра закончилась", "Game ended" -> Color(red = 0.33f, green = 0.33f, blue = 0.38f)
        "Не сыграли", "Not played" -> Color(red = 0.72f, green = 0.22f, blue = 0.20f)
        "Подтверждена", "Confirmed" -> Color(red = 0.16f, green = 0.58f, blue = 0.33f)
        "Отменена", "Canceled" -> Color(red = 0.72f, green = 0.22f, blue = 0.20f)
        else -> AppTheme.court
    }

val MatchGameRequest.statusSurfaceColor: Color
    get() = when (statusLabel) {
        "Поиск", "Search" -> Color(red = 0.88f, green = 0.92f, blue = 0.98f)
        "В процессе набора", "В процессе набора людей", "Подбор игроков", "Recruiting", "Finding players" ->
            Color(red = 0.98f, green = 0.93f, blue = 0.84f)
        "В ожидании принятия", "Ждём подтверждение", "Игра назначается", "Ждёт подтверждения",
        "Awaiting decision", "Awaiting confirmation" -> Color(red = 0.91f, green = 0.90f, blue = 0.99f)
        "Игрок найден", "Игроки найдены", "Игра подтверждена", "Игра прошла",
        "Player found", "Players found", "Game confirmed", "Game played" ->
            Color(red = 0.86f, green = 0.95f, blue = 0.89f)
        "Скоро начнется", "Starting soon" -> Color(red = 0.99f, green = 0.94f, blue = 0.83f)
        "Игра началась", "Игра идет", "Game started", "Game in progress" ->
            Color(red = 0.86f, green = 0.93f, blue = 0.98f)
        "Игра закончилась", "Game ended" -> Color(red = 0.90f, green = 0.90f, blue = 0.92f)
        "Не сыграли", "Not played" -> Color(red = 0.96f, green = 0.88f, blue = 0.88f)
        "Подтверждена", "Confirmed" -> Color(red = 0.86f, green = 0.95f, blue = 0.89f)
        "Отменена", "Canceled" -> Color(red = 0.96f, green = 0.88f, blue = 0.88f)
        else -> AppTheme.mint.copy(alpha = 0.68f)
    }

val RegularPairOccurrence.statusTintColor: Color
    get() = when (status.lowercase()) {
        "confirmed" -> AppTheme.court
        "declined" -> Color.Red.copy(alpha = 0.9f)
        "canceled", "cancelled", "expired" -> AppTheme.ink.copy(alpha = 0.72f)
        else -> AppTheme.ink
    }

val RegularPairOccurrence.statusSurfaceColor: Color
    get() = when (status.lowercase()) {
        "confirmed" -> AppTheme.mint
        "declined" -> Color.Red.copy(alpha = 0.12f)
        "canceled", "cancelled", "expired" -> Color.Gray.copy(alpha = 0.18f)
        else -> AppTheme.cream
    }

val GameRequestInvitee.statusTint: Color
    get() = when (status.lowercase()) {
        "accepted" -> AppTheme.court
        "declined", "rejected" -> Color.Red.copy(alpha = 0.88f)
        "canceled", "cancelled", "withdrawn" -> Color.Gray.copy(alpha = 0.82f)
        else -> Color(red = 1.0f, green = 0.70f, blue = 0.30f)
    }
