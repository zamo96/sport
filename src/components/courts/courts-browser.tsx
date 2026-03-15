"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { MapPinned } from "lucide-react";

import { COURT_SETTING_LABELS, SURFACE_LABELS } from "@/lib/constants";
import { Chip } from "@/components/ui/chip";
import { Panel } from "@/components/ui/panel";

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

  const mapPoints = useMemo(() => {
    if (courts.length === 0) return [];
    const lats = courts.map((court) => court.locationLat);
    const lngs = courts.map((court) => court.locationLng);
    const minLat = Math.min(...lats);
    const maxLat = Math.max(...lats);
    const minLng = Math.min(...lngs);
    const maxLng = Math.max(...lngs);

    return courts.map((court) => ({
      ...court,
      top: `${20 + ((maxLat - court.locationLat) / Math.max(maxLat - minLat, 0.01)) * 60}%`,
      left: `${12 + ((court.locationLng - minLng) / Math.max(maxLng - minLng, 0.01)) * 76}%`
    }));
  }, [courts]);

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
        <Panel className="relative h-[420px] overflow-hidden bg-[linear-gradient(180deg,#D8F0E3_0%,#C2E7D4_38%,#FFF4E6_100%)]">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(201,109,66,0.18),transparent_40%)]" />
          <div className="absolute inset-x-6 top-6 rounded-2xl bg-white/80 px-4 py-3 text-sm text-ink/70 backdrop-blur">
            Временная карта для MVP без привязки к провайдеру. Позже можно подключить Mapbox, Google или Яндекс.
          </div>
          {mapPoints.map((court) => (
            <Link
              href={`/play/proposals/new?courtId=${court.id}`}
              key={court.id}
              className="absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center"
              style={{ top: court.top, left: court.left }}
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-clay text-white shadow-glow">
                <MapPinned className="h-5 w-5" />
              </div>
              <div className="mt-2 rounded-full bg-white px-3 py-2 text-[11px] font-semibold text-ink shadow-card">
                {court.name}
              </div>
            </Link>
          ))}
        </Panel>
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
