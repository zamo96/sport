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

export const DISTRICT_OPTIONS = [
  "admiralteysky",
  "vasileostrovsky",
  "vyborgsky",
  "kalininsky",
  "kirovsky",
  "kolpinsky",
  "krasnogvardeysky",
  "krasnoselsky",
  "kronshtadtsky",
  "kurortny",
  "moskovsky",
  "nevsky",
  "petrogradsky",
  "petrodvortsovy",
  "primorsky",
  "pushkinsky",
  "frunzensky",
  "central",
] as const;

export type DistrictOption = (typeof DISTRICT_OPTIONS)[number];

export const DISTRICT_LABELS: Record<DistrictOption, string> = {
  admiralteysky: "Адмиралтейский",
  vasileostrovsky: "Василеостровский",
  vyborgsky: "Выборгский",
  kalininsky: "Калининский",
  kirovsky: "Кировский",
  kolpinsky: "Колпинский",
  krasnogvardeysky: "Красногвардейский",
  krasnoselsky: "Красносельский",
  kronshtadtsky: "Кронштадтский",
  kurortny: "Курортный",
  moskovsky: "Московский",
  nevsky: "Невский",
  petrogradsky: "Петроградский",
  petrodvortsovy: "Петродворцовый",
  primorsky: "Приморский",
  pushkinsky: "Пушкинский",
  frunzensky: "Фрунзенский",
  central: "Центральный",
};

export const DISTRICT_MAP_AREAS: Record<
  DistrictOption,
  {
    label: string;
    color: string;
    center: { lat: number; lng: number };
    polygon: [number, number][];
    searchHints: string[];
  }
