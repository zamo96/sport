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
