"use client";

import { SPORT_LABELS, SPORT_OPTIONS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { SportIcon } from "@/components/ui/sport-icon";

type Sport = (typeof SPORT_OPTIONS)[number];

export function SportPicker({
  value,
  onChange,
  multiple = false,
  options = SPORT_OPTIONS
}: {
  value: Sport[];
  onChange: (value: Sport[]) => void;
  multiple?: boolean;
  options?: readonly Sport[];
}) {
  function toggle(sport: Sport) {
    if (multiple) {
      onChange(value.includes(sport) ? value.filter((item) => item !== sport) : [...value, sport]);
      return;
    }

    onChange([sport]);
  }

  return (
    <div className="grid grid-cols-2 gap-3">
      {options.map((sport) => {
        const active = value.includes(sport);
        return (
          <button
            key={sport}
            type="button"
            onClick={() => toggle(sport)}
            className={cn(
              "rounded-[22px] border px-4 py-4 text-left transition",
              active ? "border-ink bg-ink text-white" : "border-white/60 bg-cream text-ink"
            )}
          >
            <div className="inline-flex items-center gap-2 text-sm font-bold">
              <SportIcon sport={sport} className="h-4 w-4" />
              {SPORT_LABELS[sport]}
            </div>
            <div className={cn("mt-1 text-xs leading-5", active ? "text-white/80" : "text-ink/60")}>
              {multiple ? "Добавь в свои виды спорта" : "Выбери спорт для этой игры"}
            </div>
          </button>
        );
      })}
    </div>
  );
}
