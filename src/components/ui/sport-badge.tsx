"use client";

import type { Sport } from "@prisma/client";

import { useLocale } from "@/components/i18n/locale-provider";
import { getAuthSportLabel } from "@/lib/i18n/web/auth";
import { cn } from "@/lib/utils";
import { SportIcon } from "@/components/ui/sport-icon";

export function SportBadge({
  sport,
  className,
  iconClassName
}: {
  sport: Sport;
  className?: string;
  iconClassName?: string;
}) {
  const { locale } = useLocale();

  return (
    <span className={cn("inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-xs font-semibold", className)}>
      <SportIcon sport={sport} className={iconClassName ?? "h-3.5 w-3.5"} />
      {getAuthSportLabel(locale, sport)}
    </span>
  );
}
