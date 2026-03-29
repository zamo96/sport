"use client";

import type { Sport } from "@prisma/client";
import { useEffect, useMemo, useRef, useState } from "react";

import {
  DEFAULT_CITY_COORDINATES,
  DISTRICT_MAP_AREAS,
  SPORT_EMOJIS,
  SPORT_LABELS,
  getDistrictArea
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
  compact = false,
  focus
}: {
  courts: CourtMapPoint[];
  district?: string | null;
  radiusKm?: number;
  compact?: boolean;
  focus?:
    | {
        type: "metro" | "club";
        label?: string | null;
        center: { lat: number; lng: number };
        radiusKm: number;
        district?: string | null;
      }
    | {
        type: "district";
        label?: string | null;
        district: string;
        center?: { lat: number; lng: number } | null;
        radiusKm?: number;
      }
    | null;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const apiKey = getYandexMapsApiKey();
  const initialLocation = useMemo(() => {
    if (focus?.type === "metro" || focus?.type === "club") {
      return {
        center: [focus.center.lng, focus.center.lat] as [number, number],
        zoom: getZoomByRadius(focus.radiusKm)
      };
    }

    if (focus?.type === "district") {
      const focusDistrictCenter = focus.center ?? getDistrictArea(focus.district)?.center ?? null;
      if (focusDistrictCenter) {
        return {
          center: [focusDistrictCenter.lng, focusDistrictCenter.lat] as [number, number],
          zoom: 11
        };
      }
    }

    const districtCenter = getDistrictArea(district)?.center ?? null;

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
  }, [courts, district, focus]);

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
        const YMapListener = ymaps3.YMapListener;
        const map = new YMap(containerRef.current, {
          location: initialLocation,
          behaviors: ["drag", "pinchZoom", "dblClick", "scrollZoom"]
        });
        const markerNodes: unknown[] = [];
        let markerSignature = "";

        map.addChild(new YMapDefaultSchemeLayer({ theme: "light" }));
        map.addChild(new YMapDefaultFeaturesLayer());

        if (YMapFeature) {
          const districtEntries =
            focus?.type === "district" && focus.district
              ? Object.entries(DISTRICT_MAP_AREAS).filter(([districtKey]) => districtKey === focus.district)
              : Object.entries(DISTRICT_MAP_AREAS);

          for (const [districtKey, area] of districtEntries) {
            const isSelected = districtKey === (focus?.type === "district" ? focus.district : district);

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
            const area = getDistrictArea(district);
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

          if (focus?.type === "metro" || focus?.type === "club") {
            map.addChild(
              new YMapFeature({
                geometry: {
                  type: "Polygon",
                  coordinates: [buildCircle(focus.center.lat, focus.center.lng, focus.radiusKm)]
                },
                style: {
                  fill: focus.type === "metro" ? "rgba(209, 74, 61, 0.12)" : "rgba(20, 47, 38, 0.1)",
                  stroke: [{ color: focus.type === "metro" ? "#D14A3D" : "#142F26", width: 2 }]
                }
              })
            );
          }
        }

        const renderMarkers = (zoom: number, center: [number, number]) => {
          const visibleCourts = getVisibleCourtsForZoom(courts, center, zoom, compact, focus);
          const nextSignature = visibleCourts.map((court) => court.id).join("|");

          if (nextSignature === markerSignature) {
            return;
          }

          markerSignature = nextSignature;
          for (const marker of markerNodes.splice(0, markerNodes.length)) {
            map.removeChild?.(marker);
          }

          for (const court of visibleCourts) {
            const primarySport = getPrimaryCourtSport(court.supportedSports) ?? "tennis";
            const sportEmoji = SPORT_EMOJIS[primarySport];
            const sportLabels = normalizeCourtSports(court.supportedSports)
              .map((sport) => SPORT_LABELS[sport as Sport])
              .join(" · ");
            const markerElement = document.createElement("a");
            markerElement.href = `/play/proposals/new?courtId=${court.id}`;
            markerElement.className = "group flex -translate-y-full flex-col items-center text-center no-underline";
            const showLabel = zoom >= 13.2 || visibleCourts.length <= 6;
            markerElement.innerHTML = `
              <span class="flex h-9 w-9 items-center justify-center rounded-full bg-[#C96D42] text-white shadow-lg ring-4 ring-white/90 transition group-hover:scale-105">
                <span style="display:flex;align-items:center;justify-content:center;font-size:15px;line-height:1;width:100%;height:100%;">${sportEmoji}</span>
              </span>
              ${
                showLabel
                  ? `<span class="mt-1.5 max-w-[132px] rounded-full bg-white/96 px-2.5 py-1.5 text-[10px] font-semibold leading-4 text-[#142F26] shadow-md">
                      ${escapeHtml(court.name)}
                    </span>`
                  : ""
              }
            `;
            markerElement.title = `${court.name} — ${court.address}${sportLabels ? ` — ${sportLabels}` : ""}`;

            const markerNode = new YMapMarker(
              {
                coordinates: [court.locationLng, court.locationLat]
              },
              markerElement
            );
            markerNodes.push(markerNode);
            map.addChild(markerNode);
          }
        };

        if (YMapListener) {
          map.addChild(
            new YMapListener({
              onUpdate: ({ location }) => {
                const center = Array.isArray(location?.center) ? location.center : initialLocation.center;
                const zoom = typeof location?.zoom === "number" ? location.zoom : initialLocation.zoom;
                renderMarkers(zoom, center);
              }
            })
          );
        }

        renderMarkers(initialLocation.zoom, initialLocation.center);

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
  }, [apiKey, compact, courts, district, focus, initialLocation, radiusKm]);

  if (error) {
    return <Panel className="text-sm leading-6 text-ink/70">{error}</Panel>;
  }

  return <div ref={containerRef} className={`${compact ? "h-[220px]" : "h-[420px]"} w-full overflow-hidden rounded-[28px]`} />;
}

