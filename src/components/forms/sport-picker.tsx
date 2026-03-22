"use client";

import { type Sport } from "@prisma/client";

import { SPORT_LABELS, SPORT_OPTIONS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import { SportIcon } from "@/components/ui/sport-icon";

const LEVEL_TONES = [
  { min: 1, max: 2, label: "Новичок" },
  { min: 3, max: 4, label: "База" },
  { min: 5, max: 6, label: "Уверенный" },
  { min: 7, max: 8, label: "Сильный" },
  { min: 9, max: 10, label: "Турнирный" }
] as const;

export function SportPicker({
  value,
  onChange,
  multiple = false,
  options = SPORT_OPTIONS,
  levels,
  onLevelChange
}: {
  value: Sport[];
  onChange: (value: Sport[]) => void;
  multiple?: boolean;
  options?: readonly Sport[];
  levels?: Partial<Record<Sport, number>>;
  onLevelChange?: (sport: Sport, level: number) => void;
}) {
  function toggle(sport: Sport) {
    if (multiple) {
      onChange(value.includes(sport) ? value.filter((item) => item !== sport) : [...value, sport]);
      return;
    }

    onChange([sport]);
  }

  return (
    <div className="grid grid-cols-2 gap-2.5">
      {options.map((sport) => {
        const active = value.includes(sport);
        const level = levels?.[sport] ?? 5;
        const levelVisual = getLevelVisual(level);
        return (
          <div
            key={sport}
            className={cn(
              "rounded-[22px] border px-3 py-3 text-left transition-all duration-300 ease-out will-change-transform",
              active
                ? "translate-y-[-2px] border-court/35 bg-[linear-gradient(180deg,rgba(58,134,109,0.96),rgba(23,56,46,0.92))] text-white shadow-[0_20px_44px_rgba(20,47,38,0.22)] ring-1 ring-white/18"
                : "border-white/60 bg-[linear-gradient(180deg,rgba(255,255,255,0.92),rgba(248,243,233,0.96))] text-ink hover:translate-y-[-1px] hover:shadow-[0_14px_30px_rgba(20,47,38,0.08)]"
            )}
          >
            <button type="button" onClick={() => toggle(sport)} className="w-full text-left">
              <div className="inline-flex items-center gap-2 text-sm font-bold">
                <span
                  className={cn(
                    "flex h-8 w-8 items-center justify-center rounded-2xl transition-all duration-300",
                    active ? "scale-105 bg-white/16 text-white shadow-[0_10px_22px_rgba(255,255,255,0.08)]" : "bg-white text-court"
                  )}
                >
                  <SportIcon sport={sport} className="h-4 w-4" />
                </span>
                <span className="leading-5">{SPORT_LABELS[sport]}</span>
              </div>
              <div className={cn("mt-1 text-[11px] leading-[1.1rem]", active ? "text-white/78" : "text-ink/60")}>
                {multiple ? "Добавь в свои виды спорта" : "Выбери спорт для этой игры"}
              </div>
            </button>

            <div
              className={cn(
                "grid origin-top transition-all duration-300 ease-out",
                active && levels && onLevelChange ? "mt-3 grid-rows-[1fr] opacity-100" : "mt-0 grid-rows-[0fr] opacity-0"
              )}
            >
              <div className="min-h-0 overflow-hidden">
                {levels && onLevelChange ? (
                  <div className={cn("rounded-[18px] bg-white/12 px-2.5 py-2.5 transition-all duration-300", active ? "scale-100" : "scale-95")}>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[10px] font-semibold uppercase tracking-[0.16em] text-white/70">Уровень</span>
                      <span className={cn("rounded-full px-2 py-1 text-[11px] font-semibold", levelVisual.badgeClassName)}>
                        {levelVisual.label}
                      </span>
                    </div>
                    <div className="mt-2 flex items-center gap-2">
                      <LevelStepButton
                        label="Уменьшить"
                        className={levelVisual.stepClassName}
                        onClick={() => onLevelChange(sport, Math.max(1, level - 1))}
                      >
                        -
                      </LevelStepButton>
                      <div className="flex-1">
                        <div className="flex items-end justify-between gap-1">
                          {Array.from({ length: 10 }, (_, index) => {
                            const activeSegment = index < level;
                            return (
                              <span
                                key={`${sport}-${index + 1}`}
                                className={cn(
                                  "h-6 flex-1 rounded-full transition-all duration-300 ease-out",
                                  activeSegment ? levelVisual.segmentClassName : "bg-white/18"
                                )}
                                style={activeSegment ? { transitionDelay: `${index * 18}ms` } : undefined}
                              />
                            );
                          })}
                        </div>
                        <div className="mt-1.5 flex items-center justify-between text-[10px] font-medium text-white/64">
                          <span>1</span>
                          <span className="text-xs font-bold text-white">{level}</span>
                          <span>10</span>
                        </div>
                      </div>
                      <LevelStepButton
                        label="Увеличить"
                        className={levelVisual.stepClassName}
                        onClick={() => onLevelChange(sport, Math.min(10, level + 1))}
                      >
                        +
                      </LevelStepButton>
                    </div>
                  </div>
                ) : null}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function LevelStepButton({
  children,
  label,
  onClick,
  className
}: {
  children: string;
  label: string;
  onClick: () => void;
  className?: string;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={(event) => {
        event.preventDefault();
        event.stopPropagation();
        onClick();
      }}
      className={cn(
        "flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-lg font-semibold text-white transition duration-200 active:scale-90",
        className
      )}
    >
      {children}
    </button>
  );
}

function getLevelVisual(level: number) {
  const label = LEVEL_TONES.find((tone) => level >= tone.min && level <= tone.max)?.label ?? "Уверенный";

  if (level <= 2) {
    return {
      label,
      badgeClassName: "bg-rose-400/22 text-white",
      segmentClassName: "bg-gradient-to-t from-rose-300 to-orange-300 shadow-[0_6px_14px_rgba(251,113,133,0.25)]",
      stepClassName: "bg-rose-300/24 hover:bg-rose-300/32"
    };
  }

  if (level <= 4) {
    return {
      label,
      badgeClassName: "bg-orange-300/24 text-white",
      segmentClassName: "bg-gradient-to-t from-orange-300 to-amber-200 shadow-[0_6px_14px_rgba(251,146,60,0.24)]",
      stepClassName: "bg-orange-300/24 hover:bg-orange-300/34"
    };
  }

  if (level <= 6) {
    return {
      label,
      badgeClassName: "bg-yellow-200/26 text-white",
      segmentClassName: "bg-gradient-to-t from-yellow-200 to-lime-200 shadow-[0_6px_14px_rgba(250,204,21,0.24)]",
      stepClassName: "bg-yellow-200/24 hover:bg-yellow-200/34"
    };
  }

  if (level <= 8) {
    return {
      label,
      badgeClassName: "bg-emerald-300/24 text-white",
      segmentClassName: "bg-gradient-to-t from-emerald-300 to-teal-200 shadow-[0_6px_14px_rgba(52,211,153,0.26)]",
      stepClassName: "bg-emerald-300/24 hover:bg-emerald-300/34"
    };
  }

  return {
    label,
    badgeClassName: "bg-sky-300/24 text-white",
    segmentClassName: "bg-gradient-to-t from-sky-300 to-cyan-200 shadow-[0_6px_14px_rgba(56,189,248,0.26)]",
    stepClassName: "bg-sky-300/24 hover:bg-sky-300/34"
  };
}
