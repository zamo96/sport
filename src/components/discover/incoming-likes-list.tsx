"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { MapPin } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { getSportLevelEntries } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";
import { useLocale } from "@/components/i18n/locale-provider";
import {
  getDiscoverDayLabel,
  getDiscoverFormatLabel,
  getDiscoverSurfaceLabel,
  getDiscoverTimeLabel,
  translateDiscover,
  translateDiscoverReason
} from "@/lib/i18n/web/discover";

type IncomingLikeUser = {
  id: string;
  name: string | null;
  age: number | null;
  city: string | null;
  district?: string | null;
  districtLabel?: string | null;
  bio: string | null;
  avatarUrl: string | null;
  tennisLevel: number | null;
  preferredSports?: unknown;
  sportLevels?: unknown;
  preferredPlayFormat: "singles" | "doubles" | "both";
  preferredSurface: "hard" | "clay" | "grass" | "any";
  availableDays?: unknown;
  availableTimeRanges?: unknown;
  distanceLabel: string;
  score: number | null;
  explainabilityReasons?: string[] | null;
};

export function IncomingLikesList({ users }: { users: IncomingLikeUser[] }) {
  const [items, setItems] = useState(users);
  const { locale } = useLocale();

  if (items.length === 0) {
    return (
      <Panel className="text-center">
        <div className="text-xl font-bold text-ink">{translateDiscover(locale, "discover.likes.emptyTitle")}</div>
        <div className="mt-2 text-sm leading-6 text-ink/65">
          {translateDiscover(locale, "discover.likes.emptyText")}
        </div>
      </Panel>
    );
  }

  return (
    <div className="space-y-3">
      {items.map((user) => (
        <IncomingLikeCard
          key={user.id}
          user={user}
          onResolved={() => setItems((current) => current.filter((item) => item.id !== user.id))}
        />
      ))}
    </div>
  );
}

function IncomingLikeCard({
  user,
  onResolved
}: {
  user: IncomingLikeUser;
  onResolved: () => void;
}) {
  const router = useRouter();
  const { locale } = useLocale();
  const t = (key: Parameters<typeof translateDiscover>[1], values?: Parameters<typeof translateDiscover>[2]) =>
    translateDiscover(locale, key, values);
  const [busy, setBusy] = useState(false);
  const sports = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
  const day = Array.isArray(user.availableDays) ? user.availableDays[0] : null;
  const timeRange = Array.isArray(user.availableTimeRanges) ? user.availableTimeRanges[0] : null;
  const explainabilityReasons = Array.isArray(user.explainabilityReasons)
    ? user.explainabilityReasons.filter(
        (reason): reason is string => typeof reason === "string" && reason.trim().length > 0
      )
    : [];

  async function answer(action: "like" | "dislike") {
    setBusy(true);

    try {
      const data = await apiFetch<{ match: { id: string } | null }>("/swipes", {
        method: "POST",
        body: JSON.stringify({ toUserId: user.id, action })
      });

      onResolved();

      if (action === "like" && data.match) {
        router.push(`/inbox/${data.match.id}`);
        return;
      }

      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel className="space-y-4">
      <div className="flex items-start gap-3">
        <Avatar src={user.avatarUrl} alt={user.name ?? t("discover.common.player")} size="lg" />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">{t("discover.likes.cardTitle")}</div>
              <div className="mt-1 text-xl font-bold text-ink">
                {user.name} {user.age ? `, ${user.age}` : ""}
              </div>
              <div className="mt-1 flex items-center gap-2 text-sm text-ink/60">
                <MapPin className="h-4 w-4" />
                {user.city ?? t("discover.common.city")}
                {user.districtLabel ? ` · ${user.districtLabel}` : ""}
              </div>
            </div>
            <div className="rounded-full bg-mint px-3 py-2 text-xs font-semibold text-court">
              {t("discover.likes.matchScore", { score: user.score ?? 0 })}
            </div>
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            {sports.slice(0, 2).map(({ sport, level }) => (
              <SportLevelBadge
                key={sport}
                sport={sport}
                level={level}
                badgeClassName="bg-cream text-ink"
                levelClassName="bg-cream text-ink"
              />
            ))}
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {getDiscoverFormatLabel(locale, user.preferredPlayFormat)}
            </span>
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {getDiscoverSurfaceLabel(locale, user.preferredSurface)}
            </span>
            {day ? (
              <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                {getDiscoverDayLabel(locale, String(day))}
              </span>
            ) : null}
            {timeRange ? (
              <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                {getDiscoverTimeLabel(locale, String(timeRange))}
              </span>
            ) : null}
          </div>

          {explainabilityReasons.length > 0 ? (
            <div className="mt-3 rounded-[18px] bg-mint/35 px-4 py-3">
              <div className="text-[11px] font-semibold uppercase tracking-[0.22em] text-court/80">
                {t("discover.likes.reasonTitle")}
              </div>
              <ul className="mt-2 space-y-1 text-sm leading-6 text-ink/70">
                {explainabilityReasons.slice(0, 2).map((reason) => (
                  <li key={reason} className="flex items-start gap-2">
                    <span className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-court/60" />
                    <span>{translateDiscoverReason(locale, reason)}</span>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      </div>

      <p className="text-sm leading-6 text-ink/68">
        {user.bio ?? t("discover.likes.bioFallback")}
      </p>

      <div className="grid grid-cols-2 gap-3">
        <Button variant="ghost" fullWidth onClick={() => answer("dislike")} disabled={busy}>
          {t("discover.common.skip")}
        </Button>
        <Button variant="secondary" fullWidth onClick={() => answer("like")} disabled={busy}>
          {t("discover.likes.play")}
        </Button>
      </div>
    </Panel>
  );
}
