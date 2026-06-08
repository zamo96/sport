"use client";

import Link from "next/link";
import { ArrowUp, Building2, ChevronDown, ChevronUp, MapPinned, Search } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
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
  phone?: string | null;
  workingHours?: string | null;
  yandexMapsUrl?: string | null;
  websiteUrl?: string | null;
  bookingUrl?: string | null;
  photoUrl?: string | null;
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
  const [expandedCourtId, setExpandedCourtId] = useState<string | null>(null);
  const [showBackToTop, setShowBackToTop] = useState(false);
  const topRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<HTMLDivElement | null>(null);

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

  const courtSections = useMemo(() => {
    const sections: Array<{ letter: string; courts: Court[] }> = [];
    const sectionByLetter = new Map<string, Court[]>();
    const alphabetizedCourts = [...filteredCourts].sort((left, right) => left.name.localeCompare(right.name, "ru-RU"));

    for (const court of alphabetizedCourts) {
      const letter = getCourtLetter(court.name);
      const section = sectionByLetter.get(letter) ?? [];
      section.push(court);
      sectionByLetter.set(letter, section);
    }

    for (const [letter, sectionCourts] of sectionByLetter.entries()) {
      sections.push({ letter, courts: sectionCourts });
    }

    return sections;
  }, [filteredCourts]);

  const alphabetLetters = courtSections.map((section) => section.letter);

  useEffect(() => {
    function handleScroll() {
      setShowBackToTop(window.scrollY > 640);
    }

    handleScroll();
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  useEffect(() => {
    if (expandedCourtId && !filteredCourts.some((court) => court.id === expandedCourtId)) {
      setExpandedCourtId(null);
    }
  }, [expandedCourtId, filteredCourts]);

  function applySuggestion(suggestion: SearchSuggestion) {
    if (suggestion.type === "sport" && suggestion.sport) {
      setSelectedSport(suggestion.sport);
      setSearchInput("");
      setMapFocus(null);
    } else {
      setSearchInput(suggestion.value);
      setMapFocus(suggestion);
      window.setTimeout(() => {
        mapRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 0);
    }
    setShowSuggestions(false);
  }

  function focusCourtOnMap(court: Court) {
    setShowSuggestions(false);
    setMapFocus({
      id: `club-${court.id}`,
      type: "club",
      label: court.name,
      value: court.name,
      center: { lat: court.locationLat, lng: court.locationLng },
      district: court.district ?? null,
      meta: [court.nearestMetroName, getDistrictLabel(court.district)].filter(Boolean).join(" · ")
    });

    window.setTimeout(() => {
      mapRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 0);
  }

  function scrollToTop() {
    topRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function scrollToLetter(letter: string) {
    document.getElementById(`court-section-${encodeURIComponent(letter)}`)?.scrollIntoView({
      behavior: "smooth",
      block: "start"
    });
  }

  return (
    <div ref={topRef} className="space-y-4">
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

        <div ref={mapRef} className="scroll-mt-4">
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
                        courtId: mapFocus.id.replace("club-", ""),
                        label: mapFocus.label,
                        center: mapFocus.center,
                        radiusKm: 1.5,
                        district: mapFocus.district ?? null
                      }
                    : null
            }
          />
        </div>
      </Panel>

      {alphabetLetters.length >= 6 ? (
        <div className="fixed right-2 top-1/2 z-20 flex max-h-[56vh] -translate-y-1/2 flex-col gap-1 overflow-y-auto rounded-full border border-white/80 bg-white/90 p-1 shadow-card backdrop-blur">
          {alphabetLetters.map((letter) => (
            <button
              key={letter}
              type="button"
              onClick={() => scrollToLetter(letter)}
              className="flex h-7 w-7 items-center justify-center rounded-full text-[11px] font-bold text-court transition hover:bg-mint"
              aria-label={`Перейти к клубам на ${letter}`}
            >
              {letter}
            </button>
          ))}
        </div>
      ) : null}

      <div className="space-y-3">
        {filteredCourts.length === 0 ? (
          <Panel className="text-center">
            <div className="text-xl font-bold text-ink">Подходящих центров пока нет</div>
            <div className="mt-2 text-sm leading-6 text-ink/65">
              Попробуй убрать текст запроса или сменить вид спорта.
            </div>
          </Panel>
        ) : null}

        {courtSections.map((section) => (
          <div key={section.letter} id={`court-section-${encodeURIComponent(section.letter)}`} className="scroll-mt-4 space-y-3">
            <div className="sticky top-2 z-10 inline-flex h-8 min-w-8 items-center justify-center rounded-full bg-white/95 px-3 text-xs font-bold text-court shadow-card">
              {section.letter}
            </div>
            {section.courts.map((court) => {
              const expanded = expandedCourtId === court.id;

              return (
                <Panel key={court.id} className="space-y-3">
                  {court.photoUrl ? (
                    <div
                      className="h-40 rounded-[22px] bg-cover bg-center shadow-[inset_0_-60px_80px_rgba(0,0,0,0.16)]"
                      style={{ backgroundImage: `url("${court.photoUrl}")` }}
                    />
                  ) : null}

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

                  {expanded ? (
                    <div className="grid gap-2 rounded-[20px] bg-cream/80 p-3 text-sm leading-6 text-ink/70 sm:grid-cols-2">
                      {court.workingHours ? <div>Часы: <span className="font-semibold text-ink">{court.workingHours}</span></div> : null}
                      {court.phone ? <div>Телефон: <span className="font-semibold text-ink">{court.phone}</span></div> : null}
                      {court.websiteUrl ? (
                        <a href={court.websiteUrl} target="_blank" rel="noreferrer" className="font-semibold text-court">
                          Сайт клуба
                        </a>
                      ) : null}
                      {court.bookingUrl ? (
                        <a href={court.bookingUrl} target="_blank" rel="noreferrer" className="font-semibold text-court">
                          Бронирование
                        </a>
                      ) : null}
                    </div>
                  ) : null}

                  <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                    <button
                      type="button"
                      onClick={() => focusCourtOnMap(court)}
                      className="inline-flex min-h-12 items-center justify-center gap-2 rounded-2xl bg-white/85 px-4 text-sm font-semibold text-ink shadow-[0_8px_20px_rgba(17,38,29,0.06)] transition hover:bg-white"
                    >
                      <MapPinned className="h-4 w-4 text-court" />
                      На карте
                    </button>
                    <Link href={buildProposalHref(court, selectedSport)} className="sm:col-span-2">
                      <div className="flex min-h-12 items-center justify-center rounded-2xl bg-ink px-4 text-center text-sm font-semibold text-white">
                        Предложить игру здесь
                      </div>
                    </Link>
                  </div>

                  <button
                    type="button"
                    onClick={() => setExpandedCourtId(expanded ? null : court.id)}
                    className="inline-flex items-center gap-2 text-sm font-semibold text-court"
                  >
                    {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                    {expanded ? "Скрыть детали" : "Подробнее о клубе"}
                  </button>
                </Panel>
              );
            })}
          </div>
        ))}
      </div>

      {showBackToTop ? (
        <button
          type="button"
          onClick={scrollToTop}
          className="fixed bottom-24 right-4 z-30 flex h-12 w-12 items-center justify-center rounded-full bg-ink text-white shadow-card transition hover:scale-105"
          aria-label="Вернуться наверх"
        >
          <ArrowUp className="h-5 w-5" />
        </button>
      ) : null}
    </div>
  );
}

function buildProposalHref(court: Court, selectedSport: Sport | null) {
  const courtSports = normalizeCourtSports(court.supportedSports);
  const sport = selectedSport && courtSports.includes(selectedSport) ? selectedSport : courtSports[0] ?? null;
  const params = new URLSearchParams({ courtId: court.id });

  if (sport) {
    params.set("sport", sport);
  }

  return `/play/proposals/new?${params.toString()}`;
}

function getCourtLetter(name: string) {
  const normalized = name.trim().normalize("NFKD").replace(/^[^\p{L}\p{N}]+/u, "");
  const first = normalized[0]?.toLocaleUpperCase("ru-RU") ?? "#";

  if (first === "Ё") {
    return "Е";
  }

  return /[\p{L}\p{N}]/u.test(first) ? first : "#";
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
