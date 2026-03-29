"use client";

import { useEffect, useMemo, useState } from "react";
import { type Sport } from "@prisma/client";
import { Info, X } from "lucide-react";

import { SPORT_LABELS } from "@/lib/constants";
import { getSportLevelGuideSports, SPORT_LEVEL_GUIDES } from "@/lib/sport-level-guides";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportIcon } from "@/components/ui/sport-icon";

export function SportLevelGuideSheet({
  open,
  sports,
  onClose
}: {
  open: boolean;
  sports: Sport[];
  onClose: () => void;
}) {
  const availableSports = useMemo(() => getSportLevelGuideSports(sports), [sports]);
  const [activeSport, setActiveSport] = useState<Sport>(availableSports[0] ?? "tennis");

  useEffect(() => {
    if (!availableSports.includes(activeSport)) {
      setActiveSport(availableSports[0] ?? "tennis");
    }
  }, [activeSport, availableSports]);

  if (!open) {
    return null;
  }

  const guide = SPORT_LEVEL_GUIDES[activeSport];

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/45 px-3 pb-4 pt-10 backdrop-blur-[2px]">
      <Panel className="flex max-h-[84svh] w-full max-w-lg flex-col overflow-hidden rounded-[32px] border-white/70 bg-cream p-0 shadow-[0_28px_80px_rgba(17,38,29,0.18)]">
        <div className="border-b border-line/80 px-4 pb-3 pt-4">
          <div className="flex items-start justify-between gap-3">
            <div className="space-y-2">
              <div className="inline-flex items-center gap-2 rounded-full bg-white px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
                <Info className="h-3.5 w-3.5" />
                Подсказка по уровням
              </div>
              <div className="text-xl font-bold text-ink">Как выбрать уровень</div>
              <div className="text-sm leading-6 text-ink/65">
                Выбери вид спорта и ориентируйся по ближайшему описанию. Если сомневаешься, можно оставить вариант
                `Не знаю`.
              </div>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="flex h-10 w-10 items-center justify-center rounded-full bg-white text-ink/60"
              aria-label="Закрыть"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <div className="mt-4 flex gap-2 overflow-x-auto pb-1 [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden">
            {availableSports.map((sport) => {
              const active = sport === activeSport;
              return (
                <button
                  key={sport}
                  type="button"
                  onClick={() => setActiveSport(sport)}
                  className={cn(
                    "inline-flex shrink-0 items-center gap-2 rounded-full px-3 py-2 text-sm font-semibold transition",
                    active ? "bg-court text-white shadow-[0_12px_24px_rgba(17,38,29,0.16)]" : "bg-white text-ink/78"
                  )}
                >
                  <SportIcon sport={sport} className="h-4 w-4" />
                  {SPORT_LABELS[sport]}
                </button>
              );
            })}
          </div>
        </div>

        <div className="flex-1 space-y-2 overflow-y-auto px-4 py-4">
          {guide.map((entry) => (
            <div
              key={`${activeSport}-${entry.level}`}
              className="rounded-[22px] border border-white/70 bg-white/76 px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.68)]"
            >
              <div className="flex items-center justify-between gap-3">
                <div className="text-base font-bold text-ink">
                  {entry.level}. {entry.title}
                </div>
                <div className="rounded-full bg-cream px-3 py-1 text-xs font-semibold text-court">Уровень {entry.level}</div>
              </div>
              <div className="mt-1.5 text-sm leading-6 text-ink/68">{entry.description}</div>
            </div>
          ))}
        </div>

        <div className="border-t border-line/80 px-4 py-3">
          <Button type="button" fullWidth onClick={onClose}>
            Понятно
          </Button>
        </div>
      </Panel>
    </div>
  );
}
