"use client";

import Link from "next/link";
import { Building2, MapPinned, Search } from "lucide-react";
import { useMemo, useState } from "react";
import type { Sport } from "@prisma/client";

import {
  DEFAULT_CITY,
  getDistrictLabel,
  SPORT_LABELS,
  SPORT_OPTIONS
} from "@/lib/constants";
import { normalizeCourtSports } from "@/lib/courts";
import { buildCourtSearchTerms, matchesSearchTerms, normalizeSearchText } from "@/lib/search-text";
import { cn } from "@/lib/utils";
import { CourtsMap } from "@/components/maps/courts-map";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";
import { SportIcon } from "@/components/ui/sport-icon";

type Court = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  nearestMetroName?: string | null;
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

type SearchSuggestion = {
  id: string;
  type: "club" | "metro" | "district" | "sport";
  label: string;
  value: string;
  meta?: string | null;
  sport?: Sport;
  district?: string | null;
  center?: { lat: number; lng: number } | null;
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
  const [selectedSport, setSelectedSport] = useState<Sport | null>(initialSport ?? null);
  const [showSuggestions, setShowSuggestions] = useState(Boolean(initialQuery));
  const [mapFocus, setMapFocus] = useState<SearchSuggestion | null>(null);

  const visibleSports = useMemo(() => {
    const base = profileSports.length > 0 ? profileSports : SPORT_OPTIONS;
    return Array.from(new Set(base));
  }, [profileSports]);

  const searchSuggestions = useMemo(() => {
    const normalized = normalizeSearchText(searchInput);
    if (!normalized) {
      return [] as SearchSuggestion[];
    }

    const clubSuggestions: SearchSuggestion[] = courts
      .filter((court) =>
        matchesSearchTerms(
          buildCourtSearchTerms({
            name: court.name,
            address: court.address,
            district: court.district,
            nearestMetroName: court.nearestMetroName,
            sports: normalizeCourtSports(court.supportedSports)
          }),
          normalized
        )
      )
      .slice(0, 4)
      .map((court) => ({
        id: `club-${court.id}`,
        type: "club",
        label: court.name,
        value: court.name,
        center: { lat: court.locationLat, lng: court.locationLng },
        district: court.district ?? null,
        meta: [court.nearestMetroName, getDistrictLabel(court.district), normalizeCourtSports(court.supportedSports).slice(0, 2).map((sport) => SPORT_LABELS[sport]).join(" · ")]
          .filter(Boolean)
          .join(" · ")
      }));

    const metroSuggestions = Array.from(
      new Map(
        courts
          .filter((court) => court.nearestMetroName)
          .map((court) => [court.nearestMetroName as string, court])
      ).entries()
    )
      .filter(([metroName]) =>
        matchesSearchTerms(
          buildCourtSearchTerms({
            name: metroName,
            address: "",
            district: null,
            nearestMetroName: metroName,
            sports: []
          }),
          normalized
        )
      )
      .slice(0, 3)
      .map(([metroName, court]) => ({
        id: `metro-${metroName}`,
        type: "metro" as const,
        label: metroName,
        value: metroName,
        center: { lat: court.locationLat, lng: court.locationLng },
        district: court.district ?? null,
        meta: getDistrictLabel(court.district) ?? "Метро"
      }));

    const districtSuggestions = Array.from(
      new Set(courts.map((court) => getDistrictLabel(court.district)).filter((label): label is string => Boolean(label)))
    )
      .filter((districtLabel) =>
        matchesSearchTerms(
          buildCourtSearchTerms({
            name: districtLabel,
            address: "",
            district: districtLabel,
            nearestMetroName: null,
            sports: []
          }),
          normalized
        )
      )
      .slice(0, 3)
      .map((districtLabel) => ({
        id: `district-${districtLabel}`,
        type: "district" as const,
        label: districtLabel,
        value: districtLabel,
        district: courts.find((court) => getDistrictLabel(court.district) === districtLabel)?.district ?? null,
        center: (() => {
          const districtCourts = courts.filter((court) => getDistrictLabel(court.district) === districtLabel);
          if (districtCourts.length === 0) return null;
          return {
            lat: districtCourts.reduce((sum, court) => sum + court.locationLat, 0) / districtCourts.length,
            lng: districtCourts.reduce((sum, court) => sum + court.locationLng, 0) / districtCourts.length
          };
        })(),
        meta: "Район"
      }));

    const sportSuggestions = visibleSports
      .filter((sport) =>
        matchesSearchTerms(
          buildCourtSearchTerms({
            name: SPORT_LABELS[sport],
            address: "",
            district: null,
            nearestMetroName: null,
            sports: [sport]
          }),
          normalized
        )
      )
      .slice(0, 3)
      .map((sport) => ({
        id: `sport-${sport}`,
        type: "sport" as const,
        label: SPORT_LABELS[sport],
        value: SPORT_LABELS[sport],
        sport,
        meta: `${courts.filter((court) => normalizeCourtSports(court.supportedSports).includes(sport)).length} центров`
      }));

    return [...clubSuggestions, ...metroSuggestions, ...districtSuggestions, ...sportSuggestions].slice(0, 8);
  }, [courts, searchInput, visibleSports]);

  const filteredCourts = useMemo(() => {
    const normalizedQuery = normalizeSearchText(searchInput);

    return courts.filter((court) => {
      const supportsSport = !selectedSport || normalizeCourtSports(court.supportedSports).includes(selectedSport);
      const matchesQuery = matchesSearchTerms(
        buildCourtSearchTerms({
          name: court.name,
          address: court.address,
          district: court.district,
          nearestMetroName: court.nearestMetroName,
          sports: normalizeCourtSports(court.supportedSports)
        }),
        normalizedQuery
      );

      return supportsSport && matchesQuery;
    });
  }, [courts, searchInput, selectedSport]);

  function applySuggestion(suggestion: SearchSuggestion) {
    if (suggestion.type === "sport" && suggestion.sport) {
      setSelectedSport(suggestion.sport);
      setSearchInput("");
      setMapFocus(null);
    } else {
      setSearchInput(suggestion.value);
      setMapFocus(suggestion);
    }
    setShowSuggestions(false);
  }

  return (
    <div className="space-y-4">
      <Panel className="space-y-4 overflow-hidden">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Спортивные центры</div>
            <div className="mt-1 text-sm leading-6 text-ink/72">
              Собственная база клубов и площадок в {DEFAULT_CITY}. Карта видна сразу, а поиск подсказывает варианты по мере ввода.
            </div>
            <div className="mt-2 text-xs font-semibold uppercase tracking-[0.18em] text-ink/50">
              Найдено: {filteredCourts.length}
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
              onChange={(event) => {
                setSearchInput(event.target.value);
                setMapFocus(null);
                setShowSuggestions(true);
              }}
              onFocus={() => setShowSuggestions(Boolean(searchInput.trim()))}
              onBlur={() => {
                window.setTimeout(() => setShowSuggestions(false), 120);
              }}
              className="input pl-11"
            />
          </div>

          {searchInput && showSuggestions ? (
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
                      key={suggestion.id}
                      type="button"
                      onMouseDown={(event) => {
                        event.preventDefault();
                        applySuggestion(suggestion);
                      }}
                      className="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-left text-sm font-medium text-ink transition hover:bg-cream"
                    >
                      <SuggestionLeading suggestion={suggestion} />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate">{suggestion.label}</span>
                        {suggestion.meta ? <span className="block truncate text-xs font-medium text-ink/55">{suggestion.meta}</span> : null}
                      </span>
                      <span className="shrink-0 rounded-full bg-cream px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.16em] text-ink/55">
                        {suggestion.type === "club"
                          ? "Клуб"
                          : suggestion.type === "metro"
                            ? "Метро"
                            : suggestion.type === "district"
                              ? "Район"
                              : "Спорт"}
                      </span>
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
                onClick={() => {
                  setSelectedSport(active ? null : sport);
                  setMapFocus(null);
                }}
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

        <CourtsMap
          courts={filteredCourts}
          district={userDistrict}
          radiusKm={searchRadiusKm}
          focus={
            mapFocus?.type === "metro" && mapFocus.center
              ? {
                  type: "metro",
                  label: mapFocus.label,
                  center: mapFocus.center,
                  radiusKm: 3,
                  district: mapFocus.district ?? null
                }
              : mapFocus?.type === "district" && mapFocus.district
                ? {
                    type: "district",
                    label: mapFocus.label,
                    district: mapFocus.district,
                    center: mapFocus.center ?? null
                  }
                : mapFocus?.type === "club" && mapFocus.center
                  ? {
                      type: "club",
                      label: mapFocus.label,
                      center: mapFocus.center,
                      radiusKm: 1.5,
                      district: mapFocus.district ?? null
                    }
                  : null
          }
        />
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
                  {getDistrictLabel(court.district) ?? court.district ?? DEFAULT_CITY}
                </div>
                <div className="mt-1 text-xl font-bold text-ink">{court.name}</div>
                <div className="mt-1 text-sm leading-6 text-ink/65">{court.address}</div>
                {court.nearestMetroName ? (
                  <div className="mt-1 text-xs font-medium text-ink/55">Метро: {court.nearestMetroName}</div>
                ) : null}
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

function SuggestionLeading({ suggestion }: { suggestion: SearchSuggestion }) {
  if (suggestion.type === "sport" && suggestion.sport) {
    return (
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-mint text-court">
        <SportIcon sport={suggestion.sport} className="h-4 w-4" />
      </span>
    );
  }

  if (suggestion.type === "metro") {
    return (
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#FDE7E5] text-[#D14A3D]">
        <span className="text-sm font-bold">M</span>
      </span>
    );
  }

  if (suggestion.type === "district") {
    return (
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#EEF6FF] text-[#356AC3]">
        <MapPinned className="h-4 w-4" />
      </span>
    );
  }

  return (
    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-cream text-court">
      <Building2 className="h-4 w-4" />
    </span>
  );
}
