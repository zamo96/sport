"use client";

import { type Sport } from "@prisma/client";

import { useLocale } from "@/components/i18n/locale-provider";
import { cn } from "@/lib/utils";
import { SportBadge } from "@/components/ui/sport-badge";

export function SportLevelBadge({
  sport,
  level,
  className,
  badgeClassName,
  levelClassName,
  iconClassName
}: {
  sport: Sport;
  level: number | null;
  className?: string;
  badgeClassName?: string;
  levelClassName?: string;
  iconClassName?: string;
}) {
  const { t } = useLocale();

  return (
    <span className={cn("inline-flex items-center gap-2", className)}>
      <SportBadge sport={sport} className={badgeClassName} iconClassName={iconClassName} />
      <span className={cn("rounded-full px-3 py-2 text-xs font-semibold", levelClassName)}>
        {level === null ? t("profile.level.unknown") : t("profile.level.value", { level })}
      </span>
    </span>
  );
}
