"use client";

import { type Sport } from "@prisma/client";

import { SportLevelBadge } from "@/components/ui/sport-level-badge";

type SportLevels = Partial<Record<Sport, number>>;

export function SportLevelsEditor({
  sports,
  values,
  onChange
}: {
  sports: Sport[];
  values: SportLevels;
  onChange: (sport: Sport, level: number) => void;
}) {
  if (sports.length === 0) {
    return null;
  }

  return (
    <div className="space-y-3">
      {sports.map((sport) => {
        const level = values[sport] ?? 5;

        return (
          <div key={sport} className="rounded-[24px] bg-cream p-4">
            <div className="flex items-center justify-between gap-3">
              <SportLevelBadge
                sport={sport}
                level={level}
                badgeClassName="bg-white text-ink"
                levelClassName="bg-white text-ink"
              />
              <div className="text-xs font-semibold uppercase tracking-[0.18em] text-ink/45">1-10</div>
            </div>
            <input
              type="range"
              min={1}
              max={10}
              value={level}
              onChange={(event) => onChange(sport, Number(event.target.value))}
              className="mt-4 w-full accent-clay"
            />
            <div className="mt-2 flex items-center justify-between text-[11px] font-medium text-ink/45">
              <span>Начинающий</span>
              <span>Продвинутый</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}
