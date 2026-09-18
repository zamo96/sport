import { HotSearchWindow, type GameSearchStatus, type GameSearchType } from "@prisma/client";

import { DAY_OPTIONS } from "@/lib/constants";
import { formatLocalTime, getLocalDateParts, getLocalWeekdayKey, localDateTimeToUtc } from "@/lib/timezone";

const DAY_MAP = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] as const;

function windowOffsetDays(hotWindow?: HotSearchWindow | null) {
  if (hotWindow === "tomorrow") {
    return 1;
  }

  if (hotWindow === "day_after_tomorrow") {
    return 2;
  }

  return 0;
}

export function resolveSearchDays(
  searchType: GameSearchType,
  preferredDays: string[],
  hotWindow?: HotSearchWindow | null,
  hotStartsAt?: Date | null,
  timezone?: string | null
) {
  if (searchType !== "hot") {
    return preferredDays;
  }

  const base = hotStartsAt ? new Date(hotStartsAt) : new Date();
  const parts = getLocalDateParts(timezone, base);
  // День недели считаем в календаре игрока: сервер живёт в UTC, и под вечер
  // его дата уже не совпадает с той, что человек видит у себя.
  const local = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + windowOffsetDays(hotWindow)));
  const resolvedDay = DAY_MAP[local.getUTCDay()];

  return DAY_OPTIONS.includes(resolvedDay) ? [resolvedDay] : [];
}

/**
 * «Сегодня в 9:00» — это девять утра у игрока, а не на сервере. Контейнер
 * работает в UTC, поэтому прежний `setHours` сдвигал время на смещение зоны:
 * выбранные 9:00 сохранялись как 12:00 по Москве.
 */
