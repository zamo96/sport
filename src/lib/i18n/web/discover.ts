import type { SupportedLocale } from "@/lib/locales";
import { defineWebMessages, interpolateWebMessage, type WebTranslationValues } from "@/lib/i18n/web/define";
import { SPORT_LABELS, SPORT_OPTIONS } from "@/lib/constants";
import { getAuthSportLabel } from "@/lib/i18n/web/auth";

export const discoverMessages = defineWebMessages(
  {
    "discover.nearby.clubsError": "Nearby venues could not be loaded.",
    "discover.nearby.retry": "Try again",
    "discover.nearby.title": "Nearby options · {city}",
    "discover.nearby.players": "No players match here yet. Showing nearby options within {radius} km, with the same preferences.",
    "discover.nearby.clubs": "Venues within {radius} km",
    "discover.nearby.distance": "{distance} in a straight line from {city}",
    "discover.nearby.empty": "No players match your current preferences yet.",
    "discover.common.player": "Player",
    "discover.common.city": "City",
    "discover.common.unspecifiedCity": "City not specified",
    "discover.common.close": "Close",
    "discover.common.gotIt": "Got it",
    "discover.common.next": "Next",
    "discover.common.skip": "Skip",
    "discover.common.soon": "Soon",
    "discover.common.level": "Level {level}",
    "discover.common.and": "and",
    "discover.common.andMore": "{name} and {count} more",
    "discover.page.eyebrow": "Discover",
    "discover.page.title": "Players nearby",
    "discover.page.urgent": "Urgent",
    "discover.page.createHot": "Create a quick game · {count} looking now",
    "discover.page.createRegular": "Create a regular search",
    "discover.page.upcomingEmptyTitle": "No upcoming games yet",
    "discover.page.upcomingEmptyText": "Once someone confirms a game or you agree on one in chat, it will appear here.",
    "discover.tabs.upcoming": "Upcoming games",
    "discover.tabs.similar": "Similar players",
    "discover.tabs.likes": "Want to play with you",
    "discover.tabs.regular": "Regular",
    "discover.tabs.urgent": "Urgent",
    "discover.intro.badge": "How discovery works",
    "discover.intro.title": "Browse players first, then choose how to play",
    "discover.intro.text": "Discovery is split into a few simple modes, so you can quickly see who is ready now or arrange a game ahead of time.",
    "discover.intro.similar.title": "Similar players",
    "discover.intro.similar.text": "Cards are already sorted by sport, level, availability, and distance. Each card shows the next step and why it was recommended.",
    "discover.intro.regular.title": "Regular",
    "discover.intro.regular.text": "Players search ahead by day and time. A good fit when you want to make plans without rushing.",
    "discover.intro.urgent.title": "Urgent",
    "discover.intro.urgent.text": "Games for today and tomorrow, when someone needs a partner soon.",
    "discover.intro.likes.title": "Want to play with you",
    "discover.intro.likes.withCount": "You already have {count} incoming likes. Liking back opens a chat immediately.",
    "discover.intro.likes.empty": "This tab will appear when someone wants to play specifically with you.",
    "discover.tour.similar.title": "Similar players are recommended here",
    "discover.tour.similar.text": "Cards are already sorted by sport, level, distance, and availability. Quickly decide who you would like to play with.",
    "discover.tour.regular.title": "Players plan games ahead here",
    "discover.tour.regular.text": "These are regular searches by day and time, for arranging a game without rushing.",
    "discover.tour.urgent.title": "Urgent games are collected here",
    "discover.tour.urgent.text": "Games for today and tomorrow, when a partner is needed quickly. The fastest arrangements start here.",
    "discover.tour.progress": "Tip {step} of {count}",
    "discover.tour.close": "Close tip",
    "discover.filters.title": "Filters",
    "discover.filters.subtitle": "Choose a sport first. Use the other filters only when you need to narrow the results.",
    "discover.filters.reset": "Reset",
    "discover.filters.quickTitle": "Quick search by sport",
    "discover.filters.quickText": "Start with the sport. It is the most important filter for finding a partner.",
    "discover.filters.active": "{count} active",
    "discover.filters.none": "no filters",
    "discover.filters.radius": "Radius",
    "discover.filters.radiusValue": "Up to {value} km",
    "discover.filters.level": "Level",
    "discover.filters.min": "Min",
    "discover.filters.max": "Max",
    "discover.filters.advanced": "More filters",
    "discover.filters.city": "City",
    "discover.filters.cityHint": "The app is currently available only in Saint Petersburg.",
    "discover.filters.gender": "Gender",
    "discover.guest.eyebrow": "Guest mode",
    "discover.guest.profile": "Your profile",
    "discover.guest.defaultFormat": "Default format",
    "discover.guest.draft": "Your profile draft is ready. Browse player cards and active searches; we will ask for your email only when you take an action.",
    "discover.guest.createHot": "Create a quick game",
    "discover.guest.loading": "Finding players for your profile…",
    "discover.guest.error": "Could not load recommendations",
    "discover.likes.emptyTitle": "No one wants to play with you yet",
    "discover.likes.emptyText": "When someone likes you, their card will appear here. Liking back opens a shared chat immediately.",
    "discover.likes.cardTitle": "Wants to play with you",
    "discover.likes.matchScore": "Match {score}",
    "discover.likes.reasonTitle": "Why recommended",
    "discover.likes.bioFallback": "This player seems ready to arrange a game quickly.",
    "discover.likes.play": "Let's play",
    "discover.notifications.open": "Open notification center",
    "discover.regular.title": "You already play regularly",
    "discover.regular.subtitle": "Your current regular partners come first, followed by players looking for a partner.",
    "discover.regular.autoSlot": "The next slot will appear automatically",
    "discover.regular.gameCreated": "Next game created · {time}",
    "discover.regular.slotConfirmed": "Slot confirmed · {time}",
    "discover.regular.slotDeclined": "This slot did not work · {time}",
    "discover.regular.slotNeedsReply": "Reply needed for this slot · {time}",
    "discover.regular.scheduleUnknown": "Schedule to be confirmed",
    "discover.regular.open": "Open regular play",
    "discover.regular.openGame": "Open game",
    "discover.regular.checkSlot": "Check slot",
    "discover.respond.approved": "You have been selected",
    "discover.respond.withdrawing": "Withdrawing…",
    "discover.respond.withdraw": "Withdraw response",
    "discover.respond.found": "Player already found",
    "discover.respond.sending": "Sending…",
    "discover.respond.action": "Respond",
    "discover.respond.authTitle": "Verify your email to respond",
    "discover.respond.authText": "Then we can show your response to the organizer, send you their answer, and open a chat if they select you.",
    "discover.seeking.hotEmptyTitle": "No urgent searches right now",
    "discover.seeking.emptyTitle": "No one is looking for a game right now",
    "discover.seeking.hotEmptyText": "When someone needs a replacement for today or tomorrow, their urgent search will appear here.",
    "discover.seeking.emptyText": "Ask players to turn on game search or come back later.",
    "discover.seeking.duration": "{minutes} min",
    "discover.seeking.search": "Search",
    "discover.seeking.lifecycle.ended": "Game ended",
    "discover.seeking.lifecycle.inProgress": "Game in progress",
    "discover.seeking.lifecycle.started": "Game started",
    "discover.seeking.lifecycle.soon": "Starting soon",
    "discover.seeking.lifecycle.playersFound": "Players found",
    "discover.seeking.lifecycle.playerFound": "Player found",
    "discover.seeking.lifecycle.recruiting": "Recruiting players",
    "discover.seeking.lifecycle.closed": "Closed",
    "discover.seeking.countdown.started": "already started",
    "discover.seeking.countdown.in": "in {value}",
    "discover.seeking.countdown.lessMinute": "in less than a minute",
    "discover.seeking.rosterMany": "{approved} of {needed} players found",
    "discover.seeking.rosterConfirmed": "Player confirmed",
    "discover.seeking.rosterOne": "1 player needed",
    "discover.seeking.hotBookedTitle": "Player needed soon",
    "discover.seeking.hotTitle": "Quick game coming up",
    "discover.seeking.regularTitle": "Looking for a partner by schedule",
    "discover.seeking.bioFallback": "Wants to arrange a game quickly without a long chat.",
    "discover.seeking.start": "Starts",
    "discover.seeking.match": "Match",
    "discover.seeking.lookingFor": "Looking for",
    "discover.seeking.why": "Why recommended",
    "discover.seeking.when": "When",
    "discover.seeking.place": "Venue",
    "discover.seeking.placeBooked": "Venue selected",
    "discover.seeking.placeLater": "Venue to be chosen later",
    "discover.seeking.roster": "Players",
    "discover.seeking.target": "Looking for",
    "discover.seeking.ownLevelUnknown": "Your level: unknown",
    "discover.seeking.ownLevel": "Your level: {level}",
    "discover.seeking.playersNeeded": "Players needed: {count}",
    "discover.seeking.timeInChat": "Time to be agreed in chat",
    "discover.swipe.matchFallback": "player",
    "discover.swipe.emptyTitle": "No more cards",
    "discover.empty.seenAll.title": "You have seen everyone",
    "discover.empty.sportAll": "All · {count}",
    "discover.empty.why.searching": "looking for a game · {count}",
    "discover.empty.why.members": "{count} players from here",
    "discover.empty.why.rent": "courts to rent",
    "discover.empty.allCourtsTile": "All courts",
    "discover.empty.seenAll.text": "There are {count} profiles in {city} right now, and you went through all of them. We will write when new ones show up.",
    "discover.empty.firstHere.title": "You are the first one here",
    "discover.empty.firstHere.text": "No matching players to show in {city} yet. You can invite the people you already play with.",
    "discover.empty.courtsTitle": "Courts nearby",
    "discover.empty.allCourts": "All courts",
    "discover.empty.invite.title": "Invite whoever you already play with",
    "discover.empty.invite.text": "It is faster to find a partner when your own people are around.",
    "discover.empty.invite.share": "Share",
    "discover.empty.invite.copied": "Link copied",
    "discover.empty.invite.stats": "Opened {visits} · joined {joined}",
    "discover.empty.invite.shareText": "I play in {city} and I am looking for partners. Join me:",
    "discover.empty.thin.title": "Few players nearby",
    "discover.empty.thin.text": "Invite someone you know — the city fills up faster that way.",    "discover.swipe.emptyText": "Change the sport filters or come back when new players join.",
    "discover.swipe.openMatches": "Open matches",
    "discover.swipe.sportsCenters": "Sports venues",
    "discover.swipe.title": "Quick recommendations",
    "discover.swipe.profileSports": "Sports in your profile: {count}",
    "discover.swipe.remaining": "Remaining",
    "discover.swipe.skipStamp": "Skip",
    "discover.swipe.playStamp": "Let's play",
    "discover.swipe.score": "Score {score}",
    "discover.swipe.nearby": "Nearby",
    "discover.swipe.districtUnknown": "Area not specified",
    "discover.swipe.nextStep": "Next step",
    "discover.swipe.nextStepText": "Tap “Let's play” to show your interest. If it is mutual, a chat will open.",
    "discover.swipe.why": "Why recommended",
    "discover.swipe.reasonsSoon": "Reasons such as sport, level, distance, and availability will appear here soon.",
    "discover.swipe.bioFallback": "Ready to arrange a venue and play without a long chat.",
    "discover.swipe.play": "Let's play",
    "discover.swipe.matchEyebrow": "It's a match",
    "discover.swipe.matchTitle": "You and {name} are both interested",
    "discover.swipe.matchText": "Open the shared chat to agree on the details or choose a sports venue right away.",
    "discover.swipe.continue": "Keep browsing",
    "discover.swipe.openChat": "Open chat",
    "discover.swipe.authTitle": "Verify your email to show interest",
    "discover.swipe.authText": "Your profile is ready. After verifying your email, you can like players, open chats, and receive replies.",
    "discover.reason.sportLevel": "Sport and level match",
    "discover.reason.distance": "Distance: {distance}",
    "discover.reason.availability": "Availability: {value}",
    "discover.reason.sport": "Matching sport: {sport}",
    "discover.reason.level": "Similar level: {level}",
    "discover.reason.nearby": "Nearby: {distance}",
    "discover.reason.sameArea": "Nearby area",
    "discover.reason.schedule": "Schedules overlap",
    "discover.distance.nearby": "nearby",
    "discover.distance.meters": "{value} m",
    "discover.distance.kilometers": "{value} km",
    "discover.upcoming.roster": "{count} players",
    "discover.upcoming.title": "Confirmed games",
    "discover.upcoming.regularText": "This regular-play slot is confirmed. If your plans change, open regular play and adjust the next slot.",
    "discover.upcoming.gameText": "This game is confirmed. Open the game details or shared chat to settle any final details.",
    "discover.upcoming.rosterChat": "Group chat",
    "discover.upcoming.sharedChat": "Shared chat",
    "discover.label.day.monday": "Mon",
    "discover.label.day.tuesday": "Tue",
    "discover.label.day.wednesday": "Wed",
    "discover.label.day.thursday": "Thu",
    "discover.label.day.friday": "Fri",
    "discover.label.day.saturday": "Sat",
    "discover.label.day.sunday": "Sun",
    "discover.label.time.morning": "Morning",
    "discover.label.time.day": "Afternoon",
    "discover.label.time.evening": "Evening",
    "discover.label.gender.male": "Male",
    "discover.label.gender.female": "Female",
    "discover.label.gender.other": "Other",
    "discover.label.format.singles": "Singles",
    "discover.label.format.doubles": "Doubles",
    "discover.label.format.both": "Any format",
    "discover.label.surface.hard": "Hard",
    "discover.label.surface.clay": "Clay",
    "discover.label.surface.grass": "Grass",
    "discover.label.surface.any": "Any surface",
    "discover.label.hot.today": "Today",
    "discover.label.hot.tomorrow": "Tomorrow",
    "discover.label.hot.day_after_tomorrow": "Day after tomorrow"
  },
  {
    "discover.nearby.clubsError": "Не удалось загрузить клубы поблизости.",
    "discover.nearby.retry": "Попробовать снова",
    "discover.nearby.title": "Варианты рядом · {city}",
    "discover.nearby.players": "По выбранным условиям игроков не найдено. Показываем варианты в радиусе {radius} км с теми же предпочтениями.",
    "discover.nearby.clubs": "Клубы в радиусе {radius} км",
    "discover.nearby.distance": "{distance} по прямой · точка отсчёта: {city}",
    "discover.nearby.empty": "По текущим условиям игроков пока не найдено.",
    "discover.common.player": "Игрок",
    "discover.common.city": "Город",
    "discover.common.unspecifiedCity": "Город не указан",
    "discover.common.close": "Закрыть",
    "discover.common.gotIt": "Понятно",
    "discover.common.next": "Дальше",
    "discover.common.skip": "Пропустить",
    "discover.common.soon": "Скоро",
    "discover.common.level": "Уровень {level}",
    "discover.common.and": "и",
    "discover.common.andMore": "{name} и еще {count}",
    "discover.page.eyebrow": "Поиск",
    "discover.page.title": "Игроки рядом",
    "discover.page.urgent": "Срочно",
    "discover.page.createHot": "Создать быструю игру · сейчас ищут {count}",
    "discover.page.createRegular": "Создать регулярный поиск",
    "discover.page.upcomingEmptyTitle": "Ближайших игр пока нет",
    "discover.page.upcomingEmptyText": "Как только кто-то подтвердит игру или ты договоришься в чате, она появится здесь.",
    "discover.tabs.upcoming": "Ближайшие игры",
    "discover.tabs.similar": "Похожие игроки",
    "discover.tabs.likes": "Хотят с тобой сыграть",
    "discover.tabs.regular": "Регулярно",
    "discover.tabs.urgent": "Срочно",
    "discover.intro.badge": "Как устроен поиск",
    "discover.intro.title": "Сначала смотри игроков, потом выбирай сценарий",
    "discover.intro.text": "Здесь поиск разделён на несколько простых режимов, чтобы быстро понять, с кем можно сыграть уже сейчас или договориться заранее.",
    "discover.intro.similar.title": "Похожие игроки",
    "discover.intro.similar.text": "Карточки уже отсортированы по спорту, уровню, доступности и расстоянию. На карточке есть следующий шаг и причины подбора.",
    "discover.intro.regular.title": "Регулярно",
    "discover.intro.regular.text": "Игроки заранее ищут партнёра по дням и времени. Подходит, если хочешь договориться спокойно.",
    "discover.intro.urgent.title": "Срочно",
    "discover.intro.urgent.text": "Здесь события на сегодня и завтра, когда человек ищет партнёра на ближайшее время.",
    "discover.intro.likes.title": "Хотят с тобой сыграть",
    "discover.intro.likes.withCount": "Сейчас тебя уже ждут {count} входящих лайков. Ответный лайк сразу открывает чат.",
    "discover.intro.likes.empty": "Эта вкладка появится, когда кто-то сам захочет сыграть именно с тобой.",
    "discover.tour.similar.title": "Здесь подбираются похожие игроки",
    "discover.tour.similar.text": "Карточки уже отсортированы по спорту, уровню, расстоянию и доступности. Здесь можно быстро решить, с кем хочется сыграть.",
    "discover.tour.regular.title": "Тут игроки ищут игру заранее",
    "discover.tour.regular.text": "Это регулярные поиски по дням и времени. Удобно выбирать спокойный сценарий без спешки.",
    "discover.tour.urgent.title": "Здесь собраны срочные события",
    "discover.tour.urgent.text": "Игры на сегодня и завтра, когда нужно быстро найти партнёра. Самые быстрые договорённости начинаются отсюда.",
    "discover.tour.progress": "Подсказка {step} из {count}",
    "discover.tour.close": "Закрыть подсказку",
    "discover.filters.title": "Фильтры",
    "discover.filters.subtitle": "Главное выбрать спорт. Остальные фильтры нужны только чтобы быстро сузить выдачу.",
    "discover.filters.reset": "Сбросить",
    "discover.filters.quickTitle": "Быстрый поиск по спорту",
    "discover.filters.quickText": "Начни с вида спорта. Это самый важный фильтр для поиска партнера.",
    "discover.filters.active": "{count} активн.",
    "discover.filters.none": "без фильтров",
    "discover.filters.radius": "Радиус",
    "discover.filters.radiusValue": "До {value} км",
    "discover.filters.level": "Уровень",
    "discover.filters.min": "От",
    "discover.filters.max": "До",
    "discover.filters.advanced": "Дополнительные фильтры",
    "discover.filters.city": "Город",
    "discover.filters.cityHint": "Пока приложение работает только в Санкт-Петербурге.",
    "discover.filters.gender": "Пол",
    "discover.guest.eyebrow": "Гостевой режим",
    "discover.guest.profile": "Твой профиль",
    "discover.guest.defaultFormat": "Формат по умолчанию",
    "discover.guest.draft": "Уже собран черновик профиля. Смотри карточки и активные поиски, а email попросим только в момент действия.",
    "discover.guest.createHot": "Создать быструю игру",
    "discover.guest.loading": "Подбираем игроков под твой профиль…",
    "discover.guest.error": "Не удалось загрузить подбор",
    "discover.likes.emptyTitle": "Пока никто не хочет с тобой сыграть",
    "discover.likes.emptyText": "Когда кто-то поставит тебе лайк, карточка появится здесь. Ответный лайк сразу откроет общий чат.",
    "discover.likes.cardTitle": "Хочет с тобой сыграть",
    "discover.likes.matchScore": "Совпадение {score}",
    "discover.likes.reasonTitle": "Почему в подборе",
    "discover.likes.bioFallback": "Похоже, этот игрок хочет быстро договориться и выйти на игру.",
    "discover.likes.play": "Можно поиграть",
    "discover.notifications.open": "Открыть центр уведомлений",
    "discover.regular.title": "Уже играете регулярно",
    "discover.regular.subtitle": "Сначала текущие регулярные пары, ниже новые игроки, которые ищут партнёра.",
    "discover.regular.autoSlot": "Ближайший слот появится автоматически",
    "discover.regular.gameCreated": "Ближайшая игра создана · {time}",
    "discover.regular.slotConfirmed": "Слот подтверждён · {time}",
    "discover.regular.slotDeclined": "Этот слот не подошёл · {time}",
    "discover.regular.slotNeedsReply": "Нужен ответ по слоту · {time}",
    "discover.regular.scheduleUnknown": "Расписание уточняется",
    "discover.regular.open": "Открыть регулярку",
    "discover.regular.openGame": "Открыть игру",
    "discover.regular.checkSlot": "Проверить слот",
    "discover.respond.approved": "Тебя уже выбрали",
    "discover.respond.withdrawing": "Отзываем…",
    "discover.respond.withdraw": "Отменить отклик",
    "discover.respond.found": "Игрок уже найден",
    "discover.respond.sending": "Отправляем…",
    "discover.respond.action": "Откликнуться",
    "discover.respond.authTitle": "Подтверди email, чтобы откликнуться",
    "discover.respond.authText": "Так мы сможем показать организатору твой отклик, а тебе прислать ответ и открыть чат, если тебя выберут.",
    "discover.seeking.hotEmptyTitle": "Сейчас нет срочных поисков",
    "discover.seeking.emptyTitle": "Сейчас никто не ищет игру",
    "discover.seeking.hotEmptyText": "Когда у кого-то срывается игрок на сегодня или завтра, горячий поиск появится здесь.",
    "discover.seeking.emptyText": "Попроси игроков включить статус поиска игры или зайди позже.",
    "discover.seeking.duration": "{minutes} мин",
    "discover.seeking.search": "Поиск",
    "discover.seeking.lifecycle.ended": "Игра закончилась",
    "discover.seeking.lifecycle.inProgress": "Игра идет",
    "discover.seeking.lifecycle.started": "Игра началась",
    "discover.seeking.lifecycle.soon": "Скоро начнется",
    "discover.seeking.lifecycle.playersFound": "Игроки найдены",
    "discover.seeking.lifecycle.playerFound": "Игрок найден",
    "discover.seeking.lifecycle.recruiting": "В процессе набора",
    "discover.seeking.lifecycle.closed": "Закрыт",
    "discover.seeking.countdown.started": "уже началось",
    "discover.seeking.countdown.in": "через {value}",
    "discover.seeking.countdown.lessMinute": "меньше чем через минуту",
    "discover.seeking.rosterMany": "Собрано {approved} из {needed}",
    "discover.seeking.rosterConfirmed": "Игрок уже подтверждён",
    "discover.seeking.rosterOne": "Нужен 1 игрок",
    "discover.seeking.hotBookedTitle": "Нужен игрок на ближайшее время",
    "discover.seeking.hotTitle": "Быстрая игра на ближайшее время",
    "discover.seeking.regularTitle": "Ищет партнёра по расписанию",
    "discover.seeking.bioFallback": "Хочет быстро договориться и выйти на игру без долгой переписки.",
    "discover.seeking.start": "Старт",
    "discover.seeking.match": "Совпадение",
    "discover.seeking.lookingFor": "Сейчас ищет",
    "discover.seeking.why": "Почему в подборе",
    "discover.seeking.when": "Когда",
    "discover.seeking.place": "Место",
    "discover.seeking.placeBooked": "Место уже выбрано",
    "discover.seeking.placeLater": "Место подберут позже",
    "discover.seeking.roster": "Состав",
    "discover.seeking.target": "Ищет",
    "discover.seeking.ownLevelUnknown": "Свой уровень: не знаю",
    "discover.seeking.ownLevel": "Свой уровень: {level}",
    "discover.seeking.playersNeeded": "Нужно игроков: {count}",
    "discover.seeking.timeInChat": "Время уточнит в чате",
    "discover.swipe.matchFallback": "игрок",
    "discover.swipe.emptyTitle": "Карточки закончились",
    "discover.empty.seenAll.title": "Вы посмотрели всех",
    "discover.empty.sportAll": "Все · {count}",
    "discover.empty.why.searching": "ищут игру · {count}",
    "discover.empty.why.members": "{count} игроков отсюда",
    "discover.empty.why.rent": "корты в аренду",
    "discover.empty.allCourtsTile": "Все корты",
    "discover.empty.seenAll.text": "В городе {city} сейчас {count} анкет, и вы пролистали все. Появятся новые — напишем.",
    "discover.empty.firstHere.title": "Здесь вы первый",
    "discover.empty.firstHere.text": "В городе {city} пока нет подходящих игроков для показа. Можно позвать тех, с кем уже играете.",
    "discover.empty.courtsTitle": "Корты рядом",
    "discover.empty.allCourts": "Все корты",
    "discover.empty.invite.title": "Позовите, с кем уже играете",
    "discover.empty.invite.text": "Быстрее найти партнёра, если рядом есть свои.",
    "discover.empty.invite.share": "Отправить",
    "discover.empty.invite.copied": "Ссылка скопирована",
    "discover.empty.invite.stats": "Переходов {visits} · дошли до анкеты {joined}",
    "discover.empty.invite.shareText": "Играю в городе {city}, ищу партнёров. Присоединяйся:",
    "discover.empty.thin.title": "Игроков рядом мало",
    "discover.empty.thin.text": "Позовите знакомых — так город наполняется быстрее.",    "discover.swipe.emptyText": "Измени спорт в фильтрах или вернись позже, когда появятся новые игроки.",
    "discover.swipe.openMatches": "Открыть мэтчи",
    "discover.swipe.sportsCenters": "Спортивные центры",
    "discover.swipe.title": "Быстрый подбор",
    "discover.swipe.profileSports": "По видам спорта из профиля: {count}",
    "discover.swipe.remaining": "Осталось",
    "discover.swipe.skipStamp": "Пропуск",
    "discover.swipe.playStamp": "Можно играть",
    "discover.swipe.score": "Скор {score}",
    "discover.swipe.nearby": "Рядом",
    "discover.swipe.districtUnknown": "Район не указан",
    "discover.swipe.nextStep": "Следующий шаг",
    "discover.swipe.nextStepText": "Нажми «Можно поиграть», чтобы отправить интерес. Если интерес взаимный — откроется чат.",
    "discover.swipe.why": "Почему в подборе",
    "discover.swipe.reasonsSoon": "Скоро здесь появятся причины: спорт, уровень, расстояние и доступность.",
    "discover.swipe.bioFallback": "Готов(а) быстро договориться, выбрать центр и выйти на игру без длинной переписки.",
    "discover.swipe.play": "Можно поиграть",
    "discover.swipe.matchEyebrow": "Это мэтч",
    "discover.swipe.matchTitle": "У тебя взаимный интерес с {name}",
    "discover.swipe.matchText": "Теперь можно перейти в общий чат и договориться о деталях или сразу выбрать спортивный центр.",
    "discover.swipe.continue": "Продолжить поиск",
    "discover.swipe.openChat": "Открыть чат",
    "discover.swipe.authTitle": "Подтверди email, чтобы отправить интерес",
    "discover.swipe.authText": "Профиль уже собран. После подтверждения почты ты сможешь лайкать, открывать чат и получать ответ от игрока.",
    "discover.reason.sportLevel": "Совпадают спорт и уровень",
    "discover.reason.distance": "По расстоянию: {distance}",
    "discover.reason.availability": "По доступности: {value}",
    "discover.reason.sport": "Совпадает спорт: {sport}",
    "discover.reason.level": "Уровень рядом: {level}",
    "discover.reason.nearby": "Недалеко: {distance}",
    "discover.reason.sameArea": "Рядом по району",
    "discover.reason.schedule": "Пересекается расписание",
    "discover.distance.nearby": "рядом",
    "discover.distance.meters": "{value} м",
    "discover.distance.kilometers": "{value} км",
    "discover.upcoming.roster": "Состав: {count}",
    "discover.upcoming.title": "Подтвержденные игры",
    "discover.upcoming.regularText": "Этот слот по регулярной паре уже подтверждён. Если планы меняются, открой регулярку и скорректируй следующий слот.",
    "discover.upcoming.gameText": "Эта игра уже подтверждена. Открой детали игры или общий чат, если нужно уточнить последние детали.",
    "discover.upcoming.rosterChat": "Чат состава",
    "discover.upcoming.sharedChat": "Общий чат",
    "discover.label.day.monday": "Пн",
    "discover.label.day.tuesday": "Вт",
    "discover.label.day.wednesday": "Ср",
    "discover.label.day.thursday": "Чт",
    "discover.label.day.friday": "Пт",
    "discover.label.day.saturday": "Сб",
    "discover.label.day.sunday": "Вс",
    "discover.label.time.morning": "Утро",
    "discover.label.time.day": "День",
    "discover.label.time.evening": "Вечер",
    "discover.label.gender.male": "Мужской",
    "discover.label.gender.female": "Женский",
    "discover.label.gender.other": "Другой",
    "discover.label.format.singles": "Одиночная",
    "discover.label.format.doubles": "Парная",
    "discover.label.format.both": "Любой формат",
    "discover.label.surface.hard": "Хард",
    "discover.label.surface.clay": "Грунт",
    "discover.label.surface.grass": "Трава",
    "discover.label.surface.any": "Любое",
    "discover.label.hot.today": "Сегодня",
    "discover.label.hot.tomorrow": "Завтра",
    "discover.label.hot.day_after_tomorrow": "Послезавтра"
  }
);

