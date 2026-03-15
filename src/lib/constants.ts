export const SESSION_COOKIE = "tennis_session";
export const SESSION_TTL_DAYS = 14;
export const AUTH_CODE_TTL_MINUTES = 10;

export const CITY_PRESETS = {
  "Москва": { lat: 55.7558, lng: 37.6173 },
  Moscow: { lat: 55.7558, lng: 37.6173 },
  London: { lat: 51.5072, lng: -0.1276 },
  Berlin: { lat: 52.52, lng: 13.405 },
  Dubai: { lat: 25.2048, lng: 55.2708 },
  Barcelona: { lat: 41.3874, lng: 2.1686 },
  Tbilisi: { lat: 41.7151, lng: 44.8271 }
} as const;

export const DAY_OPTIONS = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday"
] as const;

export const DAY_LABELS = {
  monday: "Пн",
  tuesday: "Вт",
  wednesday: "Ср",
  thursday: "Чт",
  friday: "Пт",
  saturday: "Сб",
  sunday: "Вс"
} as const;

export const TIME_RANGE_OPTIONS = ["morning", "day", "evening"] as const;

export const TIME_RANGE_LABELS = {
  morning: "Утро",
  day: "День",
  evening: "Вечер"
} as const;

export const GENDER_LABELS = {
  male: "Мужской",
  female: "Женский",
  other: "Другой"
} as const;

export const PLAY_FORMAT_LABELS = {
  singles: "Одиночная",
  doubles: "Парная",
  both: "Любой формат"
} as const;

export const SURFACE_LABELS = {
  hard: "Хард",
  clay: "Грунт",
  grass: "Трава",
  any: "Любое"
} as const;

export const COURT_SETTING_LABELS = {
  indoor: "Крытый",
  outdoor: "Открытый"
} as const;

export const SPORT_OPTIONS = ["tennis", "padel", "badminton", "squash", "pickleball"] as const;

export const SPORT_LABELS = {
  tennis: "Теннис",
  padel: "Падел",
  badminton: "Бадминтон",
  squash: "Сквош",
  pickleball: "Пиклбол"
} as const;

export const GAME_SEARCH_TYPE_LABELS = {
  regular: "Обычный поиск",
  hot: "Горячий поиск"
} as const;

export const HOT_SEARCH_WINDOW_LABELS = {
  today: "На сегодня",
  tomorrow: "На завтра"
} as const;
