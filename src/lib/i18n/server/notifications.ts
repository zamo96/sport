import { defineServerMessages } from "@/lib/i18n/server/define";
import type { SupportedLocale } from "@/lib/locales";

export const notificationMessages = defineServerMessages(
  {
    "push.hotDigest.title.one": "An urgent game nearby",
    "push.hotDigest.title.few": "{count} urgent games nearby",
    "push.hotDigest.title.many": "{count} urgent games nearby",
    "push.hotDigest.body.court": "{sports} · for example {court}",
    "push.hotDigest.body.plain": "{sports} · reply in the Urgent tab",
    "push.onboarding.title": "One step left",
    "push.onboarding.body": "Add your level and schedule — we will pick opponents for you",
    "push.firstPlayers.title": "There are players near you",
    "push.firstPlayers.body": "We found {count} — take a look and see who fits",
    "push.newPlayers.title": "New players near you",
    "push.newPlayers.body.one": "{count} new player since your last visit",
    "push.newPlayers.body.few": "{count} new players since your last visit",
    "push.newPlayers.body.many": "{count} new players since your last visit",
    "push.likesWaiting.title": "Someone liked you",
    "push.likesWaiting.body.one": "{count} player is waiting for your reply",
    "push.likesWaiting.body.few": "{count} players are waiting for your reply",
    "push.likesWaiting.body.many": "{count} players are waiting for your reply",
    "push.trainingNudge.title": "Fancy a session?",
    "push.trainingNudge.body": "You are free {day} — the search is prefilled, just tap create",
    "push.day.monday": "on Monday",
    "push.day.tuesday": "on Tuesday",
    "push.day.wednesday": "on Wednesday",
    "push.day.thursday": "on Thursday",
    "push.day.friday": "on Friday",
    "push.day.saturday": "on Saturday",
    "push.day.sunday": "on Sunday",
    "push.winBack.title": "It has been a while",
    "push.winBack.body.one": "{count} player is looking for a game near you",
    "push.winBack.body.few": "{count} players are looking for a game near you",
    "push.winBack.body.many": "{count} players are looking for a game near you",
    "push.player.fallback": "A player",
    "push.court.fallback": "Venue to be confirmed",
    "push.searchResponseWaiting.title.one": "{name} is waiting for your answer",
    "push.searchResponseWaiting.title.few": "{count} responses are waiting for your answer",
    "push.searchResponseWaiting.title.many": "{count} responses are waiting for your answer",
    "push.searchResponseWaiting.body.one": "A response to your search — confirm or decline",
    "push.searchResponseWaiting.body.few": "Open the search and decide who you play with",
    "push.searchResponseWaiting.body.many": "Open the search and decide who you play with",
    "push.gameOutcome.title.one": "How did the game go?",
    "push.gameOutcome.title.few": "{count} games are waiting for a result",
    "push.gameOutcome.title.many": "{count} games are waiting for a result",
    "push.gameOutcome.body.one": "{when} · {opponent} — mark whether you played",
    "push.gameOutcome.body.few": "Mark which of them happened, starting with {when}",
    "push.gameOutcome.body.many": "Mark which of them happened, starting with {when}",
    "push.regularSlotWaiting.title.one": "{name} is waiting for your confirmation",
    "push.regularSlotWaiting.title.few": "{count} regular slots are waiting for you",
    "push.regularSlotWaiting.title.many": "{count} regular slots are waiting for you",
    "push.regularSlotWaiting.body.one": "{when} · {court} — confirm if the time works",
    "push.regularSlotWaiting.body.few": "Starting with {when} — mark the slots that work",
    "push.regularSlotWaiting.body.many": "Starting with {when} — mark the slots that work"
  },
  {
    "push.hotDigest.title.one": "Есть срочная игра рядом",
    "push.hotDigest.title.few": "Рядом {count} срочные игры",
    "push.hotDigest.title.many": "Рядом {count} срочных игр",
    "push.hotDigest.body.court": "{sports} · например {court}",
    "push.hotDigest.body.plain": "{sports} · можно откликнуться во вкладке «Срочно»",
    "push.onboarding.title": "Остался один шаг",
    "push.onboarding.body": "Укажите уровень и расписание — мы подберём соперников",
    "push.firstPlayers.title": "Рядом есть игроки",
    "push.firstPlayers.body": "Мы нашли {count} — посмотрите, кто подойдёт",
    "push.newPlayers.title": "Рядом новые игроки",
    "push.newPlayers.body.one": "С вашего последнего визита появился {count} новый игрок",
    "push.newPlayers.body.few": "С вашего последнего визита появились {count} новых игрока",
    "push.newPlayers.body.many": "С вашего последнего визита появилось {count} новых игроков",
    "push.likesWaiting.title": "Вас лайкнули",
    "push.likesWaiting.body.one": "Ответа ждёт {count} игрок",
    "push.likesWaiting.body.few": "Ответа ждут {count} игрока",
    "push.likesWaiting.body.many": "Ответа ждут {count} игроков",
    "push.trainingNudge.title": "Не хотите сходить на тренировку?",
    "push.trainingNudge.body": "У вас свободно {day} — поиск уже заполнен, останется нажать «Создать»",
    // Предлог входит в значение: «во вторник», но «в понедельник».
    "push.day.monday": "в понедельник",
    "push.day.tuesday": "во вторник",
    "push.day.wednesday": "в среду",
    "push.day.thursday": "в четверг",
    "push.day.friday": "в пятницу",
    "push.day.saturday": "в субботу",
    "push.day.sunday": "в воскресенье",
    "push.winBack.title": "Давно вас не было",
    "push.winBack.body.one": "Рядом игру ищет {count} игрок",
    "push.winBack.body.few": "Рядом игру ищут {count} игрока",
    "push.winBack.body.many": "Рядом игру ищут {count} игроков",
    "push.player.fallback": "Игрок",
    "push.court.fallback": "Место уточняется",
    // Пол игрока неизвестен, поэтому имя стоит в именительном, а глагол — в
    // форме без родового окончания: «Аня ждёт», «Иван ждёт».
    "push.searchResponseWaiting.title.one": "{name} ждёт вашего ответа",
    "push.searchResponseWaiting.title.few": "{count} отклика ждут ответа",
    "push.searchResponseWaiting.title.many": "{count} откликов ждут ответа",
    "push.searchResponseWaiting.body.one": "Отклик на ваш поиск — подтвердите или отклоните",
    "push.searchResponseWaiting.body.few": "Откройте поиск и решите, с кем играете",
    "push.searchResponseWaiting.body.many": "Откройте поиск и решите, с кем играете",
    "push.gameOutcome.title.one": "Как прошла игра?",
    "push.gameOutcome.title.few": "{count} игры ждут отметки",
    "push.gameOutcome.title.many": "{count} игр ждут отметки",
    "push.gameOutcome.body.one": "{when} · {opponent} — отметьте, сыграли вы или нет",
    "push.gameOutcome.body.few": "Отметьте, какие из них состоялись, начиная с {when}",
    "push.gameOutcome.body.many": "Отметьте, какие из них состоялись, начиная с {when}",
    // Имя партнёра в именительном, глагол без родового окончания: «Аня ждёт».
    "push.regularSlotWaiting.title.one": "{name} ждёт вашего подтверждения",
    "push.regularSlotWaiting.title.few": "{count} слота регулярной пары ждут вас",
    "push.regularSlotWaiting.title.many": "{count} слотов регулярной пары ждут вас",
    "push.regularSlotWaiting.body.one": "{when} · {court} — подтвердите, если время подходит",
    "push.regularSlotWaiting.body.few": "Начиная с {when} — отметьте, какие слоты подходят",
    "push.regularSlotWaiting.body.many": "Начиная с {when} — отметьте, какие слоты подходят"
  }
);

/**
 * Русскому нужны три формы («1 игра», «2 игры», «5 игр»), английскому — две.
 * Возвращает суффикс ключа, а не готовую строку, чтобы формы жили в каталоге.
 */
export function pluralKeySuffix(locale: SupportedLocale, count: number): "one" | "few" | "many" {
  if (locale !== "ru") {
    return count === 1 ? "one" : "many";
  }

  const mod10 = count % 10;
  const mod100 = count % 100;

  if (mod10 === 1 && mod100 !== 11) {
    return "one";
  }

  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return "few";
  }

  return "many";
}
