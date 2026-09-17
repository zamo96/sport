import { defineWebMessages, interpolateWebMessage, type WebTranslationValues } from "@/lib/i18n/web/define";
import type { SupportedLocale } from "@/lib/locales";

export const courtsMessages = defineWebMessages(
  {
    "courts.page.eyebrow": "Sports venues",
    "courts.page.title": "Choose a venue before you start chatting.",
    "courts.page.subtitle": "Browse sports venues in your selected city and nearby. Search suggests clubs and districts as you type.",
    "courts.browser.eyebrow": "Sports venues",
    "courts.browser.description": "Clubs and venues for your selected city. The map is ready right away, and search suggests options as you type.",
    "courts.browser.found": "Found: {count}",
    "courts.browser.radius": "Radius",
    "courts.search.placeholder": "Search by club, district, metro station, or sport",
    "courts.suggestions.title": "Suggestions",
    "courts.suggestions.empty": "No suggestions yet. Try a district or club name.",
    "courts.suggestion.type.club": "Club",
    "courts.suggestion.type.metro": "Metro",
    "courts.suggestion.type.district": "District",
    "courts.suggestion.type.sport": "Sport",
    "courts.alphabet.jump": "Go to clubs starting with {letter}",
    "courts.empty.title": "No matching venues yet",
    "courts.empty.body": "Try clearing the search or choosing a different sport.",
    "courts.card.metro": "Metro",
    "courts.card.distance": "Distance",
    "courts.card.rating": "Rating {rating}",
    "courts.card.about": "About the club",
    "courts.card.hours": "Hours",
    "courts.card.phone": "Phone",
    "courts.card.website": "Club website",
    "courts.card.booking": "Book",
    "courts.card.messenger": "Messenger",
    "courts.card.messenger.max": "MAX",
    "courts.card.map": "View on map",
    "courts.card.propose": "Propose a game here",
    "courts.card.hideDetails": "Hide details",
    "courts.card.showDetails": "About this club",
    "courts.backToTop": "Back to top",
    "courts.map.label": "Sports venues map",
    "courts.map.loading": "Loading the map…",
    "courts.map.disabled": "The map is disabled. Set `NEXT_PUBLIC_MAP_PROVIDER=yandex` and `NEXT_PUBLIC_YANDEX_MAPS_API_KEY` to enable Yandex Maps.",
    "courts.map.apiKeyError": "Add `NEXT_PUBLIC_YANDEX_MAPS_API_KEY` to enable the map.",
    "courts.map.loadError": "Could not load Yandex Maps.",
    "courts.distance.nearby": "Nearby",
    "courts.distance.meters": "{value} m",
    "courts.distance.kilometers": "{value} km",
    "courts.count.venue.one": "{count} venue",
    "courts.count.venue.few": "{count} venues",
    "courts.count.venue.many": "{count} venues"
  },
  {
    "courts.page.eyebrow": "Спортивные центры",
    "courts.page.title": "Выбери место до начала переписки.",
    "courts.page.subtitle": "Спортивные центры в выбранном городе и поблизости. Поиск подсказывает клубы и районы сразу при вводе.",
    "courts.browser.eyebrow": "Спортивные центры",
    "courts.browser.description": "Клубы и площадки для выбранного города. Карта видна сразу, а поиск подсказывает варианты по мере ввода.",
    "courts.browser.found": "Найдено: {count}",
    "courts.browser.radius": "Радиус",
    "courts.search.placeholder": "Клуб, район, метро или вид спорта",
    "courts.suggestions.title": "Подсказки",
    "courts.suggestions.empty": "Ничего не подсказали, попробуй район или название клуба.",
    "courts.suggestion.type.club": "Клуб",
    "courts.suggestion.type.metro": "Метро",
    "courts.suggestion.type.district": "Район",
    "courts.suggestion.type.sport": "Спорт",
    "courts.alphabet.jump": "Перейти к клубам на {letter}",
    "courts.empty.title": "Подходящих центров пока нет",
    "courts.empty.body": "Попробуй убрать текст запроса или сменить вид спорта.",
    "courts.card.metro": "Метро",
    "courts.card.distance": "Расстояние",
    "courts.card.rating": "Рейтинг {rating}",
    "courts.card.about": "О клубе",
    "courts.card.hours": "Часы",
    "courts.card.phone": "Телефон",
    "courts.card.website": "Сайт клуба",
    "courts.card.booking": "Бронирование",
    "courts.card.messenger": "Мессенджер",
    "courts.card.messenger.max": "МАКС",
    "courts.card.map": "На карте",
    "courts.card.propose": "Предложить игру здесь",
    "courts.card.hideDetails": "Скрыть детали",
    "courts.card.showDetails": "Подробнее о клубе",
    "courts.backToTop": "Вернуться наверх",
    "courts.map.label": "Карта спортивных центров",
    "courts.map.loading": "Загружаем карту…",
    "courts.map.disabled": "Карта отключена. Укажи `NEXT_PUBLIC_MAP_PROVIDER=yandex` и `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`, чтобы включить Яндекс Карты.",
    "courts.map.apiKeyError": "Добавь `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`, чтобы включить карту.",
    "courts.map.loadError": "Не удалось загрузить Яндекс Карты.",
    "courts.distance.nearby": "Рядом",
    "courts.distance.meters": "{value} м",
    "courts.distance.kilometers": "{value} км",
    "courts.count.venue.one": "{count} центр",
    "courts.count.venue.few": "{count} центра",
    "courts.count.venue.many": "{count} центров"
  }
);

export type CourtsMessageKey = keyof (typeof courtsMessages)["en"];

export function translateCourts(
  locale: SupportedLocale,
  key: CourtsMessageKey,
  values?: WebTranslationValues
) {
  return interpolateWebMessage(courtsMessages[locale][key], values);
}

export function formatCourtsVenueCount(locale: SupportedLocale, count: number) {
  const pluralCategory = new Intl.PluralRules(locale).select(count);
  const suffix = pluralCategory === "one" ? "one" : pluralCategory === "few" ? "few" : "many";

  return translateCourts(locale, `courts.count.venue.${suffix}`, { count });
}

export function formatCourtsDistance(locale: SupportedLocale, distanceKm: number | null | undefined) {
  if (distanceKm == null || Number.isNaN(distanceKm)) {
    return translateCourts(locale, "courts.distance.nearby");
  }

  if (distanceKm < 1) {
    return translateCourts(locale, "courts.distance.meters", {
      value: Math.round(distanceKm * 1000)
    });
  }

  return translateCourts(locale, "courts.distance.kilometers", {
    value: new Intl.NumberFormat(locale, {
      minimumFractionDigits: 1,
      maximumFractionDigits: 1
    }).format(distanceKm)
  });
}

export function formatCourtsRadius(locale: SupportedLocale, radiusKm: number) {
  return translateCourts(locale, "courts.distance.kilometers", {
    value: new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(radiusKm)
  });
}
