"use client";

import { useLocale } from "@/components/i18n/locale-provider";
import { formatDiscoverDistance, translateDiscover } from "@/lib/i18n/web/discover";

export type NearbyContext = { originCity: string; radiusKm: number; distanceKm: number };

export function NearbyNotice({ nearby, clubs = false }: { nearby: NearbyContext; clubs?: boolean }) {
  const { locale } = useLocale();
  return (
    <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-court">
      <div className="font-semibold">{translateDiscover(locale, "discover.nearby.title", { city: nearby.originCity })}</div>
      <div className="mt-1 leading-5">{translateDiscover(locale, clubs ? "discover.nearby.clubs" : "discover.nearby.players", { radius: nearby.radiusKm })}</div>
    </div>
  );
}

export function NearbyDistance({ nearby }: { nearby: NearbyContext }) {
  const { locale } = useLocale();
  return <>{translateDiscover(locale, "discover.nearby.distance", {
    distance: formatDiscoverDistance(locale, nearby.distanceKm), city: nearby.originCity
  })}</>;
}
