"use client";

import Link from "next/link";
import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

import { COURT_SETTING_LABELS, SURFACE_LABELS } from "@/lib/constants";
import { Chip } from "@/components/ui/chip";
import { Panel } from "@/components/ui/panel";
import { CourtsMap } from "@/components/maps/courts-map";

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
};

export function CourtsBrowser({ courts }: { courts: Court[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [mode, setMode] = useState<"list" | "map">("list");

  function update(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (!value) params.delete(key);
    else params.set(key, value);
    router.replace(`${pathname}?${params.toString()}`);
  }

  return (
    <div className="space-y-4">
      <Panel className="space-y-3">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Фильтры кортов</div>
            <div className="mt-1 text-sm text-ink/70">Выбери место до отправки предложения.</div>
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
                <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">{SURFACE_LABELS[court.surface]}</span>
                <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">{court.priceRange}</span>
                {court.rating ? (
                  <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                    Рейтинг {court.rating.toFixed(1)}
                  </span>
                ) : null}
              </div>
              <Link href={`/play/proposals/new?courtId=${court.id}`}>
                <div className="rounded-2xl bg-ink px-4 py-3 text-center text-sm font-semibold text-white">
                  Выбрать этот корт
                </div>
              </Link>
            </Panel>
          ))}
        </div>
      )}
    </div>
  );
}
