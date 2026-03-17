import type { Sport } from "@prisma/client";

export const SESSION_COOKIE = "tennis_session";
export const SESSION_TTL_DAYS = 14;
export const AUTH_CODE_TTL_MINUTES = 10;

export const DEFAULT_CITY = "Санкт-Петербург";
export const DEFAULT_CITY_COORDINATES = { lat: 59.9386, lng: 30.3141 } as const;
export const AVAILABLE_CITIES = [DEFAULT_CITY] as const;

export const CITY_PRESETS = {
  "Санкт-Петербург": DEFAULT_CITY_COORDINATES,
  "Санкт Петербург": DEFAULT_CITY_COORDINATES,
  "Saint Petersburg": DEFAULT_CITY_COORDINATES,
  "St. Petersburg": DEFAULT_CITY_COORDINATES
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

export const SPORT_OPTIONS = [
  "table_tennis",
  "tennis",
  "padel",
  "squash",
  "badminton",
  "volleyball",
  "fitness",
  "boxing",
  "yoga",
  "football"
] as const satisfies readonly Sport[];

export const SPORT_LABELS = {
  table_tennis: "Настольный теннис",
  tennis: "Большой теннис",
  padel: "Падел",
  squash: "Сквош",
  badminton: "Бадминтон",
  volleyball: "Волейбол",
  fitness: "Фитнесс (Спортзал)",
  boxing: "Бокс",
  yoga: "Йога",
  football: "Футбол"
} as const;

export const SPORT_EMOJIS: Record<Sport, string> = {
  table_tennis: "🏓",
  tennis: "🎾",
  padel: "🥎",
  squash: "🟠",
  badminton: "🏸",
  volleyball: "🏐",
  fitness: "🏋️",
  boxing: "🥊",
  yoga: "🧘",
  football: "⚽"
};

export const GAME_SEARCH_TYPE_LABELS = {
  regular: "Обычный поиск",
  hot: "Горячий поиск"
} as const;

export const HOT_SEARCH_WINDOW_LABELS = {
  today: "На сегодня",
  tomorrow: "На завтра"
} as const;
