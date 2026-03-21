"use client";

import { DAY_LABELS, DAY_OPTIONS, TIME_RANGE_LABELS, TIME_RANGE_OPTIONS } from "@/lib/constants";
import { Chip } from "@/components/ui/chip";

type AvailabilityByDay = Partial<Record<(typeof DAY_OPTIONS)[number], (typeof TIME_RANGE_OPTIONS)[number][]>>;

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
  if (availabilityByDay && onAvailabilityByDayChange) {
    return (
      <div className="space-y-4">
        <div className="rounded-[24px] bg-cream p-4">
          <div className="text-sm font-semibold text-ink">Выбери время отдельно по каждому дню</div>
          <div className="mt-1 text-xs leading-5 text-ink/60">
            Нажимай только те окна, когда тебе реально удобно играть. Пустой день не попадёт в поиск.
          </div>
        </div>

        <div className="space-y-3">
          {DAY_OPTIONS.map((day) => {
            const selectedRanges = availabilityByDay[day] ?? [];

            return (
              <div key={day} className="rounded-[24px] bg-white/85 p-3">
                <div className="mb-2 flex items-center justify-between gap-3">
                  <div className="text-sm font-semibold text-ink">{DAY_LABELS[day]}</div>
                  {selectedRanges.length > 0 ? (
                    <button
                      type="button"
                      onClick={() => onAvailabilityByDayChange({ ...availabilityByDay, [day]: [] })}
                      className="text-xs font-semibold text-clay"
                    >
                      Очистить
                    </button>
                  ) : (
                    <span className="text-xs text-ink/45">Не выбрано</span>
                  )}
                </div>
                <div className="flex flex-wrap gap-2">
                  {TIME_RANGE_OPTIONS.map((timeRange) => (
                    <Chip
                      key={timeRange}
                      active={selectedRanges.includes(timeRange)}
                      onClick={() =>
                        onAvailabilityByDayChange({
                          ...availabilityByDay,
                          [day]: selectedRanges.includes(timeRange)
                            ? selectedRanges.filter((item) => item !== timeRange)
                            : [...selectedRanges, timeRange]
                        })
                      }
                    >
                      {TIME_RANGE_LABELS[timeRange]}
                    </Chip>
                  ))}
                </div>
              </div>
            );
          })}
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
