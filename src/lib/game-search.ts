import { HotSearchWindow, type GameSearchType } from "@prisma/client";

import { DAY_OPTIONS } from "@/lib/constants";

export function resolveSearchDays(
  searchType: GameSearchType,
  preferredDays: string[],
  hotWindow?: HotSearchWindow | null
) {
  if (searchType !== "hot") {
    return preferredDays;
  }

  const targetDate = new Date();
  if (hotWindow === "tomorrow") {
    targetDate.setDate(targetDate.getDate() + 1);
  } else if (hotWindow === "day_after_tomorrow") {
    targetDate.setDate(targetDate.getDate() + 2);
  }

  const dayIndex = targetDate.getDay();
  const dayMap = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] as const;
  const resolvedDay = dayMap[dayIndex];

  return DAY_OPTIONS.includes(resolvedDay) ? [resolvedDay] : [];
}

export function resolveHotSearchStartAt(hotWindow: HotSearchWindow, time: string) {
  const [hoursString, minutesString] = time.split(":");
  const hours = Number(hoursString);
  const minutes = Number(minutesString);

  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) {
    return null;
  }

  const targetDate = new Date();
  if (hotWindow === "tomorrow") {
    targetDate.setDate(targetDate.getDate() + 1);
  } else if (hotWindow === "day_after_tomorrow") {
    targetDate.setDate(targetDate.getDate() + 2);
  }

  targetDate.setHours(hours, minutes, 0, 0);
  return targetDate;
}

export function isExpiredHotSearch(startsAt: string | Date | null | undefined) {
  if (!startsAt) {
    return false;
  }

  return new Date(startsAt).getTime() <= Date.now();
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