> = {
  admiralteysky: {
    label: DISTRICT_LABELS.admiralteysky,
    color: "#855D4E",
    center: { lat: 59.9192, lng: 30.2857 },
    polygon: [
      [30.218, 59.939],
      [30.334, 59.939],
      [30.338, 59.894],
      [30.225, 59.895]
    ],
    searchHints: ["Адмиралтейский", "Технологический институт", "Балтийская"]
  },
  vasileostrovsky: {
    label: DISTRICT_LABELS.vasileostrovsky,
    color: "#7B61FF",
    center: { lat: 59.9432, lng: 30.2492 },
    polygon: [
      [30.19, 59.962],
      [30.276, 59.962],
      [30.292, 59.925],
      [30.205, 59.913]
    ],
    searchHints: ["Васька", "Приморская", "Василеостровский"]
  },
  vyborgsky: {
    label: DISTRICT_LABELS.vyborgsky,
    color: "#4B7BE5",
    center: { lat: 60.042, lng: 30.333 },
    polygon: [
      [30.205, 60.105],
      [30.435, 60.105],
      [30.43, 60.01],
      [30.235, 60.002]
    ],
    searchHints: ["Выборгский", "Озерки", "Проспект Просвещения"]
  },
  kalininsky: {
    label: DISTRICT_LABELS.kalininsky,
    color: "#23A27A",
    center: { lat: 60.0121, lng: 30.4041 },
    polygon: [
      [30.292, 60.055],
      [30.497, 60.055],
      [30.478, 59.982],
      [30.32, 59.982]
    ],
    searchHints: ["Калининский", "Академическая", "Гражданка"]
  },
  kirovsky: {
    label: DISTRICT_LABELS.kirovsky,
    color: "#A8663A",
    center: { lat: 59.877, lng: 30.258 },
    polygon: [
      [30.142, 59.918],
      [30.301, 59.918],
      [30.305, 59.833],
      [30.16, 59.83]
    ],
    searchHints: ["Кировский", "Нарвская", "Ленинский проспект"]
  },
  kolpinsky: {
    label: DISTRICT_LABELS.kolpinsky,
    color: "#B47BDA",
    center: { lat: 59.744, lng: 30.595 },
    polygon: [
      [30.46, 59.815],
      [30.72, 59.815],
      [30.74, 59.665],
      [30.49, 59.665]
    ],
    searchHints: ["Колпино", "Колпинский", "Понтонный"]
  },
  krasnogvardeysky: {
    label: DISTRICT_LABELS.krasnogvardeysky,
    color: "#B86482",
    center: { lat: 59.965, lng: 30.448 },
    polygon: [
      [30.345, 59.995],
      [30.535, 59.995],
      [30.54, 59.91],
      [30.36, 59.91]
    ],
    searchHints: ["Красногвардейский", "Ладожская", "Новочеркасская"]
  },
  krasnoselsky: {
    label: DISTRICT_LABELS.krasnoselsky,
    color: "#D98B5C",
    center: { lat: 59.826, lng: 30.167 },
    polygon: [
      [29.98, 59.885],
      [30.265, 59.885],
      [30.27, 59.73],
      [30.03, 59.73]
    ],
    searchHints: ["Красносельский", "Юго-Запад", "Солнечный город"]
  },
  kronshtadtsky: {
    label: DISTRICT_LABELS.kronshtadtsky,
    color: "#4A92A2",
    center: { lat: 59.995, lng: 29.775 },
    polygon: [
      [29.62, 60.06],
      [29.93, 60.06],
      [29.93, 59.92],
      [29.62, 59.92]
    ],
    searchHints: ["Кронштадт", "Кронштадтский", "остров Котлин"]
  },
  kurortny: {
    label: DISTRICT_LABELS.kurortny,
    color: "#4B9E8E",
    center: { lat: 60.158, lng: 29.945 },
    polygon: [
      [29.72, 60.31],
      [30.15, 60.31],
      [30.19, 60.08],
      [29.78, 60.02]
    ],
    searchHints: ["Курортный", "Сестрорецк", "Зеленогорск"]
  },
  moskovsky: {
    label: DISTRICT_LABELS.moskovsky,
    color: "#E7A938",
    center: { lat: 59.8553, lng: 30.3215 },
    polygon: [
      [30.25, 59.89],
      [30.385, 59.89],
      [30.392, 59.825],
      [30.265, 59.81]
    ],
    searchHints: ["Московский", "Парк Победы", "Московская"]
  },
  nevsky: {
    label: DISTRICT_LABELS.nevsky,
    color: "#E85B7B",
    center: { lat: 59.8964, lng: 30.4724 },
    polygon: [
      [30.368, 59.926],
      [30.57, 59.926],
      [30.585, 59.848],
      [30.39, 59.84]
    ],
    searchHints: ["Невский район", "Проспект Большевиков", "Ломоносовская"]
  },
  petrogradsky: {
    label: DISTRICT_LABELS.petrogradsky,
    color: "#2F7A65",
    center: { lat: 59.9669, lng: 30.3045 },
    polygon: [
      [30.233, 59.983],
      [30.332, 59.983],
      [30.343, 59.948],
      [30.251, 59.942]
    ],
    searchHints: ["Петроградка", "Крестовский", "Чкаловская"]
  },
  petrodvortsovy: {
    label: DISTRICT_LABELS.petrodvortsovy,
    color: "#9B7A45",
    center: { lat: 59.879, lng: 29.915 },
    polygon: [
      [29.63, 59.95],
      [30.15, 59.95],
      [30.14, 59.78],
      [29.67, 59.78]
    ],
    searchHints: ["Петергоф", "Стрельна", "Петродворцовый"]
  },
  primorsky: {
    label: DISTRICT_LABELS.primorsky,
    color: "#548BFF",
    center: { lat: 59.993, lng: 30.2398 },
    polygon: [
      [30.153, 60.04],
      [30.318, 60.04],
      [30.339, 59.982],
      [30.205, 59.956]
    ],
    searchHints: ["Приморский", "Старая Деревня", "Комендантский"]
  },
  pushkinsky: {
    label: DISTRICT_LABELS.pushkinsky,
    color: "#8C9A4F",
    center: { lat: 59.716, lng: 30.408 },
    polygon: [
      [30.17, 59.79],
      [30.62, 59.79],
      [30.63, 59.57],
      [30.22, 59.57]
    ],
    searchHints: ["Пушкин", "Шушары", "Царское Село"]
  },
  frunzensky: {
    label: DISTRICT_LABELS.frunzensky,
    color: "#C76A5E",
    center: { lat: 59.868, lng: 30.384 },
    polygon: [
      [30.28, 59.91],
      [30.46, 59.91],
      [30.46, 59.81],
      [30.29, 59.81]
    ],
    searchHints: ["Фрунзенский", "Купчино", "Международная"]
  },
  central: {
    label: DISTRICT_LABELS.central,
    color: "#D96A47",
    center: { lat: 59.9315, lng: 30.3609 },
    polygon: [
      [30.314, 59.948],
      [30.402, 59.948],
      [30.412, 59.917],
      [30.33, 59.907],
      [30.302, 59.924]
    ],
    searchHints: ["Лиговский", "Чернышевская", "поближе к центру"]
  },
};

export const DISTRICT_SEARCH_HINTS = Object.values(DISTRICT_MAP_AREAS).flatMap((district) => district.searchHints);

export function isDistrictOption(value: string | null | undefined): value is DistrictOption {
  return typeof value === "string" && DISTRICT_OPTIONS.includes(value as DistrictOption);
}

export function getDistrictArea(district: string | null | undefined) {
  return isDistrictOption(district) ? DISTRICT_MAP_AREAS[district] : null;
}

export function getDistrictLabel(district: string | null | undefined) {
  return isDistrictOption(district) ? DISTRICT_LABELS[district] : null;
}

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
  tomorrow: "На завтра",
  day_after_tomorrow: "На послезавтра"
} as const;
