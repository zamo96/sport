"use client";

import Link from "next/link";
import { Search, Sparkles } from "lucide-react";
import { useMemo, useState } from "react";
import type { Sport } from "@prisma/client";

import {
  DEFAULT_CITY,
  DISTRICT_LABELS,
  DISTRICT_SEARCH_HINTS,
  SPORT_LABELS,
  SPORT_OPTIONS
} from "@/lib/constants";
import { normalizeCourtSports } from "@/lib/courts";
import { cn } from "@/lib/utils";
import { CourtsMap } from "@/components/maps/courts-map";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";

type Court = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  priceRange: string;
  rating: number | null;
  distanceLabel: string;
  distanceKm: number | null;
  locationLat: number;
  locationLng: number;
  sourceType: string;
  supportedSports?: unknown;
};

type CourtsBrowserProps = {
  courts: Court[];
  userDistrict?: string | null;
  searchRadiusKm: number;
  profileSports: Sport[];
  initialQuery?: string;
  initialSport?: Sport | null;
};

export function CourtsBrowser({
  courts,
  userDistrict,
  searchRadiusKm,
  profileSports,
  initialQuery = "",
  initialSport = null
}: CourtsBrowserProps) {
  const [searchInput, setSearchInput] = useState(initialQuery);
  const [selectedSport, setSelectedSport] = useState<Sport | null>(initialSport ?? profileSports[0] ?? null);

  const visibleSports = useMemo(() => {
    const base = profileSports.length > 0 ? profileSports : SPORT_OPTIONS;
    return Array.from(new Set(base));
  }, [profileSports]);

  const smartSuggestions = useMemo(() => {
    const districtLabel =
      userDistrict && userDistrict in DISTRICT_LABELS
        ? DISTRICT_LABELS[userDistrict as keyof typeof DISTRICT_LABELS]
        : null;
    const sportLabel = selectedSport ? SPORT_LABELS[selectedSport] : null;
    const dynamic = [
      sportLabel ? `${sportLabel} рядом` : null,
      sportLabel && districtLabel ? `${sportLabel} ${districtLabel}` : null,
      districtLabel ? `${districtLabel}` : null,
      ...DISTRICT_SEARCH_HINTS.slice(0, 4)
    ].filter((value): value is string => Boolean(value));

    return Array.from(new Set(dynamic)).slice(0, 6);
  }, [selectedSport, userDistrict]);

  const searchSuggestions = useMemo(() => {
    const normalized = searchInput.trim().toLowerCase();
    const baseSuggestions = courts.flatMap((court) => [
      court.name,
      court.address,
      court.district ? DISTRICT_LABELS[court.district as keyof typeof DISTRICT_LABELS] ?? court.district : null
    ]);

    return Array.from(new Set(baseSuggestions.filter((item): item is string => Boolean(item))))
      .filter((item) => !normalized || item.toLowerCase().includes(normalized))
      .slice(0, 6);
  }, [courts, searchInput]);

  const filteredCourts = useMemo(() => {
    const normalizedQuery = searchInput.trim().toLowerCase();

    return courts.filter((court) => {
      const supportsSport = !selectedSport || normalizeCourtSports(court.supportedSports).includes(selectedSport);
      const haystack = [
        court.name,
        court.address,
        court.district ? DISTRICT_LABELS[court.district as keyof typeof DISTRICT_LABELS] ?? court.district : ""
      ]
        .join(" ")
        .toLowerCase();
      const matchesQuery = !normalizedQuery || haystack.includes(normalizedQuery);

      return supportsSport && matchesQuery;
    });
  }, [courts, searchInput, selectedSport]);

  return (
    <div className="space-y-4">
      <Panel className="space-y-4 overflow-hidden">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Спортивные центры</div>
            <div className="mt-1 text-sm leading-6 text-ink/72">
              Собственная база клубов и площадок в {DEFAULT_CITY}. Карта видна сразу, а поиск подсказывает варианты по мере ввода.
            </div>
          </div>
          <div className="rounded-[22px] bg-mint px-3 py-2 text-right">
            <div className="text-[11px] uppercase tracking-[0.18em] text-court">Радиус</div>
            <div className="mt-1 font-bold text-ink">{searchRadiusKm} км</div>
          </div>
        </div>

        <div className="space-y-3">
          <div className="relative">
            <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/40" />
            <input
              value={searchInput}
              onChange={(event) => setSearchInput(event.target.value)}
              className="input pl-11"
              placeholder={
                selectedSport
                  ? `${SPORT_LABELS[selectedSport]} в удобном районе, у метро или по названию клуба`
                  : "Клуб, адрес, метро или район"
              }
            />
          </div>

          <div className="flex flex-wrap gap-2">
            {smartSuggestions.map((suggestion) => (
              <button
                key={suggestion}
                type="button"
                onClick={() => setSearchInput(suggestion)}
                className="inline-flex items-center gap-2 rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink"
              >
                <Sparkles className="h-3.5 w-3.5 text-court" />
                {suggestion}
              </button>
            ))}
          </div>

          {searchInput ? (
            <div className="rounded-[24px] border border-line bg-white/90 p-2 shadow-card">
              <div className="px-2 pb-2 pt-1 text-[11px] font-semibold uppercase tracking-[0.2em] text-ink/45">
                Подсказки
              </div>
              <div className="space-y-1">
                {searchSuggestions.length === 0 ? (
                  <div className="rounded-2xl px-3 py-2 text-sm text-ink/55">Ничего не подсказали, попробуй район или название клуба.</div>
                ) : (
                  searchSuggestions.map((suggestion) => (
                    <button
                      key={suggestion}
                      type="button"
                      onClick={() => setSearchInput(suggestion)}
                      className="block w-full rounded-2xl px-3 py-2 text-left text-sm font-medium text-ink transition hover:bg-cream"
                    >
                      {suggestion}
                    </button>
                  ))
                )}
              </div>
            </div>
          ) : null}
        </div>

        <div className="flex gap-2 overflow-x-auto pb-1">
          {visibleSports.map((sport) => {
            const active = selectedSport === sport;

            return (
              <button
                key={sport}
                type="button"
                onClick={() => setSelectedSport(active ? null : sport)}
                className={cn(
                  "rounded-full border px-1.5 py-1 transition",
                  active ? "border-ink bg-ink" : "border-white/60 bg-white/85"
                )}
              >
                <SportBadge
                  sport={sport}
                  className={active ? "bg-transparent px-2 py-1 text-white" : "bg-transparent px-2 py-1 text-ink"}
                  iconClassName={active ? "h-3.5 w-3.5 text-white" : "h-3.5 w-3.5 text-ink"}
                />
              </button>
            );
          })}
        </div>

        <CourtsMap courts={filteredCourts} district={userDistrict} radiusKm={searchRadiusKm} />
      </Panel>

      <div className="space-y-3">
        {filteredCourts.length === 0 ? (
          <Panel className="text-center">
            <div className="text-xl font-bold text-ink">Подходящих центров пока нет</div>
            <div className="mt-2 text-sm leading-6 text-ink/65">
              Попробуй убрать текст запроса или сменить вид спорта.
            </div>
          </Panel>
        ) : null}

        {filteredCourts.map((court) => (
          <Panel key={court.id} className="space-y-3">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">
                  {court.district ? DISTRICT_LABELS[court.district as keyof typeof DISTRICT_LABELS] ?? court.district : DEFAULT_CITY}
                </div>
                <div className="mt-1 text-xl font-bold text-ink">{court.name}</div>
                <div className="mt-1 text-sm leading-6 text-ink/65">{court.address}</div>
              </div>
              <div className="rounded-[22px] bg-mint px-3 py-2 text-right">
                <div className="text-[11px] uppercase tracking-[0.18em] text-court">Расстояние</div>
                <div className="mt-1 font-bold text-ink">{court.distanceLabel}</div>
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              {normalizeCourtSports(court.supportedSports).map((sport) => (
                <SportBadge key={sport} sport={sport as Sport} className="bg-cream text-ink" />
              ))}
              <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">{court.priceRange}</span>
              {court.rating ? (
                <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                  Рейтинг {court.rating.toFixed(1)}
                </span>
              ) : null}
            </div>

            <Link href={`/play/proposals/new?courtId=${court.id}`}>
              <div className="rounded-2xl bg-ink px-4 py-3 text-center text-sm font-semibold text-white">
                Выбрать этот центр
              </div>
            </Link>
          </Panel>
        ))}
      </div>
    </div>
  );
}