export type DiscoverMessageKey = keyof (typeof discoverMessages)["en"];

export function translateDiscover(locale: SupportedLocale, key: DiscoverMessageKey, values?: WebTranslationValues) {
  return interpolateWebMessage(discoverMessages[locale][key], values);
}

export function translateDiscoverReason(locale: SupportedLocale, reason: string) {
  if (locale === "ru") return reason;

  const patterns: Array<[RegExp, DiscoverMessageKey, string]> = [
    [/^Совпадает спорт: (.+)$/, "discover.reason.sport", "sport"],
    [/^Уровень рядом: (.+)$/, "discover.reason.level", "level"],
    [/^Недалеко: (.+)$/, "discover.reason.nearby", "distance"],
    [/^По расстоянию: (.+)$/, "discover.reason.distance", "distance"],
    [/^По доступности: (.+)$/, "discover.reason.availability", "value"]
  ];

  if (reason === "Совпадают спорт и уровень") return translateDiscover(locale, "discover.reason.sportLevel");
  if (reason === "Рядом по району") return translateDiscover(locale, "discover.reason.sameArea");
  if (reason === "Пересекается расписание") return translateDiscover(locale, "discover.reason.schedule");

  for (const [pattern, key, valueKey] of patterns) {
    const match = reason.match(pattern);
    if (match?.[1]) {
      const value = valueKey === "sport"
        ? translateDiscoverSportValue(locale, match[1])
        : valueKey === "distance"
          ? translateDiscoverDistanceLabel(locale, match[1])
          : match[1];
      return translateDiscover(locale, key, { [valueKey]: value });
    }
  }

  return reason;
}

