"use client";

import { CalendarDays, Clock3, Flame, MapPin, Target, Trophy, Users2 } from "lucide-react";
import type { Sport } from "@prisma/client";

import { DAY_LABELS, GAME_SEARCH_TYPE_LABELS, HOT_SEARCH_WINDOW_LABELS, PLAY_FORMAT_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { formatTimeUntilHotSearch } from "@/lib/game-search";
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
  gameSearches?: Array<{
    id: string;
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
      status: "pending" | "approved" | "rejected" | "withdrawn";
    }>;
    preferredCourt?: {
      name: string;
    } | null;
  }>;
};

export function SeekingPlayersList({
  users,
  variant = "seeking",
  authRequiredHref
}: {
  users: SeekingUser[];
  variant?: "seeking" | "hot";
  authRequiredHref?: string;
}) {
  if (users.length === 0) {
    return (
      <Panel className="text-center">
        <div className="text-xl font-bold text-ink">
          {variant === "hot" ? "Сейчас нет срочных поисков" : "Сейчас никто не ищет игру"}
        </div>
        <div className="mt-2 text-sm leading-6 text-ink/65">
          {variant === "hot"
            ? "Когда у кого-то срывается игрок на сегодня или завтра, горячий поиск появится здесь."
            : "Попроси игроков включить статус поиска игры или зайди позже."}
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
            ? `${new Date(latestSearch.hotStartsAt).toLocaleString("ru-RU", {
                day: "2-digit",
                month: "2-digit",
                hour: "2-digit",
                minute: "2-digit"
              })}${latestSearch.durationMinutes ? ` · ${latestSearch.durationMinutes} мин` : ""}`
            : null;
        const hotCountdownLabel =
          latestSearch?.searchType === "hot" ? formatTimeUntilHotSearch(latestSearch.hotStartsAt) : null;
        const myResponseStatus = latestSearch?.responses?.[0]?.status;
        const sports = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
        const scheduleLabel = latestSearch
          ? buildScheduleLabel({
              type: latestSearch.searchType,
              hotWindow: latestSearch.hotWindow,
              hotScheduleLabel,
              preferredDays: searchDays,
              preferredTimeRanges: searchTimeRanges
            })
          : buildAvailabilityLabel(days, timeRanges);
        const approvedResponses = latestSearch?.responses?.filter((response) => response.status === "approved").length ?? 0;
        const playersNeeded = Math.max(latestSearch?.playersNeeded ?? 1, 1);
        const rosterLabel =
          playersNeeded > 1 ? `Собрано ${approvedResponses} из ${playersNeeded}` : approvedResponses > 0 ? "Игрок уже подтверждён" : "Нужен 1 игрок";
        const detailsTitle =
          latestSearch?.searchType === "hot"
            ? latestSearch.hasCourtBooked
              ? "Нужен игрок на ближайшее время"
              : "Быстрая игра на ближайшее время"
            : "Ищет партнёра по расписанию";
        const detailText =
          latestSearch?.comment?.trim() ||
          user.bio?.trim() ||
          "Хочет быстро договориться и выйти на игру без долгой переписки.";
        const primarySport = latestSearch?.sport ?? sports[0]?.sport ?? null;
        const primaryLevel =
          primarySport && latestSearch
            ? latestSearch.selfLevelUnknown
              ? null
              : (latestSearch.selfLevel ?? getSportLevel(user.sportLevels, primarySport, user.tennisLevel ?? 5))
            : null;

        return (
          <Panel key={user.id} className="overflow-hidden p-2">
            <div className="relative overflow-hidden rounded-[28px] bg-gradient-to-b from-court via-court to-ink p-3 text-white shadow-[0_18px_40px_rgba(17,38,29,0.18)]">
              <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.18),transparent_42%)]" />

              <div className="relative flex items-start justify-between gap-3">
                <div className="flex min-w-0 items-start gap-3">
                  <Avatar src={user.avatarUrl} alt={user.name ?? "Игрок"} size="md" className="ring-4 ring-white/12" />
                  <div className="min-w-0">
                    <div className="text-[1.05rem] font-bold leading-5 text-white">
                      {user.name} {user.age ? `, ${user.age}` : ""}
                    </div>
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      <SearchPill
                        icon={MapPin}
                        label={`${user.city ?? "Город"} · ${user.distanceLabel}`}
                        className="max-w-full bg-white/12 text-white/82"
                      />
                      {latestSearch ? (
                        <>
                          <SearchPill
                            icon={latestSearch.searchType === "hot" ? Flame : CalendarDays}
                            label={latestSearch.searchType === "hot" ? "Быстрая игра" : "Регулярный поиск"}
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
                    {latestSearch?.searchType === "hot" ? "Старт" : "Совпадение"}
                  </div>
                  <div className="mt-0.5 text-[12px] font-bold leading-4 text-white">
                    {latestSearch?.searchType === "hot" ? hotCountdownLabel ?? "Скоро" : user.score ?? 0}
                  </div>
                </div>
              </div>

              <div className="relative mt-3 space-y-2.5">
                <div>
                  <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-white/62">Сейчас ищет</div>
                  <div className="mt-1 text-[1rem] font-bold leading-5 text-white">{detailsTitle}</div>
                  <div className="mt-1 text-[13px] leading-5 text-white/78 line-clamp-2">{detailText}</div>
                </div>

                <div className="grid grid-cols-2 gap-2">
                  <InfoCard icon={Clock3} label="Когда" value={scheduleLabel} />
                  <InfoCard
                    icon={Trophy}
                    label="Клуб"
                    value={
                      latestSearch?.preferredCourt?.name
                        ? latestSearch.preferredCourt.name
                        : latestSearch?.hasCourtBooked
                          ? "Площадка уже есть"
                          : "Клуб подберут позже"
                    }
                  />
                  <InfoCard icon={Users2} label="Состав" value={rosterLabel} />
                  <InfoCard
                    icon={Target}
                    label="Ищет"
                    value={`Уровень ${latestSearch?.desiredLevelMin ?? 1}–${latestSearch?.desiredLevelMax ?? 10}`}
                  />
                </div>

                <div className="flex flex-wrap gap-1.5">
                  <SearchPill label={PLAY_FORMAT_LABELS[latestSearch?.format ?? user.preferredPlayFormat]} />
                  {latestSearch && primarySport ? (
                    <SearchPill
                      label={primaryLevel === null ? "Свой уровень: не знаю" : `Свой уровень: ${primaryLevel}`}
                    />
                  ) : null}
                  {latestSearch?.hotWindow ? (
                    <SearchPill
                      icon={Flame}
                      label={HOT_SEARCH_WINDOW_LABELS[latestSearch.hotWindow]}
                      className="bg-red-500/90 text-white"
                    />
                  ) : null}
                  {latestSearch?.playersNeeded && latestSearch.playersNeeded > 1 ? (
                    <SearchPill label={`Нужно игроков: ${latestSearch.playersNeeded}`} />
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
                  existingStatus={myResponseStatus}
                  authRequiredHref={authRequiredHref}
                />
              </div>
            ) : null}
          </Panel>
        );
      })}
    </div>
  );
}

function buildAvailabilityLabel(days: unknown[], timeRanges: unknown[]) {
  const dayLabel = days
    .slice(0, 3)
    .map((day) => DAY_LABELS[day as keyof typeof DAY_LABELS])
    .join(", ");
  const timeLabel = timeRanges
    .slice(0, 2)
    .map((timeRange) => TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS])
    .join(", ");

  if (dayLabel && timeLabel) {
    return `${dayLabel} · ${timeLabel}`;
  }

  return dayLabel || timeLabel || "Время уточнит в чате";
}

function buildScheduleLabel({
  type,
  hotWindow,
  hotScheduleLabel,
  preferredDays,
  preferredTimeRanges
}: {
  type: "regular" | "hot";
  hotWindow: "today" | "tomorrow" | "day_after_tomorrow" | null;
  hotScheduleLabel: string | null;
  preferredDays: unknown[];
  preferredTimeRanges: unknown[];
}) {
  if (type === "hot") {
    const hotLabel = hotWindow ? HOT_SEARCH_WINDOW_LABELS[hotWindow] : "Скоро";
    return hotScheduleLabel ? `${hotLabel} · ${hotScheduleLabel}` : hotLabel;
  }

  return buildAvailabilityLabel(preferredDays, preferredTimeRanges);
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
