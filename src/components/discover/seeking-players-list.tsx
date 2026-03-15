"use client";

import { Flame, MapPin } from "lucide-react";

import { DAY_LABELS, GAME_SEARCH_TYPE_LABELS, HOT_SEARCH_WINDOW_LABELS, PLAY_FORMAT_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
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
    hotWindow: "today" | "tomorrow" | null;
    hasCourtBooked: boolean;
    sport: "tennis" | "padel" | "badminton" | "squash" | "pickleball";
    format: "singles" | "doubles" | "both";
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
  variant = "seeking"
}: {
  users: SeekingUser[];
  variant?: "seeking" | "hot";
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
        const myResponseStatus = latestSearch?.responses?.[0]?.status;
        const sports = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);

        return (
          <Panel key={user.id} className="space-y-3">
            <div className="flex items-start gap-3">
              <Avatar src={user.avatarUrl} alt={user.name ?? "Игрок"} size="lg" />
              <div className="min-w-0 flex-1">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="text-xl font-bold text-ink">
                      {user.name} {user.age ? `, ${user.age}` : ""}
                    </div>
                    <div className="mt-1 flex items-center gap-2 text-sm text-ink/60">
                      <MapPin className="h-4 w-4" />
                      {user.city ?? "Город"} · {user.distanceLabel}
                    </div>
                  </div>
                  <div className="rounded-full bg-mint px-3 py-2 text-xs font-semibold text-court">
                    Совпадение {user.score ?? 0}
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
                    {PLAY_FORMAT_LABELS[user.preferredPlayFormat]}
                  </span>
                  {days.slice(0, 3).map((day) => (
                    <span key={String(day)} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                      {DAY_LABELS[day as keyof typeof DAY_LABELS]}
                    </span>
                  ))}
                  {timeRanges.map((timeRange) => (
                    <span
                      key={String(timeRange)}
                      className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink"
                    >
                      {TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]}
                    </span>
                  ))}
                </div>
              </div>
            </div>

            <p className="text-sm leading-6 text-ink/68">
              {user.bio ?? "Готов(а) быстро договориться и выйти на корт."}
            </p>

            {latestSearch ? (
              <div className={`rounded-[24px] p-3 ${latestSearch.searchType === "hot" ? "bg-red-50" : "bg-mint/60"}`}>
                <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
                  <span className="inline-flex items-center gap-1.5">
                    {latestSearch.searchType === "hot" ? <Flame className="h-3.5 w-3.5 text-red-500" /> : null}
                    {latestSearch.searchType === "hot" ? "Горячий поиск" : "Активный поиск игры"}
                  </span>
                </div>
                <div className="mt-2 flex flex-wrap gap-2">
                  <span
                    className={`rounded-full px-3 py-2 text-xs font-semibold ${latestSearch.searchType === "hot" ? "bg-white text-red-700" : "bg-white text-ink"}`}
                  >
                    <span className="inline-flex items-center gap-1.5">
                      {latestSearch.searchType === "hot" ? <Flame className="h-3.5 w-3.5" /> : null}
                      {GAME_SEARCH_TYPE_LABELS[latestSearch.searchType]}
                    </span>
                  </span>
                  <SportBadge
                    sport={latestSearch.sport}
                    className="bg-white text-ink"
                  />
                  <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
                    Уровень {getSportLevel(user.sportLevels, latestSearch.sport, user.tennisLevel ?? 5)}
                  </span>
                  <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
                    {PLAY_FORMAT_LABELS[latestSearch.format]}
                  </span>
                  {latestSearch.hotWindow ? (
                    <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-red-700">
                      {HOT_SEARCH_WINDOW_LABELS[latestSearch.hotWindow]}
                    </span>
                  ) : null}
                  {latestSearch.hasCourtBooked ? (
                    <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-red-700">
                      Корт уже есть
                    </span>
                  ) : null}
                  {searchDays.map((day) => (
                    <span key={String(day)} className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
                      {DAY_LABELS[day as keyof typeof DAY_LABELS]}
                    </span>
                  ))}
                  {searchTimeRanges.map((timeRange) => (
                    <span key={String(timeRange)} className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
                      {TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]}
                    </span>
                  ))}
                  {latestSearch.preferredCourt?.name ? (
                    <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
                      {latestSearch.preferredCourt.name}
                    </span>
                  ) : null}
                </div>
                {latestSearch.comment ? (
                  <div className="mt-2 text-sm leading-6 text-ink/72">{latestSearch.comment}</div>
                ) : null}
              </div>
            ) : null}

            {latestSearch ? (
              <RespondToSearchButton gameSearchId={latestSearch.id} existingStatus={myResponseStatus} />
            ) : null}
          </Panel>
        );
      })}
    </div>
  );
}
