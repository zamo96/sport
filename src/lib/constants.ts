import type { Sport } from "@prisma/client";

export const SESSION_COOKIE = "tennis_session";
export const SESSION_TTL_DAYS = 14;
export const AUTH_CODE_TTL_MINUTES = 10;

export const DEFAULT_CITY = "Санкт-Петербург";
export const DEFAULT_CITY_COORDINATES = { lat: 59.9386, lng: 30.3141 } as const;
export const AVAILABLE_CITIES = [DEFAULT_CITY, "Москва"] as const;

export const CITY_PRESETS = {
  "Санкт-Петербург": DEFAULT_CITY_COORDINATES,
  "Санкт Петербург": DEFAULT_CITY_COORDINATES,
  "Saint Petersburg": DEFAULT_CITY_COORDINATES,
  "St. Petersburg": DEFAULT_CITY_COORDINATES,
  "Москва": { lat: 55.7558, lng: 37.6173 },
  "Moscow": { lat: 55.7558, lng: 37.6173 },
  "Казань": { lat: 55.7961, lng: 49.1064 },
  "Kazan": { lat: 55.7961, lng: 49.1064 }
} as const;

export const SAINT_PETERSBURG_DISTRICT_OPTIONS = [
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

export const MOSCOW_DISTRICT_OPTIONS = [
  "moscow_central",
  "moscow_northern",
  "moscow_northeastern",
  "moscow_eastern",
  "moscow_southeastern",
  "moscow_southern",
  "moscow_southwestern",
  "moscow_western",
  "moscow_northwestern",
  "moscow_zelenograd",
  "moscow_novomoskovsky",
  "moscow_troitsky",
] as const;

export const KAZAN_DISTRICT_OPTIONS = [
  "kazan_aviastroitelny",
  "kazan_vakhitovsky",
  "kazan_kirovsky",
  "kazan_moskovsky",
  "kazan_novo_savinovsky",
  "kazan_privolzhsky",
  "kazan_sovetsky",
] as const;

export const DISTRICT_OPTIONS = [
  ...SAINT_PETERSBURG_DISTRICT_OPTIONS,
  ...MOSCOW_DISTRICT_OPTIONS,
  ...KAZAN_DISTRICT_OPTIONS,
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
  moscow_central: "Центральный административный округ",
  moscow_northern: "Северный административный округ",
  moscow_northeastern: "Северо-Восточный административный округ",
  moscow_eastern: "Восточный административный округ",
  moscow_southeastern: "Юго-Восточный административный округ",
  moscow_southern: "Южный административный округ",
  moscow_southwestern: "Юго-Западный административный округ",
  moscow_western: "Западный административный округ",
  moscow_northwestern: "Северо-Западный административный округ",
  moscow_zelenograd: "Зеленоградский административный округ",
  moscow_novomoskovsky: "Новомосковский административный округ",
  moscow_troitsky: "Троицкий административный округ",
  kazan_aviastroitelny: "Авиастроительный",
  kazan_vakhitovsky: "Вахитовский",
  kazan_kirovsky: "Кировский",
  kazan_moskovsky: "Московский",
  kazan_novo_savinovsky: "Ново-Савиновский",
  kazan_privolzhsky: "Приволжский",
  kazan_sovetsky: "Советский",
};

type DistrictMapArea = {
  label: string;
  color: string;
  center: { lat: number; lng: number };
  polygon: [number, number][];
  searchHints: string[];
};

export const DISTRICT_MAP_AREAS: Record<string, DistrictMapArea> = {
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
  moscow_central: {
    label: DISTRICT_LABELS.moscow_central,
    color: "#24D68A",
    center: { lat: 55.7512, lng: 37.6244 },
    polygon: [
      [37.545, 55.795],
      [37.626, 55.805],
      [37.704, 55.775],
      [37.694, 55.713],
      [37.62, 55.695],
      [37.548, 55.724]
    ],
    searchHints: ["ЦАО", "центр Москвы", "Центральный административный округ"]
  },
  moscow_northern: {
    label: DISTRICT_LABELS.moscow_northern,
    color: "#24D68A",
    center: { lat: 55.8768, lng: 37.575 },
    polygon: [
      [37.455, 55.925],
      [37.545, 55.965],
      [37.665, 55.945],
      [37.704, 55.806],
      [37.626, 55.805],
      [37.545, 55.795],
      [37.475, 55.825]
    ],
    searchHints: ["САО", "Северный административный округ", "Динамо"]
  },
  moscow_northeastern: {
    label: DISTRICT_LABELS.moscow_northeastern,
    color: "#24D68A",
    center: { lat: 55.8582, lng: 37.7372 },
    polygon: [
      [37.665, 55.945],
      [37.835, 55.925],
      [37.85, 55.83],
      [37.704, 55.775],
      [37.704, 55.806]
    ],
    searchHints: ["СВАО", "Северо-Восточный административный округ", "ВДНХ"]
  },
  moscow_eastern: {
    label: DISTRICT_LABELS.moscow_eastern,
    color: "#24D68A",
    center: { lat: 55.7458, lng: 37.8427 },
    polygon: [
      [37.85, 55.83],
      [37.955, 55.82],
      [37.97, 55.705],
      [37.815, 55.675],
      [37.694, 55.713],
      [37.704, 55.775]
    ],
    searchHints: ["ВАО", "Восточный административный округ", "Измайлово"]
  },
  moscow_southeastern: {
    label: DISTRICT_LABELS.moscow_southeastern,
    color: "#24D68A",
    center: { lat: 55.6463, lng: 37.7367 },
    polygon: [
      [37.694, 55.713],
      [37.815, 55.675],
      [37.855, 55.585],
      [37.71, 55.565],
      [37.625, 55.65],
      [37.62, 55.695]
    ],
    searchHints: ["ЮВАО", "Юго-Восточный административный округ", "Люблино"]
  },
  moscow_southern: {
    label: DISTRICT_LABELS.moscow_southern,
    color: "#24D68A",
    center: { lat: 55.6138, lng: 37.5922 },
    polygon: [
      [37.62, 55.695],
      [37.625, 55.65],
      [37.71, 55.565],
      [37.65, 55.515],
      [37.5, 55.56],
      [37.515, 55.65],
      [37.548, 55.724]
    ],
    searchHints: ["ЮАО", "Южный административный округ", "Коломенская"]
  },
  moscow_southwestern: {
    label: DISTRICT_LABELS.moscow_southwestern,
    color: "#24D68A",
    center: { lat: 55.6563, lng: 37.4463 },
    polygon: [
      [37.548, 55.724],
      [37.515, 55.65],
      [37.5, 55.56],
      [37.355, 55.56],
      [37.35, 55.665],
      [37.455, 55.735]
    ],
    searchHints: ["ЮЗАО", "Юго-Западный административный округ", "Профсоюзная"]
  },
  moscow_western: {
    label: DISTRICT_LABELS.moscow_western,
    color: "#24D68A",
    center: { lat: 55.7418, lng: 37.3972 },
    polygon: [
      [37.455, 55.825],
      [37.545, 55.795],
      [37.548, 55.724],
      [37.455, 55.735],
      [37.35, 55.665],
      [37.26, 55.7],
      [37.285, 55.805]
    ],
    searchHints: ["ЗАО", "Западный административный округ", "Кунцево"]
  },
  moscow_northwestern: {
    label: DISTRICT_LABELS.moscow_northwestern,
    color: "#24D68A",
    center: { lat: 55.8711, lng: 37.3478 },
    polygon: [
      [37.285, 55.805],
      [37.455, 55.825],
      [37.455, 55.925],
      [37.315, 55.93],
      [37.235, 55.875]
    ],
    searchHints: ["СЗАО", "Северо-Западный административный округ", "Строгино"]
  },
  moscow_zelenograd: {
    label: DISTRICT_LABELS.moscow_zelenograd,
    color: "#24D68A",
    center: { lat: 55.986, lng: 37.2075 },
    polygon: [
      [37.13, 56.03],
      [37.27, 56.03],
      [37.285, 55.945],
      [37.145, 55.94]
    ],
    searchHints: ["Зеленоград", "Зеленоградский административный округ"]
  },
  moscow_novomoskovsky: {
    label: DISTRICT_LABELS.moscow_novomoskovsky,
    color: "#24D68A",
    center: { lat: 55.5617, lng: 37.3433 },
    polygon: [
      [37.26, 55.7],
      [37.35, 55.665],
      [37.355, 55.56],
      [37.5, 55.56],
      [37.41, 55.425],
      [37.185, 55.465]
    ],
    searchHints: ["НАО", "Новомосковский административный округ", "Новая Москва"]
  },
  moscow_troitsky: {
    label: DISTRICT_LABELS.moscow_troitsky,
    color: "#24D68A",
    center: { lat: 55.3583, lng: 37.092 },
    polygon: [
      [37.185, 55.465],
      [37.41, 55.425],
      [37.345, 55.23],
      [36.815, 55.22],
      [36.905, 55.455]
    ],
    searchHints: ["ТАО", "Троицкий административный округ", "Троицк"]
  },
  kazan_aviastroitelny: {
    label: DISTRICT_LABELS.kazan_aviastroitelny,
    color: "#24D68A",
    center: { lat: 55.881, lng: 49.117 },
    polygon: [
      [49.045, 55.925],
      [49.205, 55.925],
      [49.205, 55.855],
      [49.105, 55.835],
      [49.025, 55.865]
    ],
    searchHints: ["Авиастроительный", "Авиастрой", "Северный вокзал"]
  },
  kazan_vakhitovsky: {
    label: DISTRICT_LABELS.kazan_vakhitovsky,
    color: "#24D68A",
    center: { lat: 55.778, lng: 49.12 },
    polygon: [
      [49.06, 55.815],
      [49.145, 55.825],
      [49.195, 55.77],
      [49.145, 55.73],
      [49.055, 55.75]
    ],
    searchHints: ["Вахитовский", "центр Казани", "Кремль"]
  },
  kazan_kirovsky: {
    label: DISTRICT_LABELS.kazan_kirovsky,
    color: "#24D68A",
    center: { lat: 55.808, lng: 48.91 },
    polygon: [
      [48.825, 55.9],
      [49.025, 55.865],
      [49.06, 55.815],
      [49.055, 55.75],
      [48.865, 55.73],
      [48.765, 55.815]
    ],
    searchHints: ["Кировский", "Адмиралтейская слобода"]
  },
  kazan_moskovsky: {
    label: DISTRICT_LABELS.kazan_moskovsky,
    color: "#24D68A",
    center: { lat: 55.828, lng: 49.049 },
    polygon: [
      [49.025, 55.865],
      [49.105, 55.835],
      [49.12, 55.795],
      [49.06, 55.815],
      [48.93, 55.825]
    ],
    searchHints: ["Московский район Казани", "Яшьлек"]
  },
  kazan_novo_savinovsky: {
    label: DISTRICT_LABELS.kazan_novo_savinovsky,
    color: "#24D68A",
    center: { lat: 55.813, lng: 49.208 },
    polygon: [
      [49.105, 55.835],
      [49.245, 55.85],
      [49.26, 55.785],
      [49.195, 55.77],
      [49.145, 55.825]
    ],
    searchHints: ["Ново-Савиновский", "Козья слобода", "Чаша"]
  },
  kazan_privolzhsky: {
    label: DISTRICT_LABELS.kazan_privolzhsky,
    color: "#24D68A",
    center: { lat: 55.681, lng: 49.064 },
    polygon: [
      [49.055, 55.75],
      [49.145, 55.73],
      [49.25, 55.655],
      [49.145, 55.585],
      [48.93, 55.64],
      [48.865, 55.73]
    ],
    searchHints: ["Приволжский", "Горки", "Дубравная"]
  },
  kazan_sovetsky: {
    label: DISTRICT_LABELS.kazan_sovetsky,
    color: "#24D68A",
    center: { lat: 55.724, lng: 49.27 },
    polygon: [
      [49.195, 55.77],
      [49.26, 55.785],
      [49.385, 55.775],
      [49.41, 55.65],
      [49.25, 55.655],
      [49.145, 55.73]
    ],
    searchHints: ["Советский", "Азино", "Проспект Победы"]
  },
};

export const DISTRICT_SEARCH_HINTS = Object.values(DISTRICT_MAP_AREAS).flatMap((district) => district.searchHints);

export function isDistrictOption(value: string | null | undefined): value is DistrictOption {
  return typeof value === "string" && DISTRICT_OPTIONS.includes(value as DistrictOption);
}

export function getDistrictArea(district: string | null | undefined) {
  return isDistrictOption(district) ? DISTRICT_MAP_AREAS[district] ?? null : null;
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

/** Радиус круга и подписи на карте кортов. Раньше брался из настройки игрока,
 *  которую убрали: город и районы задают охват точнее, чем километры. */
export const COURTS_MAP_RADIUS_KM = 20;

export const TIME_RANGE_OPTIONS = ["morning", "day", "evening"] as const;

export const TIME_RANGE_LABELS = {
  morning: "Утро",
  day: "День",
  evening: "Вечер"
} as const;

export function getTimePreferenceLabel(value: string) {
  const [day, time] = value.split("@");
  if (day && time && day in DAY_LABELS) {
    return `${DAY_LABELS[day as keyof typeof DAY_LABELS]} ${time}`;
  }

  return TIME_RANGE_LABELS[value as keyof typeof TIME_RANGE_LABELS] ?? value;
}

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
  "football",
  "running",
  "supboard"
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
  football: "Футбол",
  running: "Бег",
  supboard: "Сапборд"
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
  football: "⚽",
  running: "🏃",
  supboard: "🏄"
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
  },
  running: {
    centerLabel: "Маршрут или место старта",
    anyCenterLabel: "Любой маршрут",
    bookedTitle: "Маршрут уже выбран",
    bookedHint: "Включи, если маршрут уже понятен и нужен партнёр на пробежку.",
    regularPlaceholder: "Ищу партнёра для регулярных пробежек в удобное время.",
    hotPlaceholder: "Ищу партнёра на пробежку сегодня. Маршрут укажу в описании."
  },
  supboard: {
    centerLabel: "Маршрут или место старта",
    anyCenterLabel: "Любой маршрут",
    bookedTitle: "Маршрут уже выбран",
    bookedHint: "Включи, если маршрут по воде уже понятен и нужен партнёр.",
    regularPlaceholder: "Ищу партнёра для прогулок на сапборде в удобное время.",
    hotPlaceholder: "Ищу партнёра на сапборд сегодня. Маршрут укажу на карте."
  }
};

export const GAME_SEARCH_TYPE_LABELS = {
  regular: "Регулярный поиск",
  hot: "Горячий поиск"
} as const;

export const HOT_SEARCH_WINDOW_LABELS = {
  today: "На сегодня",
  tomorrow: "На завтра",
  day_after_tomorrow: "На послезавтра"
} as const;
