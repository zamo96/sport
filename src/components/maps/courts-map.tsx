"use client";

import { getMapProvider } from "@/lib/maps/config";
import { Panel } from "@/components/ui/panel";
import { YandexCourtsMap } from "@/components/maps/yandex-courts-map";

type CourtMapPoint = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  locationLat: number;
  locationLng: number;
  supportedSports?: unknown;
};

export function CourtsMap({
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
  const provider = getMapProvider();

  if (provider === "yandex") {
    return <YandexCourtsMap courts={courts} district={district} radiusKm={radiusKm} compact={compact} />;
  }

  return (
    <Panel className="text-sm leading-6 text-ink/70">
      Карта отключена. Укажи `NEXT_PUBLIC_MAP_PROVIDER=yandex` и `NEXT_PUBLIC_YANDEX_MAPS_API_KEY`,
      чтобы включить Яндекс Карты.
    </Panel>
  );
}
