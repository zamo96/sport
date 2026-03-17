import type { Sport } from "@prisma/client";

import { SPORT_LABELS } from "@/lib/constants";
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
  return (
    <span className={cn("inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-xs font-semibold", className)}>
      <SportIcon sport={sport} className={iconClassName ?? "h-3.5 w-3.5"} />
      {SPORT_LABELS[sport]}
    </span>
  );
}
