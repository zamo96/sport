"use client";

import { useEffect, useMemo, useRef, useState } from "react";

import { DEFAULT_CITY, DEFAULT_CITY_COORDINATES, DISTRICT_MAP_AREAS, getDistrictArea, getDistrictLabel } from "@/lib/constants";
import { getYandexMapsApiKey } from "@/lib/maps/config";
import { cn } from "@/lib/utils";
import { loadYandexMaps } from "@/lib/maps/yandex";
import { Panel } from "@/components/ui/panel";

export function YandexSearchAreaMap({
  centerLat,
  centerLng,
  radiusKm,
  city = DEFAULT_CITY,
  district,
  isApproximate = false,
  className
}: {
  centerLat?: number | null;
  centerLng?: number | null;
  radiusKm: number;
  city?: string;
  district?: string | null;
  isApproximate?: boolean;
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const apiKey = getYandexMapsApiKey();
  const center = useMemo(
    () =>
      [
        centerLng ?? getDistrictArea(district)?.center.lng ?? DEFAULT_CITY_COORDINATES.lng,
        centerLat ?? getDistrictArea(district)?.center.lat ?? DEFAULT_CITY_COORDINATES.lat
      ] as [number, number],
    [centerLat, centerLng, district]
  );
  const initialLocation = useMemo(
    () => ({
      center,
      zoom: getZoomByRadius(radiusKm)
    }),
    [center, radiusKm]
  );

  useEffect(() => {
    let mapInstance: { destroy: () => void } | null = null;
    let cancelled = false;

    async function initMap() {
      if (!containerRef.current) {
        return;
      }

      if (!apiKey) {
        setError("Добавь NEXT_PUBLIC_YANDEX_MAPS_API_KEY, чтобы включить карту района.");
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
                  fill: hexToRgba(area.color, isSelected ? 0.18 : 0.08),
                  stroke: [{ color: area.color, width: isSelected ? 3 : 1.5 }]
                }
              })
            );
          }

          map.addChild(
            new YMapFeature({
              geometry: {
                type: "Polygon",
                coordinates: [buildCircle(center[1], center[0], radiusKm)]
              },
              style: {
                fill: "rgba(39, 125, 93, 0.18)",
                stroke: [{ color: "#277D5D", width: 2 }]
              }
            })
          );
        }

        const markerElement = document.createElement("div");
        markerElement.className = "flex -translate-y-full flex-col items-center";
        markerElement.innerHTML = `
          <span class="flex h-12 w-12 items-center justify-center rounded-full bg-[#142F26] text-white shadow-lg ring-4 ring-white/90">
            <span style="font-size:18px;line-height:1">📍</span>
          </span>
          <span class="mt-2 rounded-full bg-white px-3 py-2 text-[11px] font-semibold text-[#142F26] shadow-md">
            ${escapeHtml(getDistrictLabel(district) ?? city)} · ${radiusKm} км
          </span>
        `;
        markerElement.title = isApproximate
          ? `Примерный район поиска в ${city}`
          : `Район поиска в ${city}`;

        map.addChild(
          new YMapMarker(
            {
              coordinates: [center[0], center[1]]
            },
            markerElement
          )
        );

        mapInstance = map;
        setError(null);
      } catch (mapError) {
        if (!cancelled) {
          setError(mapError instanceof Error ? mapError.message : "Не удалось загрузить карту района.");
        }
      }
    }

    initMap();

    return () => {
      cancelled = true;
      mapInstance?.destroy();
    };
  }, [apiKey, center, city, district, initialLocation, isApproximate, radiusKm]);

  if (error) {
    return <Panel className={cn("text-sm leading-6 text-ink/70", className)}>{error}</Panel>;
  }

  return <div ref={containerRef} className={cn("h-[240px] w-full overflow-hidden rounded-[28px]", className)} />;
}

function hexToRgba(hex: string, alpha: number) {
  const value = hex.replace("#", "");
  const red = Number.parseInt(value.slice(0, 2), 16);
  const green = Number.parseInt(value.slice(2, 4), 16);
  const blue = Number.parseInt(value.slice(4, 6), 16);

  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}

function getZoomByRadius(radiusKm: number) {
  if (radiusKm <= 5) return 12;
  if (radiusKm <= 10) return 11;
  if (radiusKm <= 20) return 10;
  if (radiusKm <= 40) return 9;
  return 8;
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

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
