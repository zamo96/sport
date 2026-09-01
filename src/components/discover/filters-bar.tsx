"use client";

import { useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { ChevronDown, SlidersHorizontal } from "lucide-react";
import type { Sport } from "@prisma/client";

import {
  AVAILABLE_CITIES,
  DAY_OPTIONS,
  DEFAULT_CITY,
  SPORT_OPTIONS,
  TIME_RANGE_OPTIONS
} from "@/lib/constants";
import { Chip } from "@/components/ui/chip";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";
import { useLocale } from "@/components/i18n/locale-provider";
import {
  getDiscoverDayLabel,
  getDiscoverFormatLabel,
  getDiscoverGenderLabel,
  getDiscoverSurfaceLabel,
  getDiscoverTimeLabel,
  translateDiscover
} from "@/lib/i18n/web/discover";

export function FiltersBar({ profileSports }: { profileSports: Sport[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const { locale } = useLocale();
  const t = (key: Parameters<typeof translateDiscover>[1], values?: Parameters<typeof translateDiscover>[2]) =>
    translateDiscover(locale, key, values);

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

  const singleSelectedSport =
    filters.sport.length === 1 && SPORT_OPTIONS.includes(filters.sport[0] as Sport)
      ? (filters.sport[0] as Sport)
      : null;

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

  const activeCount = [
    filters.gender.length,
    filters.sport.length,
    filters.format.length,
    filters.surface.length,
    filters.day.length,
    filters.timeRange.length,
    filters.levelMin ? 1 : 0,
    filters.levelMax ? 1 : 0,
    filters.distanceKm && filters.distanceKm !== "20" ? 1 : 0
  ].reduce((sum, value) => sum + value, 0);

  return (
    <Panel className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.24em] text-ink/55">{t("discover.filters.title")}</div>
          <div className="mt-1 text-sm text-ink/70">{t("discover.filters.subtitle")}</div>
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
          {t("discover.filters.reset")}
        </button>
      </div>

      <div className="rounded-[24px] bg-cream/80 p-4">
        <div className="flex items-center justify-between gap-3">
          <div>
            <div className="text-sm font-bold text-ink">{t("discover.filters.quickTitle")}</div>
            <div className="mt-1 text-xs leading-5 text-ink/60">{t("discover.filters.quickText")}</div>
          </div>
          <span className="rounded-full bg-white px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
            {activeCount > 0 ? t("discover.filters.active", { count: activeCount }) : t("discover.filters.none")}
          </span>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          {(profileSports.length > 0 ? profileSports : SPORT_OPTIONS).map((sport) => (
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
      </div>

      <div className="grid grid-cols-2 gap-3">
        <label className="rounded-[22px] bg-cream/80 p-4">
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">{t("discover.filters.radius")}</div>
          <select className="input" value={filters.distanceKm} onChange={(event) => update("distanceKm", event.target.value)}>
            {["5", "10", "20", "30", "50", "100"].map((value) => (
              <option key={value} value={value}>
                {t("discover.filters.radiusValue", { value })}
              </option>
            ))}
          </select>
        </label>
        <div className="rounded-[22px] bg-cream/80 p-4">
          <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">{t("discover.filters.level")}</div>
          <div className="grid grid-cols-2 gap-2">
            <input
              className="input"
              type="number"
              min={1}
              max={10}
              value={filters.levelMin}
              onChange={(event) => update("levelMin", event.target.value)}
              placeholder={t("discover.filters.min")}
            />
            <input
              className="input"
              type="number"
              min={1}
              max={10}
              value={filters.levelMax}
              onChange={(event) => update("levelMax", event.target.value)}
              placeholder={t("discover.filters.max")}
            />
          </div>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {(["singles", "doubles", "both"] as const).map((format) => (
          <Chip key={format} active={filters.format.includes(format)} onClick={() => toggleMulti("format", format)}>
            {getDiscoverFormatLabel(locale, format)}
          </Chip>
        ))}
      </div>

      <button
        type="button"
        onClick={() => setAdvancedOpen((current) => !current)}
        className="flex w-full items-center justify-between rounded-[22px] bg-white/80 px-4 py-3 text-left"
      >
        <span className="inline-flex items-center gap-2 text-sm font-semibold text-ink">
          <SlidersHorizontal className="h-4 w-4" />
          {t("discover.filters.advanced")}
        </span>
        <span className={`transition ${advancedOpen ? "rotate-180" : ""}`}>
          <ChevronDown className="h-4 w-4 text-ink/55" />
        </span>
      </button>

      {advancedOpen ? (
        <div className="space-y-3 rounded-[24px] bg-white/70 p-4">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <label>
              <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">{t("discover.filters.city")}</div>
              <select className="input cursor-not-allowed bg-line/50 text-ink/70" value={DEFAULT_CITY} disabled>
                {AVAILABLE_CITIES.map((city) => (
                  <option key={city} value={city}>
                    {city}
                  </option>
                ))}
              </select>
              <div className="mt-2 text-xs leading-5 text-ink/55">{t("discover.filters.cityHint")}</div>
            </label>
            <div>
              <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">{t("discover.filters.gender")}</div>
              <div className="flex flex-wrap gap-2">
                {(["male", "female", "other"] as const).map((gender) => (
                  <Chip key={gender} active={filters.gender.includes(gender)} onClick={() => toggleMulti("gender", gender)}>
                    {getDiscoverGenderLabel(locale, gender)}
                  </Chip>
                ))}
              </div>
            </div>
          </div>

          <div className="flex flex-wrap gap-2">
            {(["hard", "clay", "grass", "any"] as const).map((surface) => (
              <Chip
                key={surface}
                active={filters.surface.includes(surface)}
                onClick={() => toggleMulti("surface", surface)}
              >
                {getDiscoverSurfaceLabel(locale, surface)}
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
                  {getDiscoverDayLabel(locale, day)}
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
                  {getDiscoverTimeLabel(locale, timeRange)}
                </Chip>
              ))}
            </div>
          </div>
        </div>
      ) : null}
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
