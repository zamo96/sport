"use client";

import { useEffect } from "react";
import { CalendarDays, Clock3, Flame, MapPin, Target, Trophy, Users2 } from "lucide-react";
import type { Sport } from "@prisma/client";

import { useLocale } from "@/components/i18n/locale-provider";
import { resolveSearchLifecycleStatus } from "@/lib/game-search";
import {
  formatDiscoverHotCountdown,
  getDiscoverDayLabel,
  getDiscoverFormatLabel,
  getDiscoverHotWindowLabel,
  getDiscoverTimeLabel,
  translateDiscover,
  translateDiscoverLifecycleStatus,
  translateDiscoverReason
} from "@/lib/i18n/web/discover";
import { getSportLevel, getSportLevelEntries } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";
import { RespondToSearchButton } from "@/components/discover/respond-to-search-button";

type SeekingUser = {
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
  distanceLabel: string;
  score: number | null;
  availableDays?: unknown;
  availableTimeRanges?: unknown;
  explainabilityReasons?: string[] | null;
  gameSearches?: Array<{
    id: string;
    status: "active" | "in_review" | "matched" | "closed";
    preferredDays: unknown;
    preferredTimeRanges: unknown;
    searchType: "regular" | "hot";
    hotWindow: "today" | "tomorrow" | "day_after_tomorrow" | null;
    hotStartsAt?: string | null;
    durationMinutes?: number | null;
    hasCourtBooked: boolean;
    sport: Sport;
    selfLevel?: number | null;
    selfLevelUnknown?: boolean;
    desiredLevelMin?: number | null;
    desiredLevelMax?: number | null;
    format: "singles" | "doubles" | "both";
    playersNeeded?: number | null;
    comment: string | null;
    responses?: Array<{
      id: string;
      responderUserId?: string;
      status: "pending" | "approved" | "rejected" | "withdrawn";
    }>;
    preferredCourt?: {
      name: string;
    } | null;
  }>;
};

