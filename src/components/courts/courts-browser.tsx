"use client";

import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Search, Sparkles, X } from "lucide-react";
import type { Sport } from "@prisma/client";

import { COURT_SETTING_LABELS, DEFAULT_CITY, SPORT_LABELS, SPORT_OPTIONS, SURFACE_LABELS } from "@/lib/constants";
import { normalizeCourtSports } from "@/lib/courts";
import { Chip } from "@/components/ui/chip";
import { Panel } from "@/components/ui/panel";
import { CourtsMap } from "@/components/maps/courts-map";
import { SportBadge } from "@/components/ui/sport-badge";

type Court = {
  id: string;
  name: string;
  address: string;
  surface: "hard" | "clay" | "grass" | "any";
  setting: "indoor" | "outdoor";
  priceRange: string;
  rating: number | null;
  distanceLabel: string;
  distanceKm: number | null;
  locationLat: number;
  locationLng: number;
  sourceType: string;
  supportedSports?: unknown;
};

export function CourtsBrowser({ courts }: { courts: Court[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [mode, setMode] = useState<"list" | "map">("list");
  const [searchInput, setSearchInput] = useState(searchParams.get("q") || "");
  const selectedSport = searchParams.get("sport");

  useEffect(() => {
    setSearchInput(searchParams.get("q") || "");
  }, [searchParams]);

  function update(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (!value) params.delete(key);
    else params.set(key, value);
    router.replace(`${pathname}?${params.toString()}`);
  }

  function handleSearchSubmit(event: FormEvent) {
    event.preventDefault();
    update("q", searchInput.trim());
  }

  function applySmartSuggestion(value: string) {
    setSearchInput(value);
    update("q", value);
  }

  const smartSuggestions = selectedSport
    ? [
        SPORT_LABELS[selectedSport as Sport],
        `${SPORT_LABELS[selectedSport as Sport]} рядом`,
        `${SPORT_LABELS[selectedSport as Sport]} у метро`
      ]
    : ["Теннисный клуб", "Падел-клуб", "Футбольный клуб"];

  return (
    <div className="space-y-4">
      <Panel className="space-y-3">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Фильтры центров</div>
            <div className="mt-1 text-sm text-ink/70">Площадки и спортивные центры в {DEFAULT_CITY}. Отфильтруй по виду спорта и формату площадки.</div>
          </div>
          <div className="flex rounded-full bg-cream p-1">
            {(["list", "map"] as const).map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => setMode(value)}
                className={`rounded-full px-4 py-2 text-xs font-semibold uppercase tracking-[0.18em] ${mode === value ? "bg-ink text-white" : "text-ink/50"}`}
              >
                {value === "list" ? "список" : "карта"}
              </button>
            ))}
          </div>
        </div>
        <form onSubmit={handleSearchSubmit} className="space-y-3">
          <div>
            <div className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-court">Умный поиск</div>
            <div className="text-sm text-ink/70">Введи название клуба, район, метро или просто вид спорта. Поиск учитывает выбранный спорт и ищет и по базе, и по Яндекс Картам.</div>
          </div>
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/40" />
              <input
                value={searchInput}
                onChange={(event) => setSearchInput(event.target.value)}
                className="input pl-11 pr-11"
                placeholder={selectedSport ? `${SPORT_LABELS[selectedSport as Sport]} в центре или рядом с тобой` : "Например: Теннисный клуб, Петроградка, Крестовский"}
              />
              {searchInput ? (
                <button
                  type="button"
                  onClick={() => {
                    setSearchInput("");
                    update("q", "");
                  }}
                  className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full p-1 text-ink/45 transition hover:bg-cream"
                >
                  <X className="h-4 w-4" />
                </button>
              ) : null}
            </div>
            <button type="submit" className="rounded-2xl bg-ink px-4 py-3 text-sm font-semibold text-white">
              Найти
            </button>
          </div>
          <div className="flex flex-wrap gap-2">
            {smartSuggestions.map((suggestion) => (
              <button
                key={suggestion}
                type="button"
                onClick={() => applySmartSuggestion(suggestion)}
                className="inline-flex items-center gap-2 rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink"
              >
                <Sparkles className="h-3.5 w-3.5 text-court" />
                {suggestion}
              </button>
            ))}
          </div>
        </form>
        <div className="flex flex-wrap gap-2">
          {SPORT_OPTIONS.map((sport) => (
            <button
              key={sport}
              type="button"
              onClick={() => update("sport", searchParams.get("sport") === sport ? "" : sport)}
              className={`rounded-full border px-1.5 py-1 transition ${searchParams.get("sport") === sport ? "border-ink bg-ink" : "border-white/60 bg-white/80"}`}
            >
              <SportBadge
                sport={sport}
                className={searchParams.get("sport") === sport ? "bg-transparent px-2 py-1 text-white" : "bg-transparent px-2 py-1 text-ink"}
                iconClassName={searchParams.get("sport") === sport ? "h-3.5 w-3.5 text-white" : "h-3.5 w-3.5 text-ink"}
              />
            </button>
          ))}
        </div>
        <div className="flex flex-wrap gap-2">
          {(["hard", "clay", "grass", "any"] as const).map((surface) => (
            <Chip
              key={surface}
              active={searchParams.get("surface") === surface}
              onClick={() => update("surface", searchParams.get("surface") === surface ? "" : surface)}
            >
              {SURFACE_LABELS[surface]}
            </Chip>
          ))}
          {(["indoor", "outdoor"] as const).map((setting) => (
            <Chip
              key={setting}
              active={searchParams.get("setting") === setting}
              onClick={() => update("setting", searchParams.get("setting") === setting ? "" : setting)}
            >
              {COURT_SETTING_LABELS[setting]}
            </Chip>
          ))}
        </div>
      </Panel>

      {mode === "map" ? (
        <CourtsMap courts={courts} />
      ) : (
        <div className="space-y-3">
          {courts.length === 0 ? (
            <Panel className="text-center">
              <div className="text-xl font-bold text-ink">Ничего не найдено</div>
              <div className="mt-2 text-sm leading-6 text-ink/65">
                Попробуй изменить спортивный фильтр, район или текст запроса.
              </div>
            </Panel>
          ) : null}
          {courts.map((court) => (
            <Panel key={court.id} className="space-y-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">{COURT_SETTING_LABELS[court.setting]}</div>
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
                {court.sourceType !== "yandex_org_search" ? (
                  <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">{SURFACE_LABELS[court.surface]}</span>
                ) : (
                  <span className="rounded-full bg-mint px-3 py-2 text-xs font-semibold text-ink">Яндекс Карты</span>
                )}
                <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">{court.priceRange}</span>
                {court.rating ? (
                  <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                    Рейтинг {court.rating.toFixed(1)}
                  </span>
                ) : null}
              </div>
              <Link href={`/play/proposals/new?courtId=${court.id}`}>
                <div className="rounded-2xl bg-ink px-4 py-3 text-center text-sm font-semibold text-white">
                  Выбрать эту площадку
                </div>
              </Link>
            </Panel>
          ))}
        </div>
      )}
    </div>
  );
}
