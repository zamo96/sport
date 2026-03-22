"use client";

import { useEffect, useRef, useState } from "react";

import { DISTRICT_MAP_AREAS } from "@/lib/constants";
import { getYandexMapsApiKey } from "@/lib/maps/config";
import { loadYandexMaps } from "@/lib/maps/yandex";
import { Panel } from "@/components/ui/panel";

const demoClubs = [
  {
    name: "Tennis Club",
    district: "central",
    lat: 59.9369,
    lng: 30.3438,
    color: "#C96D42",
    emoji: "🎾"
  },
  {
    name: "Padel Club",
    district: "primorsky",
    lat: 60.0035,
    lng: 30.2388,
    color: "#548BFF",
    emoji: "🥎"
  },
  {
    name: "Football Arena",
    district: "petrogradsky",
    lat: 59.9715,
    lng: 30.2978,
    color: "#2F7A65",
    emoji: "⚽"
  }
] as const;

const demoPlayers = [
  {
    name: "Максим",
    initials: "МК",
    hint: "удобен Tennis Club",
    lat: 59.9294,
    lng: 30.3172
  },
  {
    name: "Дарья",
    initials: "ДК",
    hint: "удобен Padel Club",
    lat: 59.9876,
    lng: 30.2642
  }
] as const;

const visibleDistricts = ["central", "primorsky", "petrogradsky"] as const;
const districtOvalSizes = {
  central: { latRadius: 0.018, lngRadius: 0.05 },
  primorsky: { latRadius: 0.026, lngRadius: 0.072 },
  petrogradsky: { latRadius: 0.017, lngRadius: 0.044 }
} as const;

export function YandexAuthDemoMap() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const apiKey = getYandexMapsApiKey();

  useEffect(() => {
    let mapInstance: { destroy: () => void } | null = null;
    let cancelled = false;

    async function initMap() {
      if (!containerRef.current) {
        return;
      }

      if (!apiKey) {
        setError("Добавь `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`, чтобы включить demo-карту на первом экране.");
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
          location: {
            center: [30.3041, 59.9576],
            zoom: 10.1
          },
          behaviors: ["drag", "pinchZoom", "dblClick", "scrollZoom"]
        });

        map.addChild(new YMapDefaultSchemeLayer({ theme: "light" }));
        map.addChild(new YMapDefaultFeaturesLayer());

        if (YMapFeature) {
          for (const districtKey of visibleDistricts) {
            const area = DISTRICT_MAP_AREAS[districtKey];
            const size = districtOvalSizes[districtKey];

            map.addChild(
              new YMapFeature({
                geometry: {
                  type: "Polygon",
                  coordinates: [createOvalPolygon(area.center.lat, area.center.lng, size.latRadius, size.lngRadius)]
                },
                style: {
                  fill: hexToRgba(area.color, 0.08),
                  stroke: [{ color: hexToRgba(area.color, 0.28), width: 1 }]
                }
              })
            );
          }
        }

        for (const districtKey of visibleDistricts) {
          const area = DISTRICT_MAP_AREAS[districtKey];
          const labelElement = document.createElement("div");
          labelElement.className = "flex -translate-x-1/2 -translate-y-1/2";
          labelElement.innerHTML = `
            <span style="border-radius:999px;background:${hexToRgba(area.color, 0.12)};padding:5px 10px;font-size:10px;font-weight:700;color:#142F26;border:1px solid ${hexToRgba(area.color, 0.2)};backdrop-filter:blur(10px);white-space:nowrap">
              ${escapeHtml(area.label)}
            </span>
          `;

          map.addChild(
            new YMapMarker(
              {
                coordinates: [area.center.lng, area.center.lat]
              },
              labelElement
            )
          );
        }

        for (const club of demoClubs) {
          const markerElement = document.createElement("div");
          markerElement.className = "flex -translate-y-full flex-col items-center";
          markerElement.innerHTML = `
            <span style="display:flex;height:36px;width:36px;align-items:center;justify-content:center;border-radius:999px;background:${club.color};color:white;box-shadow:0 12px 28px rgba(17,38,29,0.18);border:3px solid rgba(255,255,255,0.92);font-size:15px;line-height:1">
              ${club.emoji}
            </span>
            <span style="margin-top:7px;border-radius:999px;background:rgba(255,255,255,0.9);padding:6px 11px;font-size:10px;font-weight:700;color:#142F26;box-shadow:0 10px 24px rgba(17,38,29,0.12);white-space:nowrap">
              ${escapeHtml(club.name)}
            </span>
          `;

          map.addChild(
            new YMapMarker(
              {
                coordinates: [club.lng, club.lat]
              },
              markerElement
            )
          );
        }

        for (const player of demoPlayers) {
          const markerElement = document.createElement("div");
          markerElement.className = "flex -translate-y-full flex-col items-center";
          markerElement.innerHTML = `
            <div style="display:flex;align-items:center;gap:6px;border-radius:15px;background:rgba(255,255,255,0.88);padding:6px 8px;box-shadow:0 10px 22px rgba(17,38,29,0.1);border:1px solid rgba(255,255,255,0.86)">
              <span style="display:flex;height:24px;width:24px;align-items:center;justify-content:center;border-radius:999px;background:#142F26;color:white;font-size:9px;font-weight:700;letter-spacing:0.05em">
                ${escapeHtml(player.initials)}
              </span>
              <span style="display:flex;flex-direction:column;min-width:0">
                <span style="font-size:9px;font-weight:700;color:#142F26;line-height:1.2">${escapeHtml(player.name)}</span>
                <span style="font-size:8px;color:rgba(20,47,38,0.62);line-height:1.3;white-space:nowrap">${escapeHtml(player.hint)}</span>
              </span>
            </div>
          `;

          map.addChild(
            new YMapMarker(
              {
                coordinates: [player.lng, player.lat]
              },
              markerElement
            )
          );
        }

        mapInstance = map;
        setError(null);
      } catch (mapError) {
        if (!cancelled) {
          setError(mapError instanceof Error ? mapError.message : "Не удалось загрузить demo-карту.");
        }
      }
    }

    initMap();

    return () => {
      cancelled = true;
      mapInstance?.destroy();
    };
  }, [apiKey]);

  if (error) {
    return <Panel className="text-sm leading-6 text-ink/70">{error}</Panel>;
  }

  return (
    <div className="relative">
      <div ref={containerRef} className="h-[304px] w-full overflow-hidden rounded-[28px]" />
    </div>
  );
}

function hexToRgba(hex: string, alpha: number) {
  const value = hex.replace("#", "");
  const red = Number.parseInt(value.slice(0, 2), 16);
  const green = Number.parseInt(value.slice(2, 4), 16);
  const blue = Number.parseInt(value.slice(4, 6), 16);

  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}

function createOvalPolygon(centerLat: number, centerLng: number, latRadius: number, lngRadius: number) {
  const points: [number, number][] = [];

  for (let index = 0; index <= 32; index += 1) {
    const angle = (Math.PI * 2 * index) / 32;
    const lat = centerLat + Math.sin(angle) * latRadius;
    const lng = centerLng + Math.cos(angle) * lngRadius;
    points.push([lng, lat]);
  }

  return points;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
