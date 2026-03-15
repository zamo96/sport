"use client";

import { useMemo } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

import { DAY_LABELS, DAY_OPTIONS, GENDER_LABELS, PLAY_FORMAT_LABELS, SPORT_OPTIONS, SURFACE_LABELS, TIME_RANGE_LABELS, TIME_RANGE_OPTIONS } from "@/lib/constants";
import { Chip } from "@/components/ui/chip";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";

export function FiltersBar() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const filters = useMemo(
    () => ({
      city: searchParams.get("city") || "",
      gender: parseMulti(searchParams.get("gender")),
      sport: parseMulti(searchParams.get("sport")),
      format: parseMulti(searchParams.get("format")),
      surface: parseMulti(searchParams.get("surface")),
      day: parseMulti(searchParams.get("day")),
      timeRange: parseMulti(searchParams.get("timeRange")),
      distanceKm: searchParams.get("distanceKm") || "20",
      levelMin: searchParams.get("levelMin") || "",
      levelMax: searchParams.get("levelMax") || ""
    }),
    [searchParams]
  );

  function update(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (!value) {
      params.delete(key);
    } else {
      params.set(key, value);
    }

    router.replace(`${pathname}?${params.toString()}`);
  }

  function toggleMulti(key: string, value: string) {
    const current = parseMulti(searchParams.get(key));
    const next = current.includes(value) ? current.filter((item) => item !== value) : [...current, value];
    update(key, next.join(","));
  }

  return (
    <Panel className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.24em] text-ink/55">Фильтры</div>
          <div className="mt-1 text-sm text-ink/70">Настрой выдачу по городу, полу, уровню, расстоянию и времени игры.</div>
        </div>
        <button
          type="button"
          className="text-xs font-semibold text-clay"
          onClick={() => {
            const params = new URLSearchParams(searchParams.toString());
            const view = params.get("view");
            params.forEach((_, key) => {
              if (key !== "view") {
                params.delete(key);
              }
            });
            if (view) {
              params.set("view", view);
            }
            router.replace(params.toString() ? `${pathname}?${params.toString()}` : pathname);
          }}
        >
          Сбросить
        </button>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <label>
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">Город</div>
          <input
            className="input"
            type="text"
            placeholder="Москва"
            value={filters.city}
            onChange={(event) => update("city", event.target.value)}
          />
        </label>
        <div>
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">Пол</div>
          <div className="flex flex-wrap gap-2">
            {(["male", "female", "other"] as const).map((gender) => (
              <Chip key={gender} active={filters.gender.includes(gender)} onClick={() => toggleMulti("gender", gender)}>
                {GENDER_LABELS[gender]}
              </Chip>
            ))}
          </div>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {SPORT_OPTIONS.map((sport) => (
          <button
            key={sport}
            type="button"
            onClick={() => toggleMulti("sport", sport)}
            className={`rounded-full border px-1.5 py-1 transition ${filters.sport.includes(sport) ? "border-ink bg-ink" : "border-white/60 bg-white/80"}`}
          >
            <SportBadge
              sport={sport}
              className={filters.sport.includes(sport) ? "bg-transparent px-2 py-1 text-white" : "bg-transparent px-2 py-1 text-ink"}
              iconClassName={filters.sport.includes(sport) ? "h-3.5 w-3.5 text-white" : "h-3.5 w-3.5 text-ink"}
            />
          </button>
        ))}
      </div>

      <div className="flex flex-wrap gap-2">
        {(["singles", "doubles", "both"] as const).map((format) => (
          <Chip key={format} active={filters.format.includes(format)} onClick={() => toggleMulti("format", format)}>
            {PLAY_FORMAT_LABELS[format]}
          </Chip>
        ))}
      </div>

      <div className="flex flex-wrap gap-2">
        {(["hard", "clay", "grass", "any"] as const).map((surface) => (
          <Chip
            key={surface}
            active={filters.surface.includes(surface)}
            onClick={() => toggleMulti("surface", surface)}
          >
            {SURFACE_LABELS[surface]}
          </Chip>
        ))}
      </div>

      <div className="overflow-x-auto pb-1">
        <div className="flex gap-2">
          {DAY_OPTIONS.map((day) => (
            <Chip
              key={day}
              active={filters.day.includes(day)}
              onClick={() => toggleMulti("day", day)}
              className="whitespace-nowrap"
            >
              {DAY_LABELS[day]}
            </Chip>
          ))}
        </div>
      </div>

      <div className="overflow-x-auto pb-1">
        <div className="flex gap-2">
          {TIME_RANGE_OPTIONS.map((timeRange) => (
            <Chip
              key={timeRange}
              active={filters.timeRange.includes(timeRange)}
              onClick={() => toggleMulti("timeRange", timeRange)}
              className="whitespace-nowrap"
            >
              {TIME_RANGE_LABELS[timeRange]}
            </Chip>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <label>
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">Км</div>
          <input
            className="input"
            type="number"
            value={filters.distanceKm}
            onChange={(event) => update("distanceKm", event.target.value)}
          />
        </label>
        <label>
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">Уровень от</div>
          <input
            className="input"
            type="number"
            min={1}
            max={10}
            value={filters.levelMin}
            onChange={(event) => update("levelMin", event.target.value)}
          />
        </label>
        <label>
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">Уровень до</div>
          <input
            className="input"
            type="number"
            min={1}
            max={10}
            value={filters.levelMax}
            onChange={(event) => update("levelMax", event.target.value)}
          />
        </label>
      </div>
    </Panel>
  );
}

function parseMulti(value: string | null) {
  if (!value) {
    return [];
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}
