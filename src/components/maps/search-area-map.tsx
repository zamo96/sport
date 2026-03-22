"use client";

import { getMapProvider } from "@/lib/maps/config";
import { cn } from "@/lib/utils";
import { Panel } from "@/components/ui/panel";
import { YandexSearchAreaMap } from "@/components/maps/yandex-search-area-map";

export function SearchAreaMap({
  centerLat,
  centerLng,
  radiusKm,
  city,
  district,
  isApproximate = false,
  className
}: {
  centerLat?: number | null;
  centerLng?: number | null;
  radiusKm: number;
  city: string;
  district?: string | null;
  isApproximate?: boolean;
  className?: string;
}) {
  const provider = getMapProvider();

  if (provider === "yandex") {
    return (
        <YandexSearchAreaMap
          centerLat={centerLat}
          centerLng={centerLng}
          radiusKm={radiusKm}
          city={city}
          district={district}
          isApproximate={isApproximate}
          className={className}
        />
      );
  }

  return (
    <Panel className={cn("text-sm leading-6 text-ink/70", className)}>
      Карта района отключена. Укажи `NEXT_PUBLIC_MAP_PROVIDER=yandex` и `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`,
      чтобы видеть радиус поиска на карте.
    </Panel>
  );
}
