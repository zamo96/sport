"use client";

import { useEffect, useMemo, useState } from "react";
import { MoonStar, Sunrise, SunMedium } from "lucide-react";

import { DAY_LABELS, DAY_OPTIONS, TIME_RANGE_LABELS, TIME_RANGE_OPTIONS } from "@/lib/constants";
import { Chip } from "@/components/ui/chip";

type AvailabilityByDay = Partial<Record<(typeof DAY_OPTIONS)[number], (typeof TIME_RANGE_OPTIONS)[number][]>>;

const TIME_RANGE_STYLES = {
  morning: {
    icon: Sunrise,
    activeClassName:
      "border-amber-200 bg-[linear-gradient(180deg,#FFF3D6_0%,#FFD9B3_48%,#FFF8EC_100%)] text-[#8A4A22] shadow-[0_12px_26px_rgba(201,109,66,0.16)]",
    inactiveClassName:
      "border-white/80 bg-[linear-gradient(180deg,rgba(255,248,236,0.96),rgba(255,237,214,0.94))] text-[#9B673B]"
  },
  day: {
    icon: SunMedium,
    activeClassName:
      "border-yellow-200 bg-[linear-gradient(180deg,#FFF7CC_0%,#FFE78F_52%,#FFF8E4_100%)] text-[#8A5A00] shadow-[0_12px_26px_rgba(243,186,47,0.18)]",
    inactiveClassName:
      "border-white/80 bg-[linear-gradient(180deg,rgba(255,251,230,0.96),rgba(255,244,197,0.94))] text-[#9A7A18]"
  },
  evening: {
    icon: MoonStar,
    activeClassName:
      "border-slate-200 bg-[linear-gradient(180deg,#E3EAFB_0%,#C9D7FF_48%,#EEF2FF_100%)] text-[#334B7A] shadow-[0_12px_26px_rgba(81,110,174,0.18)]",
    inactiveClassName:
      "border-white/80 bg-[linear-gradient(180deg,rgba(242,246,255,0.96),rgba(229,236,255,0.94))] text-[#5A6E9A]"
  }
} as const;