export function SeekingPlayersList({
  users,
  currentUserId,
  variant = "seeking",
  highlightSearchId,
  authRequiredHref
}: {
  users: SeekingUser[];
  currentUserId?: string;
  variant?: "seeking" | "hot";
  highlightSearchId?: string;
  authRequiredHref?: string;
}) {
  const { locale, t } = useLocale();
  useEffect(() => {
    if (!highlightSearchId) {
      return;
    }

    const target = document.getElementById(`game-search-${highlightSearchId}`);
    if (!target) {
      return;
    }

    window.setTimeout(() => {
      target.scrollIntoView({ behavior: "smooth", block: "center" });
    }, 120);
  }, [highlightSearchId]);

  if (users.length === 0) {
    return (
      <Panel className="text-center">
        <div className="text-xl font-bold text-ink">
          {variant === "hot" ? t("discover.seeking.hotEmptyTitle") : t("discover.seeking.emptyTitle")}
        </div>
        <div className="mt-2 text-sm leading-6 text-ink/65">
          {variant === "hot"
            ? t("discover.seeking.hotEmptyText")
            : t("discover.seeking.emptyText")}
        </div>
      </Panel>
    );
  }

  return (
    <div className="space-y-3">
      {users.map((user) => {
        const days = Array.isArray(user.availableDays) ? user.availableDays : [];
        const timeRanges = Array.isArray(user.availableTimeRanges) ? user.availableTimeRanges : [];
        const latestSearch = Array.isArray(user.gameSearches) ? user.gameSearches[0] : null;
        const searchDays = latestSearch && Array.isArray(latestSearch.preferredDays) ? latestSearch.preferredDays : [];
        const searchTimeRanges =
          latestSearch && Array.isArray(latestSearch.preferredTimeRanges) ? latestSearch.preferredTimeRanges : [];
        const hotScheduleLabel =
          latestSearch?.searchType === "hot" && latestSearch.hotStartsAt
            ? `${new Date(latestSearch.hotStartsAt).toLocaleString(locale, {
                day: "2-digit",
                month: "2-digit",
                hour: "2-digit",
                minute: "2-digit"
              })}${latestSearch.durationMinutes ? ` · ${t("discover.seeking.duration", { minutes: latestSearch.durationMinutes })}` : ""}`
            : null;
        const hotCountdownLabel =
          latestSearch?.searchType === "hot" ? formatDiscoverHotCountdown(locale, latestSearch.hotStartsAt) : null;
        const myResponse = currentUserId
          ? latestSearch?.responses?.find((response) => response.responderUserId === currentUserId)
          : undefined;
        const myResponseStatus = myResponse?.status;
        const sports = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
        const scheduleLabel = latestSearch
          ? buildScheduleLabel({
              type: latestSearch.searchType,
              hotWindow: latestSearch.hotWindow,
              hotScheduleLabel,
              preferredDays: searchDays,
              preferredTimeRanges: searchTimeRanges,
              locale
            })
          : buildAvailabilityLabel(days, timeRanges, locale);
        const approvedResponses = latestSearch?.responses?.filter((response) => response.status === "approved").length ?? 0;
        const playersNeeded = Math.max(latestSearch?.playersNeeded ?? 1, 1);
        const lifecycleStatus = latestSearch
          ? resolveSearchLifecycleStatus({
              status: latestSearch.status,
              approvedCount: approvedResponses,
              playersNeeded,
              startAt: latestSearch.hotStartsAt,
              durationMinutes: latestSearch.durationMinutes
            })
          : t("discover.seeking.search");
        const localizedLifecycleStatus = translateDiscoverLifecycleStatus(locale, lifecycleStatus);
        const rosterLabel =
          playersNeeded > 1
            ? t("discover.seeking.rosterMany", { approved: approvedResponses, needed: playersNeeded })
            : approvedResponses > 0
              ? t("discover.seeking.rosterConfirmed")
              : t("discover.seeking.rosterOne");
        const detailsTitle =
          latestSearch?.searchType === "hot"
            ? latestSearch.hasCourtBooked
              ? t("discover.seeking.hotBookedTitle")
              : t("discover.seeking.hotTitle")
            : t("discover.seeking.regularTitle");
        const detailText =
          latestSearch?.comment?.trim() ||
          user.bio?.trim() ||
          t("discover.seeking.bioFallback");
        const primarySport = latestSearch?.sport ?? sports[0]?.sport ?? null;
        const primaryLevel =
          primarySport && latestSearch
            ? latestSearch.selfLevelUnknown
              ? null
              : (latestSearch.selfLevel ?? getSportLevel(user.sportLevels, primarySport, user.tennisLevel ?? 5))
            : null;
        const explainabilityReasons = Array.isArray(user.explainabilityReasons)
          ? user.explainabilityReasons.filter(
              (reason): reason is string => typeof reason === "string" && reason.trim().length > 0
            )
          : [];

        return (
          <div
            key={user.id}
            id={latestSearch ? `game-search-${latestSearch.id}` : undefined}
          >
            <Panel className={`overflow-hidden p-2 ${highlightSearchId && latestSearch?.id === highlightSearchId ? "ring-2 ring-red-400 shadow-[0_0_0_6px_rgba(239,68,68,0.08)]" : ""}`}>
            <div className="relative overflow-hidden rounded-[28px] bg-gradient-to-b from-court via-court to-ink p-3 text-white shadow-[0_18px_40px_rgba(17,38,29,0.18)]">
              <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.18),transparent_42%)]" />

              <div className="relative flex items-start justify-between gap-3">
                <div className="flex min-w-0 items-start gap-3">
                  <Avatar src={user.avatarUrl} alt={user.name ?? t("discover.common.player")} size="md" className="shrink-0 ring-4 ring-white/12" />
                  <div className="min-w-0">
                    <div className="text-[1.05rem] font-bold leading-5 text-white">
                      {user.name} {user.age ? `, ${user.age}` : ""}
                    </div>
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      <SearchPill
                        icon={MapPin}
                        label={`${user.city ?? t("discover.common.city")}${user.districtLabel ? ` · ${user.districtLabel}` : ""}`}
                        className="max-w-full bg-white/12 text-white/82"
                      />
                      {latestSearch ? (
                        <>
                          <SearchPill
                            icon={latestSearch.searchType === "hot" ? Flame : CalendarDays}
                            label={localizedLifecycleStatus}
                            className={latestSearch.searchType === "hot" ? "bg-red-500/90 text-white" : "bg-white/14 text-white"}
                          />
                          {primarySport ? <SportBadge sport={primarySport} className="bg-white/14 text-white" /> : null}
                        </>
                      ) : (
                        sports.slice(0, 1).map(({ sport }) => <SportBadge key={sport} sport={sport} className="bg-white/14 text-white" />)
                      )}
                    </div>
                  </div>
                </div>

                <div className="shrink-0 rounded-[16px] bg-white/14 px-2 py-1.5 text-right backdrop-blur">
                  <div className="text-[10px] uppercase tracking-[0.18em] text-white/60">
                    {latestSearch?.searchType === "hot" ? t("discover.seeking.start") : t("discover.seeking.match")}
                  </div>
                  <div className="mt-0.5 text-[12px] font-bold leading-4 text-white">
                    {latestSearch?.searchType === "hot" ? hotCountdownLabel ?? t("discover.common.soon") : user.score ?? 0}
                  </div>
                </div>
              </div>

              <div className="relative mt-3 space-y-2.5">
                <div>
                  <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-white/62">{t("discover.seeking.lookingFor")}</div>
                  <div className="mt-1 text-[1rem] font-bold leading-5 text-white">{detailsTitle}</div>
                  <div className="mt-1 text-[13px] leading-5 text-white/78 line-clamp-2">{detailText}</div>
                </div>

                {explainabilityReasons.length > 0 ? (
                  <div>
                    <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-white/62">{t("discover.seeking.why")}</div>
                    <div className="mt-1 flex flex-wrap gap-1.5">
                      {explainabilityReasons.slice(0, 2).map((reason) => (
                        <SearchPill key={reason} label={translateDiscoverReason(locale, reason)} className="max-w-full bg-white/12 text-white/82" />
                      ))}
                    </div>
                  </div>
                ) : null}

                <div className="grid grid-cols-2 gap-2">
                  <InfoCard icon={Clock3} label={t("discover.seeking.when")} value={scheduleLabel} />
                  <InfoCard
                    icon={Trophy}
                    label={t("discover.seeking.place")}
                    value={
                      latestSearch?.preferredCourt?.name
                        ? latestSearch.preferredCourt.name
                        : latestSearch?.hasCourtBooked
                          ? t("discover.seeking.placeBooked")
                          : t("discover.seeking.placeLater")
                    }
                  />
                  <InfoCard icon={Users2} label={t("discover.seeking.roster")} value={rosterLabel} />
                  <InfoCard
                    icon={Target}
                    label={t("discover.seeking.target")}
                    value={t("discover.common.level", { level: `${latestSearch?.desiredLevelMin ?? 1}–${latestSearch?.desiredLevelMax ?? 10}` })}
                  />
                </div>

                <div className="flex flex-wrap gap-1.5">
                  <SearchPill
                    label={getDiscoverFormatLabel(locale, latestSearch?.format ?? user.preferredPlayFormat)}
                  />
                  {latestSearch && primarySport ? (
                    <SearchPill
                      label={primaryLevel === null ? t("discover.seeking.ownLevelUnknown") : t("discover.seeking.ownLevel", { level: primaryLevel })}
                    />
                  ) : null}
                  {latestSearch?.hotWindow ? (
                    <SearchPill
                      icon={Flame}
                      label={getDiscoverHotWindowLabel(locale, latestSearch.hotWindow)}
                      className="bg-red-500/90 text-white"
                    />
                  ) : null}
                  {latestSearch?.playersNeeded && latestSearch.playersNeeded > 1 ? (
                    <SearchPill label={t("discover.seeking.playersNeeded", { count: latestSearch.playersNeeded })} />
                  ) : null}
                  {hotScheduleLabel && latestSearch?.searchType === "hot" ? <SearchPill label={hotScheduleLabel} /> : null}
                  {hotCountdownLabel && latestSearch?.searchType === "hot" ? (
                    <SearchPill icon={Flame} label={hotCountdownLabel} className="bg-red-500/90 text-white" />
                  ) : null}
                </div>

                {sports.length > 0 && !latestSearch ? (
                  <div className="flex flex-wrap gap-1.5">
                    {sports.slice(0, 2).map(({ sport, level }) => (
                      <SportLevelBadge
                        key={sport}
                        sport={sport}
                        level={level}
                        badgeClassName="bg-white/12 text-white"
                        levelClassName="bg-white/12 text-white"
                        iconClassName="h-3.5 w-3.5 text-white"
                      />
                    ))}
                  </div>
                ) : null}
              </div>
            </div>

            {latestSearch ? (
              <div className="mt-2.5">
                <RespondToSearchButton
                  gameSearchId={latestSearch.id}
                  responseId={myResponse?.id}
                  existingStatus={myResponseStatus}
                  searchMatched={latestSearch.status === "matched"}
                  authRequiredHref={authRequiredHref}
                />
              </div>
            ) : null}
            </Panel>
          </div>
        );
      })}
    </div>
  );
}

