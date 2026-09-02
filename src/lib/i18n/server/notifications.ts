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
    "push.winBack.body.many": "{count} players are looking for a game near you"
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
    "push.winBack.body.many": "Рядом игру ищут {count} игроков"
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