export function resolveHotSearchStartAt(hotWindow: HotSearchWindow, time: string, timezone?: string | null) {
  const [hoursString, minutesString] = time.split(":");
  const hours = Number(hoursString);
  const minutes = Number(minutesString);

  if (!Number.isInteger(hours) || !Number.isInteger(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
    return null;
  }

  const parts = getLocalDateParts(timezone, new Date());

  return localDateTimeToUtc(
    timezone,
    parts.year,
    parts.month,
    parts.day + windowOffsetDays(hotWindow),
    hours,
    minutes
  );
}

const DAY_ORDER = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

/**
 * Недельное расписание регулярной пары из выбранных слотов. И день, и час
 * берутся в зоне пары: подпись «monday@19:00» потом разбирают обратно в момент
 * времени, и если писать её в зоне сервера, слот уезжает на смещение зоны.
 *
 * Раньше эта функция была скопирована в трёх роутах, и починка одной копии
 * разводила их между собой.
 */
export function buildWeeklySchedule(
  options: Array<{ scheduledAt: Date | string }>,
  timezone?: string | null
) {
  const days = new Set<string>();
  const timePreferences = new Set<string>();

  for (const option of options) {
    const date = option.scheduledAt instanceof Date ? option.scheduledAt : new Date(option.scheduledAt);

    if (Number.isNaN(date.getTime())) {
      continue;
    }

    const day = getLocalWeekdayKey(timezone, date);
    days.add(day);
    timePreferences.add(`${day}@${formatLocalTime(timezone, date)}`);
  }

  return {
    preferredDays: DAY_ORDER.filter((day) => days.has(day)),
    preferredTimeRanges: Array.from(timePreferences).sort((left, right) => {
      const [leftDay, leftTime] = left.split("@");
      const [rightDay, rightTime] = right.split("@");
      const dayDiff = DAY_ORDER.indexOf(leftDay) - DAY_ORDER.indexOf(rightDay);
      return dayDiff || (leftTime ?? "").localeCompare(rightTime ?? "");
    })
  };
}

export function isExpiredHotSearch(startsAt: string | Date | null | undefined) {
  if (!startsAt) {
    return false;
  }

  return new Date(startsAt).getTime() <= Date.now();
}

export function canAcceptGameSearchResponse(search: { isActive: boolean; status: GameSearchStatus }) {
  return search.isActive && (search.status === "active" || search.status === "in_review");
}

export function formatTimeUntilHotSearch(startsAt: string | Date | null | undefined) {
  if (!startsAt) {
    return null;
  }

  const diffMs = new Date(startsAt).getTime() - Date.now();
  if (diffMs <= 0) {
    return "уже началось";
  }

  const totalMinutes = Math.floor(diffMs / 60000);
  const days = Math.floor(totalMinutes / (60 * 24));
  const hours = Math.floor((totalMinutes % (60 * 24)) / 60);
  const minutes = totalMinutes % 60;
  const parts: string[] = [];

  if (days > 0) parts.push(`${days}д`);
  if (hours > 0) parts.push(`${hours}ч`);
  if (minutes > 0 && days === 0) parts.push(`${minutes}м`);

  return parts.length > 0 ? `через ${parts.join(" ")}` : "меньше чем через минуту";
}

export function resolveSearchLifecycleStatus({
  status,
  approvedCount,
  playersNeeded,
  startAt,
  durationMinutes
}: {
  status: "active" | "in_review" | "matched" | "closed";
  approvedCount: number;
  playersNeeded: number;
  startAt?: string | Date | null;
  durationMinutes?: number | null;
}) {
  const safePlayersNeeded = Math.max(playersNeeded, 1);
  const isFilled = approvedCount >= safePlayersNeeded;
  const startTime = startAt ? new Date(startAt).getTime() : null;
  const now = Date.now();
  const effectiveDurationMinutes = durationMinutes ?? 90;

  if (isFilled && startTime) {
    const soonThresholdMs = 2 * 60 * 60 * 1000;
    const startedThresholdMs = 10 * 60 * 1000;
    const endTime = startTime + effectiveDurationMinutes * 60 * 1000;

    if (now >= endTime) {
      return "Игра закончилась";
    }

    if (now >= startTime + startedThresholdMs) {
      return "Игра идет";
    }

    if (now >= startTime) {
      return "Игра началась";
    }

    if (startTime - now <= soonThresholdMs) {
      return "Скоро начнется";
    }
  }

  if (isFilled) {
    return safePlayersNeeded > 1 ? "Игроки найдены" : "Игрок найден";
  }

  if (approvedCount > 0 || status === "in_review") {
    return "В процессе набора";
  }

  if (status === "closed") {
    return "Закрыт";
  }

  return "Поиск";
}

export function resolveScheduledGameStatus(startAt: string | Date, durationMinutes?: number | null) {
  return resolveSearchLifecycleStatus({
    status: "matched",
    approvedCount: 1,
    playersNeeded: 1,
    startAt,
    durationMinutes
  });
}

export function resolveSearchNextStep(options: {
  searchType: "regular" | "hot";
  status: "active" | "in_review" | "matched" | "closed";
  approvedCount: number;
  playersNeeded: number;
  scheduledAt?: string | Date | null;
  regularPairMatchId?: string | null;
}) {
  const { searchType, status, approvedCount, playersNeeded, scheduledAt, regularPairMatchId } = options;
  const safePlayersNeeded = Math.max(playersNeeded, 1);

  if (scheduledAt) {
    return {
      title: "Игра подтверждена",
      description: "Событие уже назначено. Следующий шаг: открой детали игры и договорись только о последних нюансах.",
      ctaLabel: "Открыть подтвержденную игру"
    };
  }

  if (searchType === "regular" && safePlayersNeeded === 1 && approvedCount === 1 && regularPairMatchId) {
    return {
      title: "Пара собрана",
      description: "Следующий шаг: предложить ближайшую игру партнеру и дождаться подтверждения.",
      ctaLabel: "Открыть чат пары"
    };
  }

  if (approvedCount >= safePlayersNeeded) {
    return {
      title: "Состав собран",
      description: "Следующий шаг: закрыть набор и назначить конкретную игру.",
      ctaLabel: "Открыть лобби"
    };
  }

  if (approvedCount > 0 || status === "in_review") {
    return {
      title: "Есть отклики",
      description: "Следующий шаг: выбрать игроков и перевести поиск в конкретную игру.",
      ctaLabel: "Открыть чат и отклики"
    };
  }

  if (status === "closed") {
    return {
      title: "Поиск закрыт",
      description: "Этот сценарий остановлен. Если всё ещё нужен игрок, открой поиск заново или создай новый.",
      ctaLabel: "Открыть поиск"
    };
  }

  return {
    title: "Поиск открыт",
    description: "Следующий шаг: дождаться откликов или скорректировать условия, чтобы быстрее договориться об игре.",
    ctaLabel: "Открыть поиск"
  };
}