function buildAvailabilityLabel(days: unknown[], timeRanges: unknown[], locale: "en" | "ru") {
  const dayLabel = days
    .slice(0, 3)
    .map((day) => getDiscoverDayLabel(locale, String(day)))
    .join(", ");
  const timeLabel = timeRanges
    .slice(0, 2)
    .map((timeRange) => getDiscoverTimeLabel(locale, String(timeRange)))
    .join(", ");

  if (dayLabel && timeLabel) {
    return `${dayLabel} · ${timeLabel}`;
  }

  return dayLabel || timeLabel || translateDiscover(locale, "discover.seeking.timeInChat");
}

function buildScheduleLabel({
  type,
  hotWindow,
  hotScheduleLabel,
  preferredDays,
  preferredTimeRanges,
  locale
}: {
  type: "regular" | "hot";
  hotWindow: "today" | "tomorrow" | "day_after_tomorrow" | null;
  hotScheduleLabel: string | null;
  preferredDays: unknown[];
  preferredTimeRanges: unknown[];
  locale: "en" | "ru";
}) {
  if (type === "hot") {
    const hotLabel = hotWindow
      ? getDiscoverHotWindowLabel(locale, hotWindow)
      : translateDiscover(locale, "discover.common.soon");
    return hotScheduleLabel ? `${hotLabel} · ${hotScheduleLabel}` : hotLabel;
  }

  return buildAvailabilityLabel(preferredDays, preferredTimeRanges, locale);
}

function InfoCard({
  icon: Icon,
  label,
  value
}: {
  icon: typeof Clock3;
  label: string;
  value: string;
}) {
  return (
    <div className="rounded-[18px] bg-white/12 px-2.5 py-2.5 backdrop-blur">
      <div className="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-white/60">
        <Icon className="h-3.5 w-3.5" />
        {label}
      </div>
      <div className="mt-1.5 text-[13px] font-semibold leading-4 text-white">{value}</div>
    </div>
  );
}

function SearchPill({
  icon: Icon,
  label,
  className
}: {
  icon?: typeof Clock3;
  label: string;
  className?: string;
}) {
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1.5 text-[11px] font-semibold ${className ?? "bg-white/12 text-white"}`}>
      {Icon ? <Icon className="h-3 w-3" /> : null}
      <span className="truncate">{label}</span>
    </span>
  );
}
