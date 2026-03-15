"use client";

import {
  DAY_LABELS,
  DAY_OPTIONS,
  TIME_RANGE_LABELS,
  TIME_RANGE_OPTIONS
} from "@/lib/constants";
import { Chip } from "@/components/ui/chip";

export function AvailabilityPicker({
  days,
  timeRanges,
  onDaysChange,
  onTimeRangesChange,
  hideDays = false
}: {
  days: string[];
  timeRanges: string[];
  onDaysChange: (value: string[]) => void;
  onTimeRangesChange: (value: string[]) => void;
  hideDays?: boolean;
}) {
  function toggle(values: string[], value: string, setter: (value: string[]) => void) {
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
                active={days.includes(day)}
                onClick={() => toggle(days, day, onDaysChange)}
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
              active={timeRanges.includes(timeRange)}
              onClick={() => toggle(timeRanges, timeRange, onTimeRangesChange)}
            >
              {TIME_RANGE_LABELS[timeRange]}
            </Chip>
          ))}
        </div>
      </div>
    </div>
  );
}
