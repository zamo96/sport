"use client";

import type { Sport } from "@prisma/client";
import { useEffect, useMemo, useRef, useState } from "react";

import {
  DEFAULT_CITY_COORDINATES,
  DISTRICT_MAP_AREAS,
  SPORT_EMOJIS,
  SPORT_LABELS,
  type DistrictOption
} from "@/lib/constants";
import { getPrimaryCourtSport, normalizeCourtSports } from "@/lib/courts";
import { getYandexMapsApiKey } from "@/lib/maps/config";
import { loadYandexMaps } from "@/lib/maps/yandex";
import { Panel } from "@/components/ui/panel";

type CourtMapPoint = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  locationLat: number;
  locationLng: number;
  supportedSports?: unknown;
};

export function YandexCourtsMap({
  courts,
  district,
  radiusKm,
  compact = false
}: {
  courts: CourtMapPoint[];
  district?: string | null;
  radiusKm?: number;
  compact?: boolean;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const apiKey = getYandexMapsApiKey();
  const initialLocation = useMemo(() => {
    const districtCenter = district ? DISTRICT_MAP_AREAS[district as DistrictOption]?.center : null;

    if (courts.length === 0) {
      return {
        center: [
          districtCenter?.lng ?? DEFAULT_CITY_COORDINATES.lng,
          districtCenter?.lat ?? DEFAULT_CITY_COORDINATES.lat
        ] as [number, number],
        zoom: 11
      };
    }

    const avgLat = courts.reduce((sum, court) => sum + court.locationLat, 0) / courts.length;
    const avgLng = courts.reduce((sum, court) => sum + court.locationLng, 0) / courts.length;

    return {
      center: [avgLng, avgLat] as [number, number],
      zoom: courts.length === 1 ? 13 : 11
    };
  }, [courts, district]);

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
        const YMapFeature = ymaps3.YMapFeature;
        const map = new YMap(containerRef.current, {
          location: initialLocation,
          behaviors: ["drag", "pinchZoom", "dblClick", "scrollZoom"]
        });

        map.addChild(new YMapDefaultSchemeLayer({ theme: "light" }));
        map.addChild(new YMapDefaultFeaturesLayer());

        if (YMapFeature) {
          for (const [districtKey, area] of Object.entries(DISTRICT_MAP_AREAS)) {
            const isSelected = districtKey === district;

            map.addChild(
              new YMapFeature({
                geometry: {
                  type: "Polygon",
                  coordinates: [area.polygon]
                },
                style: {
                  fill: hexToRgba(area.color, isSelected ? 0.16 : 0.06),
                  stroke: [{ color: area.color, width: isSelected ? 2.5 : 1.25 }]
                }
              })
            );
          }

          if (district && radiusKm) {
            const area = DISTRICT_MAP_AREAS[district as DistrictOption];
            if (area) {
              map.addChild(
                new YMapFeature({
                  geometry: {
                    type: "Polygon",
                    coordinates: [buildCircle(area.center.lat, area.center.lng, radiusKm)]
                  },
                  style: {
                    fill: "rgba(20, 47, 38, 0.08)",
                    stroke: [{ color: "#142F26", width: 2 }]
                  }
                })
              );
            }
          }
        }

        for (const court of courts) {
          const primarySport = getPrimaryCourtSport(court.supportedSports) ?? "tennis";
          const sportEmoji = SPORT_EMOJIS[primarySport];
          const sportLabels = normalizeCourtSports(court.supportedSports)
            .map((sport) => SPORT_LABELS[sport as Sport])
            .join(" · ");
          const markerElement = document.createElement("a");
          markerElement.href = `/play/proposals/new?courtId=${court.id}`;
          markerElement.className = "group flex -translate-y-full flex-col items-center text-center no-underline";
          markerElement.innerHTML = `
            <span class="flex h-11 w-11 items-center justify-center rounded-full bg-[#C96D42] text-white shadow-lg ring-4 ring-white/90 transition group-hover:scale-105">
              <span style="font-size:18px;line-height:1">${sportEmoji}</span>
            </span>
            <span class="mt-2 max-w-[170px] rounded-full bg-white px-3 py-2 text-[11px] font-semibold text-[#142F26] shadow-md">
              ${escapeHtml(court.name)}
            </span>
          `;
          markerElement.title = `${court.name} — ${court.address}${sportLabels ? ` — ${sportLabels}` : ""}`;

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
  }, [apiKey, courts, district, initialLocation, radiusKm]);

  if (error) {
    return <Panel className="text-sm leading-6 text-ink/70">{error}</Panel>;
  }

  return <div ref={containerRef} className={`${compact ? "h-[220px]" : "h-[420px]"} w-full overflow-hidden rounded-[28px]`} />;
}

function buildCircle(centerLat: number, centerLng: number, radiusKm: number) {
  const steps = 48;
  const coordinates: [number, number][] = [];
  const latitudeDegreeKm = 111.32;
  const longitudeDegreeKm = 111.32 * Math.cos((centerLat * Math.PI) / 180);

  for (let index = 0; index <= steps; index += 1) {
    const angle = (index / steps) * Math.PI * 2;
    const lat = centerLat + (Math.sin(angle) * radiusKm) / latitudeDegreeKm;
    const lng = centerLng + (Math.cos(angle) * radiusKm) / Math.max(longitudeDegreeKm, 0.0001);
    coordinates.push([lng, lat]);
  }

  return coordinates;
}

function hexToRgba(hex: string, alpha: number) {
  const value = hex.replace("#", "");
  const red = Number.parseInt(value.slice(0, 2), 16);
  const green = Number.parseInt(value.slice(2, 4), 16);
  const blue = Number.parseInt(value.slice(4, 6), 16);

  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