function translateDiscoverSportValue(locale: SupportedLocale, value: string) {
  const sport = SPORT_OPTIONS.find((option) => SPORT_LABELS[option] === value || option === value);
  return sport ? getAuthSportLabel(locale, sport) : value;
}

export function getDiscoverDayLabel(locale: SupportedLocale, value: string) {
  const key = `discover.label.day.${value}` as DiscoverMessageKey;
  return key in discoverMessages.en ? translateDiscover(locale, key) : value;
}

export function getDiscoverTimeLabel(locale: SupportedLocale, value: string) {
  const [day, time] = value.split("@");
  if (day && time) return `${getDiscoverDayLabel(locale, day)} ${time}`;
  const key = `discover.label.time.${value}` as DiscoverMessageKey;
  return key in discoverMessages.en ? translateDiscover(locale, key) : value;
}

export function getDiscoverGenderLabel(locale: SupportedLocale, value: "male" | "female" | "other") {
  return translateDiscover(locale, `discover.label.gender.${value}`);
}

export function getDiscoverFormatLabel(locale: SupportedLocale, value: "singles" | "doubles" | "both") {
  return translateDiscover(locale, `discover.label.format.${value}`);
}

export function getDiscoverSurfaceLabel(locale: SupportedLocale, value: "hard" | "clay" | "grass" | "any") {
  return translateDiscover(locale, `discover.label.surface.${value}`);
}

