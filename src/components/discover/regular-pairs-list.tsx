"use client";

import Link from "next/link";
import type { Sport } from "@prisma/client";

import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";
import { useLocale } from "@/components/i18n/locale-provider";
import { getAuthSportLabel } from "@/lib/i18n/web/auth";
import { getDiscoverDayLabel, getDiscoverFormatLabel, getDiscoverTimeLabel, translateDiscover } from "@/lib/i18n/web/discover";
import type { SupportedLocale } from "@/lib/locales";

type RegularPairCard = {
  id: string;
  sport: Sport;
  format: "singles" | "doubles" | "both";
  preferredDays: unknown;
  preferredTimeRanges: unknown;
  preferredCourt?: {
    name: string;
  } | null;
  partner: {
    name: string | null;
    avatarUrl: string | null;
  };
  nextOccurrence?: {
    id: string;
    scheduledAt: string;
    status: "pending" | "confirmed" | "declined" | "canceled" | "expired";
    gameRequest?: {
      id: string;
    } | null;
  } | null;
};

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function buildScheduleLabel(locale: SupportedLocale, preferredDays: unknown, preferredTimeRanges: unknown) {
  const days = normalizeStringArray(preferredDays)
    .slice(0, 3)
    .map((day) => getDiscoverDayLabel(locale, day));
  const timeRanges = normalizeStringArray(preferredTimeRanges)
    .slice(0, 2)
    .map((timeRange) => getDiscoverTimeLabel(locale, timeRange));

  return [days.join(", "), timeRanges.join(", ")].filter(Boolean).join(" · ");
}

function resolveOccurrenceLabel(locale: SupportedLocale, pair: RegularPairCard) {
  if (!pair.nextOccurrence) {
    return translateDiscover(locale, "discover.regular.autoSlot");
  }

  const time = new Date(pair.nextOccurrence.scheduledAt).toLocaleString(locale === "ru" ? "ru-RU" : "en-US", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });

  if (pair.nextOccurrence.gameRequest) {
    return translateDiscover(locale, "discover.regular.gameCreated", { time });
  }

  if (pair.nextOccurrence.status === "confirmed") {
    return translateDiscover(locale, "discover.regular.slotConfirmed", { time });
  }

  if (pair.nextOccurrence.status === "declined") {
    return translateDiscover(locale, "discover.regular.slotDeclined", { time });
  }

  return translateDiscover(locale, "discover.regular.slotNeedsReply", { time });
}

export function RegularPairsList({ pairs }: { pairs: RegularPairCard[] }) {
  const { locale } = useLocale();
  const t = (key: Parameters<typeof translateDiscover>[1]) => translateDiscover(locale, key);
  if (pairs.length === 0) {
    return null;
  }

  return (
    <div className="space-y-3">
      <div className="px-1">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">{t("discover.regular.title")}</div>
        <div className="mt-1 text-sm text-ink/62">
          {t("discover.regular.subtitle")}
        </div>
      </div>

      {pairs.map((pair) => (
        <Panel key={pair.id} className="space-y-3 bg-white/88">
          <div className="flex items-center gap-3">
            <Avatar src={pair.partner.avatarUrl} alt={pair.partner.name ?? t("discover.common.player")} />
            <div className="min-w-0">
              <div className="text-base font-bold text-ink">{pair.partner.name ?? t("discover.common.player")}</div>
              <div className="mt-1 flex flex-wrap items-center gap-2">
                <SportBadge sport={pair.sport} />
                <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                  {getDiscoverFormatLabel(locale, pair.format)}
                </span>
              </div>
            </div>
          </div>

          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/72">
            <div className="font-semibold text-ink">{resolveOccurrenceLabel(locale, pair)}</div>
            <div className="mt-1">
              {getAuthSportLabel(locale, pair.sport)} · {buildScheduleLabel(locale, pair.preferredDays, pair.preferredTimeRanges) || t("discover.regular.scheduleUnknown")}
              {pair.preferredCourt?.name ? ` · ${pair.preferredCourt.name}` : ""}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Link href={`/play/regular/${pair.id}`}>
              <Button fullWidth>{t("discover.regular.open")}</Button>
            </Link>
            <Link href={pair.nextOccurrence?.gameRequest ? `/play/games/${pair.nextOccurrence.gameRequest.id}` : `/play/regular/${pair.id}`}>
              <Button fullWidth variant="secondary">
                {pair.nextOccurrence?.gameRequest ? t("discover.regular.openGame") : t("discover.regular.checkSlot")}
              </Button>
            </Link>
          </div>
        </Panel>
      ))}
    </div>
  );
}
