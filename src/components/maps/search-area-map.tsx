"use client";

import { getMapProvider } from "@/lib/maps/config";
import { cn } from "@/lib/utils";
import { useLocale } from "@/components/i18n/locale-provider";
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
  const { t } = useLocale();
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
      {t("profile.map.disabled")}
    </Panel>
  );
}