export function getDiscoverHotWindowLabel(
  locale: SupportedLocale,
  value: "today" | "tomorrow" | "day_after_tomorrow"
) {
  return translateDiscover(locale, `discover.label.hot.${value}`);
}

const DISCOVER_LIFECYCLE_KEYS = {
  "Игра закончилась": "discover.seeking.lifecycle.ended",
  "Игра идет": "discover.seeking.lifecycle.inProgress",
  "Игра началась": "discover.seeking.lifecycle.started",
  "Скоро начнется": "discover.seeking.lifecycle.soon",
  "Игроки найдены": "discover.seeking.lifecycle.playersFound",
  "Игрок найден": "discover.seeking.lifecycle.playerFound",
  "В процессе набора": "discover.seeking.lifecycle.recruiting",
  "Закрыт": "discover.seeking.lifecycle.closed",
  "Поиск": "discover.seeking.search"
} as const satisfies Record<string, DiscoverMessageKey>;

export function translateDiscoverLifecycleStatus(locale: SupportedLocale, status: string) {
  const key = DISCOVER_LIFECYCLE_KEYS[status as keyof typeof DISCOVER_LIFECYCLE_KEYS];
  return key ? translateDiscover(locale, key) : status;
}

export function formatDiscoverHotCountdown(
  locale: SupportedLocale,
  startsAt: string | Date | null | undefined
) {
  if (!startsAt) return null;
  const diffMs = new Date(startsAt).getTime() - Date.now();
  if (diffMs <= 0) return translateDiscover(locale, "discover.seeking.countdown.started");

  const totalMinutes = Math.floor(diffMs / 60000);
  const days = Math.floor(totalMinutes / (60 * 24));
  const hours = Math.floor((totalMinutes % (60 * 24)) / 60);
  const minutes = totalMinutes % 60;
  const units = new Intl.RelativeTimeFormat(locale, { numeric: "always", style: "narrow" });

  if (days > 0) return units.format(days, "day");
  if (hours > 0) return units.format(hours, "hour");
  if (minutes > 0) return units.format(minutes, "minute");
  return translateDiscover(locale, "discover.seeking.countdown.lessMinute");
}