export function AvailabilityPicker({
  days,
  timeRanges,
  onDaysChange,
  onTimeRangesChange,
  availabilityByDay,
  onAvailabilityByDayChange,
  hideDays = false
}: {
  days?: string[];
  timeRanges?: string[];
  onDaysChange?: (value: string[]) => void;
  onTimeRangesChange?: (value: string[]) => void;
  availabilityByDay?: AvailabilityByDay;
  onAvailabilityByDayChange?: (value: AvailabilityByDay) => void;
  hideDays?: boolean;
}) {
  const hasDetailedAvailability = Boolean(availabilityByDay && onAvailabilityByDayChange);
  const detailedAvailability = useMemo(() => availabilityByDay ?? {}, [availabilityByDay]);
  const dayWithSelection = useMemo(
    () => DAY_OPTIONS.find((day) => (detailedAvailability[day] ?? []).length > 0) ?? DAY_OPTIONS[0],
    [detailedAvailability]
  );
  const [activeDay, setActiveDay] = useState<(typeof DAY_OPTIONS)[number]>(dayWithSelection);

  useEffect(() => {
    setActiveDay((current) => (DAY_OPTIONS.includes(current) ? current : dayWithSelection));
  }, [dayWithSelection]);

  if (hasDetailedAvailability && onAvailabilityByDayChange) {
    const setDetailedAvailability = onAvailabilityByDayChange;
    const activeRanges = detailedAvailability[activeDay] ?? [];

    function setDayRanges(day: (typeof DAY_OPTIONS)[number], ranges: (typeof TIME_RANGE_OPTIONS)[number][]) {
      setDetailedAvailability({
        ...detailedAvailability,
        [day]: ranges
      });
    }

    function toggleTimeRange(timeRange: (typeof TIME_RANGE_OPTIONS)[number]) {
      const nextRanges = activeRanges.includes(timeRange)
        ? activeRanges.filter((item) => item !== timeRange)
        : [...activeRanges, timeRange];

      setDayRanges(activeDay, nextRanges);
    }

    function applyPreset(
      presetDays: (typeof DAY_OPTIONS)[number][],
      presetRanges: (typeof TIME_RANGE_OPTIONS)[number][]
    ) {
      setDetailedAvailability({
        ...detailedAvailability,
        ...Object.fromEntries(presetDays.map((day) => [day, presetRanges]))
      });
    }

    return (
      <div className="space-y-3">
        <div className="rounded-[24px] bg-cream p-3.5">
          <div className="text-sm font-semibold text-ink">Одна шкала недели</div>
          <div className="mt-1 text-[11px] leading-[1.1rem] text-ink/60">
            Выбери день, затем отметь подходящее время. Пустые дни в подбор не попадут.
          </div>
        </div>

        <div className="rounded-[24px] bg-white/85 p-3">
          <div className="grid grid-cols-7 gap-1.5">
            {DAY_OPTIONS.map((day) => {
              const selectedRanges = detailedAvailability[day] ?? [];
              return (
                <button
                  key={day}
                  type="button"
                  onClick={() => setActiveDay(day)}
                  className={`rounded-[18px] px-1.5 py-2 text-center transition ${
                    activeDay === day ? "bg-ink text-white shadow-card" : "bg-cream text-ink"
                  }`}
                >
                  <div className="text-sm font-bold">{DAY_LABELS[day]}</div>
                  <div className="mt-1 flex items-center justify-center gap-1">
                    {TIME_RANGE_OPTIONS.map((timeRange) => (
                      <span
                        key={`${day}-${timeRange}`}
                        className={`h-1.5 w-1.5 rounded-full ${
                          selectedRanges.includes(timeRange)
                            ? activeDay === day
                              ? "bg-white"
                              : "bg-court"
                            : activeDay === day
                              ? "bg-white/28"
                              : "bg-ink/12"
                        }`}
                      />
                    ))}
                  </div>
                </button>
              );
            })}
          </div>

          <div className="mt-3 rounded-[20px] bg-cream px-3 py-3">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-sm font-semibold text-ink">{DAY_LABELS[activeDay]}</div>
                <div className="mt-1 text-[11px] leading-[1.1rem] text-ink/55">
                  Выбери одно или несколько окон времени
                </div>
              </div>
              {activeRanges.length > 0 ? (
                <button
                  type="button"
                  onClick={() => setDayRanges(activeDay, [])}
                  className="text-xs font-semibold text-clay"
                >
                  Очистить
                </button>
              ) : (
                <span className="text-[11px] text-ink/40">Пока пусто</span>
              )}
            </div>

            <div className="mt-3 grid grid-cols-3 gap-2">
              {TIME_RANGE_OPTIONS.map((timeRange) => {
                const active = activeRanges.includes(timeRange);
                const config = TIME_RANGE_STYLES[timeRange];
                const Icon = config.icon;
                return (
                  <button
                    key={timeRange}
                    type="button"
                    onClick={() => toggleTimeRange(timeRange)}
                    className={`relative overflow-hidden rounded-[18px] border px-3 py-3 text-center text-sm font-semibold transition duration-200 ${
                      active ? config.activeClassName : config.inactiveClassName
                    }`}
                  >
                    <span className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.52),transparent_60%)]" />
                    <span className="relative flex flex-col items-center gap-1.5">
                      <span
                        className={`flex h-8 w-8 items-center justify-center rounded-full ${
                          active ? "bg-white/72" : "bg-white/82"
                        }`}
                      >
                        <Icon className="h-4 w-4" />
                      </span>
                      <span>{TIME_RANGE_LABELS[timeRange]}</span>
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => applyPreset(["monday", "tuesday", "wednesday", "thursday", "friday"], ["morning"])}
              className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink"
            >
              Будни утром
            </button>
            <button
              type="button"
              onClick={() => applyPreset(["monday", "tuesday", "wednesday", "thursday", "friday"], ["evening"])}
              className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink"
            >
              Будни вечером
            </button>
            <button
              type="button"
              onClick={() => applyPreset(["saturday", "sunday"], ["morning", "day", "evening"])}
              className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink"
            >
              Выходные
            </button>
            <button
              type="button"
              onClick={() =>
                setDetailedAvailability(
                  Object.fromEntries(DAY_OPTIONS.map((day) => [day, []])) as AvailabilityByDay
                )
              }
              className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-clay"
            >
              Сбросить всё
            </button>
          </div>
        </div>
      </div>
    );
  }

  const normalizedDays = days ?? [];
  const normalizedTimeRanges = timeRanges ?? [];

  function toggle(values: string[], value: string, setter?: (value: string[]) => void) {
    if (!setter) {
      return;
    }

    setter(values.includes(value) ? values.filter((item) => item !== value) : [...values, value]);
  }

  return (
    <div className="space-y-3">
      {!hideDays ? (
        <div>
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">Дни</div>
          <div className="flex flex-wrap gap-2">
            {DAY_OPTIONS.map((day) => (
              <Chip
                key={day}
                active={normalizedDays.includes(day)}
                onClick={() => toggle(normalizedDays, day, onDaysChange)}
              >
                {DAY_LABELS[day]}
              </Chip>
            ))}
          </div>
        </div>
      ) : null}

      <div>
        <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">Время</div>
        <div className="flex flex-wrap gap-2">
          {TIME_RANGE_OPTIONS.map((timeRange) => (
            <Chip
              key={timeRange}
              active={normalizedTimeRanges.includes(timeRange)}
              onClick={() => toggle(normalizedTimeRanges, timeRange, onTimeRangesChange)}
            >
              {TIME_RANGE_LABELS[timeRange]}
            </Chip>
          ))}
        </div>
      </div>
    </div>
  );
}
