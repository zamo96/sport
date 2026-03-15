"use client";

import { useEffect, useMemo, useRef, useState } from "react";

import { getYandexMapsApiKey } from "@/lib/maps/config";
import { loadYandexMaps } from "@/lib/maps/yandex";
import { Panel } from "@/components/ui/panel";

type CourtMapPoint = {
  id: string;
  name: string;
  address: string;
  locationLat: number;
  locationLng: number;
};

export function YandexCourtsMap({ courts }: { courts: CourtMapPoint[] }) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const apiKey = getYandexMapsApiKey();
  const initialLocation = useMemo(() => {
    if (courts.length === 0) {
      return {
        center: [37.6173, 55.7558] as [number, number],
        zoom: 10
      };
    }

    const avgLat = courts.reduce((sum, court) => sum + court.locationLat, 0) / courts.length;
    const avgLng = courts.reduce((sum, court) => sum + court.locationLng, 0) / courts.length;

    return {
      center: [avgLng, avgLat] as [number, number],
      zoom: courts.length === 1 ? 13 : 11
    };
  }, [courts]);

  useEffect(() => {
    let mapInstance: { destroy: () => void } | null = null;
    let cancelled = false;

    async function initMap() {
      if (!containerRef.current) {
        return;
      }

      if (!apiKey) {
        setError("Добавь NEXT_PUBLIC_YANDEX_MAPS_API_KEY, чтобы включить карту.");
        return;
      }

      try {
        const ymaps3 = await loadYandexMaps(apiKey, "ru_RU");
        if (cancelled || !containerRef.current) {
          return;
        }

        const { YMap, YMapDefaultSchemeLayer, YMapDefaultFeaturesLayer, YMapMarker } = ymaps3;
        const map = new YMap(containerRef.current, {
          location: initialLocation,
          behaviors: ["drag", "pinchZoom", "dblClick", "scrollZoom"]
        });

        map.addChild(new YMapDefaultSchemeLayer({ theme: "light" }));
        map.addChild(new YMapDefaultFeaturesLayer());

        for (const court of courts) {
          const markerElement = document.createElement("a");
          markerElement.href = `/play/proposals/new?courtId=${court.id}`;
          markerElement.className = "group flex -translate-y-full flex-col items-center text-center no-underline";
          markerElement.innerHTML = `
            <span class="flex h-11 w-11 items-center justify-center rounded-full bg-[#C96D42] text-white shadow-lg ring-4 ring-white/90 transition group-hover:scale-105">
              <span style="font-size:18px;line-height:1">🎾</span>
            </span>
            <span class="mt-2 max-w-[170px] rounded-full bg-white px-3 py-2 text-[11px] font-semibold text-[#142F26] shadow-md">
              ${escapeHtml(court.name)}
            </span>
          `;
          markerElement.title = `${court.name} — ${court.address}`;

          map.addChild(
            new YMapMarker(
              {
                coordinates: [court.locationLng, court.locationLat]
              },
              markerElement
            )
          );
        }

        mapInstance = map;
        setError(null);
      } catch (mapError) {
        if (!cancelled) {
          setError(mapError instanceof Error ? mapError.message : "Не удалось загрузить Яндекс Карты.");
        }
      }
    }

    initMap();

    return () => {
      cancelled = true;
      mapInstance?.destroy();
    };
  }, [apiKey, courts, initialLocation]);

  if (error) {
    return <Panel className="text-sm leading-6 text-ink/70">{error}</Panel>;
  }

  return <div ref={containerRef} className="h-[420px] w-full overflow-hidden rounded-[28px]" />;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