export function formatDiscoverDistance(locale: SupportedLocale, distanceKm: number | null | undefined) {
  if (distanceKm == null || Number.isNaN(distanceKm)) {
    return translateDiscover(locale, "discover.distance.nearby");
  }
  if (distanceKm < 1) {
    return translateDiscover(locale, "discover.distance.meters", { value: Math.round(distanceKm * 1000) });
  }
  return translateDiscover(locale, "discover.distance.kilometers", {
    value: new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(distanceKm)
  });
}

export function translateDiscoverDistanceLabel(locale: SupportedLocale, label: string) {
  const normalized = label.trim().toLowerCase();
  if (normalized === "рядом" || normalized === "nearby") {
    return translateDiscover(locale, "discover.distance.nearby");
  }
  const meters = normalized.match(/^([\d.,]+)\s*(?:м|m)$/i);
  if (meters) {
    return translateDiscover(locale, "discover.distance.meters", { value: meters[1] });
  }
  const kilometers = normalized.match(/^([\d.,]+)\s*(?:км|km)$/i);
  if (kilometers) {
    const numeric = Number(kilometers[1].replace(",", "."));
    const value = Number.isFinite(numeric)
      ? new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(numeric)
      : kilometers[1];
    return translateDiscover(locale, "discover.distance.kilometers", { value });
  }
  return label;
}
