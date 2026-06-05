"use client";

import { getMapProvider } from "@/lib/maps/config";
import { cn } from "@/lib/utils";
import { Panel } from "@/components/ui/panel";
import { YandexSearchAreaMap } from "@/components/maps/yandex-search-area-map";

export function SearchAreaMap({
  centerLat,
  centerLng,
  city,
  districts = [],
  isApproximate = false,
  className
}: {
  centerLat?: number | null;
  centerLng?: number | null;
  city: string;
  districts?: string[];
  isApproximate?: boolean;
  className?: string;
}) {
  const provider = getMapProvider();

  if (provider === "yandex") {
    return (
        <YandexSearchAreaMap
          centerLat={centerLat}
          centerLng={centerLng}
          city={city}
          districts={districts}
          isApproximate={isApproximate}
          className={className}
        />
      );
  }

  return (
    <Panel className={cn("text-sm leading-6 text-ink/70", className)}>
      Карта районов отключена. Укажи `NEXT_PUBLIC_MAP_PROVIDER=yandex` и `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`,
      чтобы видеть удобные районы на карте.
    </Panel>
  );
}
