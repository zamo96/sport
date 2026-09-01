"use client";

import { type Sport } from "@prisma/client";
import { ChevronLeft, ChevronRight, HelpCircle, Hand } from "lucide-react";

import { useLocale } from "@/components/i18n/locale-provider";
import { SPORT_OPTIONS } from "@/lib/constants";
import { getAuthSportLabel } from "@/lib/i18n/web/auth";
import { type SportLevelValue } from "@/lib/sport-levels";
import { cn } from "@/lib/utils";
import { SportIcon } from "@/components/ui/sport-icon";

const LEVEL_TONES = [
  { min: 1, max: 2, key: "sportPicker.tone.beginner" },
  { min: 3, max: 4, key: "sportPicker.tone.basics" },
  { min: 5, max: 6, key: "sportPicker.tone.confident" },
  { min: 7, max: 8, key: "sportPicker.tone.strong" },
  { min: 9, max: 10, key: "sportPicker.tone.tournament" }
] as const;

export function SportPicker({
  value,
  onChange,
  multiple = false,
  options = SPORT_OPTIONS,
  levels,
  onLevelChange,
  layout = "grid",
  showLevelHint = false,
  showCarouselHint = false
}: {
  value: Sport[];
  onChange: (value: Sport[]) => void;
  multiple?: boolean;
  options?: readonly Sport[];
  levels?: Partial<Record<Sport, SportLevelValue>>;
  onLevelChange?: (sport: Sport, level: SportLevelValue) => void;
  layout?: "grid" | "carousel";
  showLevelHint?: boolean;
  showCarouselHint?: boolean;
}) {
  const { locale, t } = useLocale();

  function toggle(sport: Sport) {
    if (multiple) {
      onChange(value.includes(sport) ? value.filter((item) => item !== sport) : [...value, sport]);
      return;
    }

    onChange([sport]);
  }

  return (
    <div className="space-y-2">
      <div
        className={cn(
          layout === "carousel"
            ? "flex snap-x snap-mandatory gap-2.5 overflow-x-auto pb-1 [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden"
            : "grid grid-cols-2 gap-2.5"
        )}
      >
        {options.map((sport) => {
          const active = value.includes(sport);
          const levelValue = levels?.[sport];
          const isUnknownLevel = levelValue === null;
          const level = typeof levelValue === "number" ? levelValue : 5;
          const levelToneKey = LEVEL_TONES.find((tone) => level >= tone.min && level <= tone.max)?.key
            ?? "sportPicker.tone.confident";
          const levelVisual = getLevelVisual(level, t(levelToneKey));
          return (
            <div
              key={sport}
              role="button"
              tabIndex={0}
              onClick={() => toggle(sport)}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  toggle(sport);
                }
              }}
              className={cn(
                "cursor-pointer rounded-[22px] border px-3 py-3 text-left transition-all duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] will-change-transform transform-gpu",
                layout === "carousel" && "min-w-[11.25rem] snap-center",
                active
                  ? "translate-y-[-2px] border-court/35 bg-[linear-gradient(180deg,rgba(58,134,109,0.96),rgba(23,56,46,0.92))] text-white shadow-[0_20px_44px_rgba(20,47,38,0.22)] ring-1 ring-white/18"
                  : "border-white/60 bg-[linear-gradient(180deg,rgba(255,255,255,0.92),rgba(248,243,233,0.96))] text-ink hover:translate-y-[-1px] hover:shadow-[0_14px_30px_rgba(20,47,38,0.08)]"
              )}
            >
              <div className="w-full text-left">
                <div className="inline-flex items-center gap-2 text-sm font-bold">
                  <span
                    className={cn(
                      "flex h-8 w-8 items-center justify-center rounded-2xl transition-all duration-300",
                      active ? "scale-105 bg-white/16 text-white shadow-[0_10px_22px_rgba(255,255,255,0.08)]" : "bg-white text-court"
                    )}
                  >
                    <SportIcon sport={sport} className="h-4 w-4" />
                  </span>
                  <span className="leading-5">{getAuthSportLabel(locale, sport)}</span>
                </div>
                <div className={cn("mt-1 text-[11px] leading-[1.1rem]", active ? "text-white/78" : "text-ink/60")}>
                  {multiple ? t("sportPicker.addMultiple") : t("sportPicker.chooseOne")}
                </div>
              </div>

              <div
                className={cn(
                  "overflow-hidden transition-[max-height,opacity,transform,margin] duration-500 ease-[cubic-bezier(0.22,1,0.36,1)]",
                  active && levels && onLevelChange ? "mt-3 max-h-72 translate-y-0 opacity-100" : "mt-0 max-h-0 -translate-y-1 opacity-0"
                )}
              >
                <div>
                  {levels && onLevelChange ? (
                    <div
                      className={cn(
                        "rounded-[18px] bg-white/12 px-2.5 py-2.5 transition-[transform,opacity] duration-500 ease-[cubic-bezier(0.22,1,0.36,1)]",
                        active ? "scale-100 opacity-100" : "scale-[0.985] opacity-0"
                      )}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-[10px] font-semibold uppercase tracking-[0.16em] text-white/70">{t("sportPicker.level")}</span>
                        <span
                          className={cn(
                            "rounded-full px-2 py-1 text-[11px] font-semibold",
                            isUnknownLevel ? "bg-white/16 text-white/90" : levelVisual.badgeClassName
                          )}
                        >
                          {isUnknownLevel ? t("sportPicker.unknown") : levelVisual.label}
                        </span>
                      </div>

                      <div className="mt-2 space-y-2">
                        <div className="grid grid-cols-2 gap-2 rounded-[16px] bg-white/10 p-1">
                          <button
                            type="button"
                            onClick={(event) => {
                              event.preventDefault();
                              event.stopPropagation();
                              onLevelChange(sport, 5);
                            }}
                            className={cn(
                              "rounded-[12px] px-3 py-2 text-[11px] font-semibold transition",
                              !isUnknownLevel ? "bg-white text-ink shadow-[0_8px_16px_rgba(17,38,29,0.12)]" : "text-white/82 hover:bg-white/8"
                            )}
                          >
                            {t("sportPicker.scale")}
                          </button>
                          <button
                            type="button"
                            onClick={(event) => {
                              event.preventDefault();
                              event.stopPropagation();
                              onLevelChange(sport, null);
                            }}
                            className={cn(
                              "inline-flex items-center justify-center gap-1.5 rounded-[12px] px-3 py-2 text-[11px] font-semibold transition",
                              isUnknownLevel ? "bg-white text-ink shadow-[0_8px_16px_rgba(17,38,29,0.12)]" : "text-white/82 hover:bg-white/8"
                            )}
                          >
                            <HelpCircle className="h-3.5 w-3.5" />
                            {t("sportPicker.unknown")}
                          </button>
                        </div>
                        {showLevelHint ? (
                          <span className="block text-[10px] leading-4 text-white/72">{t("sportPicker.levelLater")}</span>
                        ) : null}
                      </div>

                      <div className="relative mt-2 min-h-[4.75rem]">
                        <div
                          className={cn(
                            "flex min-h-[4.75rem] items-center justify-center px-2 text-center text-[11px] leading-4 text-white/80 transition-[opacity,transform] duration-500 ease-[cubic-bezier(0.22,1,0.36,1)]",
                            isUnknownLevel ? "translate-y-0 opacity-100" : "pointer-events-none absolute inset-0 opacity-0"
                          )}
                        >
                          {t("sportPicker.levelLaterLong")}
                        </div>

                        <div
                          className={cn(
                            "transition-[opacity,transform] duration-500 ease-[cubic-bezier(0.22,1,0.36,1)]",
                            !isUnknownLevel ? "translate-y-0 opacity-100" : "pointer-events-none absolute inset-0 opacity-0"
                          )}
                        >
                          <div className="flex min-h-[4.75rem] items-center gap-2">
                            <LevelStepButton
                              label={t("sportPicker.decrease")}
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
                              label={t("sportPicker.increase")}
                              className={levelVisual.stepClassName}
                              onClick={() => onLevelChange(sport, Math.min(10, level + 1))}
                            >
                              +
                            </LevelStepButton>
                          </div>
                        </div>
                      </div>
                    </div>
                  ) : null}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {layout === "carousel" && showCarouselHint ? (
        <div className="flex items-center justify-center gap-2 text-[11px] font-medium text-ink/46">
          <ChevronLeft className="h-3.5 w-3.5 opacity-60" />
          <span className="relative inline-flex h-6 w-6 items-center justify-center">
            <Hand className="h-4 w-4 animate-[swipe-hand_1.8s_ease-in-out_infinite] text-ink/42" />
          </span>
          <span>{t("sportPicker.carouselHint")}</span>
          <ChevronRight className="h-3.5 w-3.5 opacity-60" />
        </div>
      ) : null}
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

function getLevelVisual(level: number, label: string) {
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
