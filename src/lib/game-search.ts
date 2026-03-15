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
  }

  const dayIndex = targetDate.getDay();
  const dayMap = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] as const;
  const resolvedDay = dayMap[dayIndex];

  return DAY_OPTIONS.includes(resolvedDay) ? [resolvedDay] : [];
}
