"use client";

import { getMapProvider } from "@/lib/maps/config";
import { Panel } from "@/components/ui/panel";
import { YandexSearchAreaMap } from "@/components/maps/yandex-search-area-map";

export function SearchAreaMap({
  centerLat,
  centerLng,
  radiusKm,
  city,
  isApproximate = false
}: {
  centerLat?: number | null;
  centerLng?: number | null;
  radiusKm: number;
  city: string;
  isApproximate?: boolean;
}) {
  const provider = getMapProvider();

  if (provider === "yandex") {
    return (
      <YandexSearchAreaMap
        centerLat={centerLat}
        centerLng={centerLng}
        radiusKm={radiusKm}
        city={city}
        isApproximate={isApproximate}
      />
    );
  }

  return (
    <Panel className="text-sm leading-6 text-ink/70">
      Карта района отключена. Укажи `NEXT_PUBLIC_MAP_PROVIDER=yandex` и `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`,
      чтобы видеть радиус поиска на карте.
    </Panel>
  );
}
