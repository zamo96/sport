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

export const SPORT_SEARCH_LABELS: Record<
  Sport,
  {
    centerLabel: string;
    anyCenterLabel: string;
    bookedTitle: string;
    bookedHint: string;
    regularPlaceholder: string;
    hotPlaceholder: string;
  }
> = {
  table_tennis: {
    centerLabel: "Клуб или стол",
    anyCenterLabel: "Любой клуб или стол",
    bookedTitle: "Стол уже забронирован",
    bookedHint: "Включи, если стол или клуб уже выбран и нужен только соперник.",
    regularPlaceholder: "Ищу партнера по настольному теннису после работы.",
    hotPlaceholder: "Игрок сорвался, стол уже забронирован, нужен партнер срочно."
  },
  tennis: {
    centerLabel: "Корт или клуб",
    anyCenterLabel: "Любой корт или клуб",
    bookedTitle: "Корт уже есть",
    bookedHint: "Включи, если корт уже найден или забронирован и нужен только игрок.",
    regularPlaceholder: "Ищу быструю игру в теннис после работы.",
    hotPlaceholder: "Игрок сорвался, корт забронирован, нужен партнер примерно моего уровня."
  },
  padel: {
    centerLabel: "Падел-корт",
    anyCenterLabel: "Любой падел-клуб",
    bookedTitle: "Корт уже есть",
    bookedHint: "Включи, если падел-корт уже найден и нужен только партнер.",
    regularPlaceholder: "Ищу партнера в падел на вечер или выходные.",
    hotPlaceholder: "Партнер сорвался, падел-корт уже забронирован, нужен игрок срочно."
  },
  squash: {
    centerLabel: "Сквош-корт",
    anyCenterLabel: "Любой сквош-центр",
    bookedTitle: "Корт уже есть",
    bookedHint: "Включи, если сквош-корт уже подтвержден и нужен только соперник.",
    regularPlaceholder: "Ищу партнера в сквош на регулярной основе.",
    hotPlaceholder: "Сквош-корт уже забронирован, нужен игрок на замену."
  },
  badminton: {
    centerLabel: "Площадка или центр",
    anyCenterLabel: "Любой центр для бадминтона",
    bookedTitle: "Площадка уже есть",
    bookedHint: "Включи, если площадка уже выбрана и нужен только партнер.",
    regularPlaceholder: "Ищу партнера по бадминтону на вечер.",
    hotPlaceholder: "Площадка для бадминтона уже забронирована, нужен партнер срочно."
  },
  volleyball: {
    centerLabel: "Площадка или центр",
    anyCenterLabel: "Любая площадка",
    bookedTitle: "Площадка уже есть",
    bookedHint: "Включи, если волейбольная площадка уже забронирована.",
    regularPlaceholder: "Ищу игроков на волейбол в удобное время.",
    hotPlaceholder: "Нужно срочно добрать игрока, площадка уже забронирована."
  },
  fitness: {
    centerLabel: "Спортзал или центр",
    anyCenterLabel: "Любой спортзал",
    bookedTitle: "Зал уже выбран",
    bookedHint: "Включи, если зал уже выбран и нужен партнер на совместную тренировку.",
    regularPlaceholder: "Ищу партнера для совместной тренировки в зале.",
    hotPlaceholder: "Окно в зале уже забронировано, нужен партнер срочно."
  },
  boxing: {
    centerLabel: "Зал или ринг",
    anyCenterLabel: "Любой зал",
    bookedTitle: "Ринг уже забронирован",
    bookedHint: "Включи, если зал или ринг уже забронирован и нужен спарринг-партнер.",
    regularPlaceholder: "Ищу партнера на бокс или техничную работу в парах.",
    hotPlaceholder: "Спарринг сорвался, зал уже забронирован, нужен партнер срочно."
  },
  yoga: {
    centerLabel: "Студия или центр",
    anyCenterLabel: "Любая студия",
    bookedTitle: "Студия уже выбрана",
    bookedHint: "Включи, если студия уже выбрана и нужен партнер на совместную практику.",
    regularPlaceholder: "Ищу партнера для совместной йоги или стрейчинга.",
    hotPlaceholder: "Есть бронь в студии, нужен партнер на практику."
  },
  football: {
    centerLabel: "Поле или центр",
    anyCenterLabel: "Любое футбольное поле",
    bookedTitle: "Поле уже забронировано",
    bookedHint: "Включи, если аренда футбольного поля уже подтверждена.",
    regularPlaceholder: "Ищу игроков на футбол в удобное время.",
    hotPlaceholder: "Игрок сорвался, аренда поля уже оплачена, нужен человек срочно."
  }
};

export const GAME_SEARCH_TYPE_LABELS = {
  regular: "Обычный поиск",
  hot: "Горячий поиск"
} as const;

export const HOT_SEARCH_WINDOW_LABELS = {
  today: "На сегодня",
  tomorrow: "На завтра"
} as const;