function getVisibleCourtsForZoom(
  courts: CourtMapPoint[],
  center: [number, number],
  zoom: number,
  compact: boolean,
  focus?:
    | {
        type: "metro" | "club";
        label?: string | null;
        center: { lat: number; lng: number };
        radiusKm: number;
        district?: string | null;
      }
    | {
        type: "district";
        label?: string | null;
        district: string;
        center?: { lat: number; lng: number } | null;
        radiusKm?: number;
      }
    | null
) {
  const limit = getMarkerLimit(zoom, compact, courts.length);
  const baseCourts =
    focus?.type === "district" && focus.district
      ? courts.filter((court) => court.district === focus.district)
      : [...courts];

  if (focus?.type === "metro" || focus?.type === "club") {
    return baseCourts
      .sort((left, right) => getQuickDistance(left, center) - getQuickDistance(right, center))
      .slice(0, limit);
  }

  return spreadCourtsAcrossDistricts(baseCourts, center, limit);
}

function getMarkerLimit(zoom: number, compact: boolean, total: number) {
  if (total <= 10) {
    return total;
  }

  const scale = compact ? 0.7 : 1;

  if (zoom < 11) return Math.min(total, Math.round(10 * scale));
  if (zoom < 12) return Math.min(total, Math.round(16 * scale));
  if (zoom < 13) return Math.min(total, Math.round(28 * scale));
  if (zoom < 14) return Math.min(total, Math.round(48 * scale));
  if (zoom < 15) return Math.min(total, Math.round(80 * scale));
  return total;
}

function getQuickDistance(court: CourtMapPoint, center: [number, number]) {
  const lngDelta = court.locationLng - center[0];
  const latDelta = court.locationLat - center[1];
  return lngDelta * lngDelta + latDelta * latDelta;
}

function spreadCourtsAcrossDistricts(courts: CourtMapPoint[], center: [number, number], limit: number) {
  const grouped = new Map<string, CourtMapPoint[]>();

  for (const court of courts) {
    const key = court.district ?? "__none__";
    if (!grouped.has(key)) {
      grouped.set(key, []);
    }
    grouped.get(key)?.push(court);
  }

  const buckets = Array.from(grouped.values()).map((bucket) =>
    bucket.sort((left, right) => getQuickDistance(left, center) - getQuickDistance(right, center))
  );

  const result: CourtMapPoint[] = [];
  let index = 0;

  while (result.length < limit) {
    let addedInRound = false;

    for (const bucket of buckets) {
      const court = bucket[index];
      if (!court) {
        continue;
      }

      result.push(court);
      addedInRound = true;

      if (result.length >= limit) {
        break;
      }
    }

    if (!addedInRound) {
      break;
    }

    index += 1;
  }

  return result;
}

function getZoomByRadius(radiusKm: number) {
  if (radiusKm <= 1) return 14;
  if (radiusKm <= 3) return 13;
  if (radiusKm <= 5) return 12.3;
  if (radiusKm <= 10) return 11.2;
  return 10.4;
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
