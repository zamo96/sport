"use client";

import Link from "next/link";
import { CalendarDays, Flame, MapPin, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import type { Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import {
  DAY_LABELS,
  GAME_SEARCH_TYPE_LABELS,
  HOT_SEARCH_WINDOW_LABELS,
  SPORT_SEARCH_LABELS,
  TIME_RANGE_LABELS,
  getDistrictLabel
} from "@/lib/constants";
import { formatTimeUntilHotSearch, resolveSearchLifecycleStatus, resolveSearchNextStep } from "@/lib/game-search";
import { getSportLevel, getSportLevelEntries } from "@/lib/sport-levels";
import { cn } from "@/lib/utils";
import { translateGameSearchResponseStatus } from "@/lib/status-map";
import { getSportPlayFormatLabelRu } from "@/components/sport-semantics";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";
import { SearchInviteButton } from "@/components/game-search/search-invite-button";

type SearchResponse = {
  id: string;
  status: "pending" | "approved" | "rejected" | "withdrawn";
  responderUser: {
    id: string;
    name: string | null;
    avatarUrl: string | null;
    age?: number | null;
    bio?: string | null;
    tennisLevel: number | null;
    preferredSports?: unknown;
    sportLevels?: unknown;
    city: string | null;
    district?: string | null;
    preferredDistricts?: unknown;
    availableDays?: unknown;
    availableTimeRanges?: unknown;
  };
};

type SearchItem = {
  id: string;
  status: "active" | "in_review" | "matched" | "closed";
  searchType: "regular" | "hot";
  hotWindow: "today" | "tomorrow" | "day_after_tomorrow" | null;
  hotStartsAt?: string | null;
  durationMinutes?: number | null;
  scheduledAt?: string | null;
  scheduledDurationMinutes?: number | null;
  hasCourtBooked: boolean;
  sport: Sport;
  selfLevel?: number | null;
  selfLevelUnknown?: boolean;
  desiredLevelMin?: number | null;
  desiredLevelMax?: number | null;
  playersNeeded?: number | null;
  preferredDays: unknown;
  preferredTimeRanges: unknown;
  format: "singles" | "doubles" | "both";
  comment: string | null;
  isActive: boolean;
  preferredCourt: {
    name: string;
  } | null;
  regularPair: {
    id: string;
    matchId: string;
    partnerUser: {
      id: string;
      name: string | null;
      avatarUrl: string | null;
    };
    preferredCourt: {
      name: string;
    } | null;
  } | null;
  responses: SearchResponse[];
};

export function GameSearchesList({ searches }: { searches: SearchItem[] }) {
  const [items, setItems] = useState(searches);

  useEffect(() => {
    setItems(searches);
  }, [searches]);

  useEffect(() => {
    let active = true;

    async function loadSearches() {
      try {
        const data = await apiFetch<{ gameSearches: SearchItem[] }>("/game-searches/my");
        if (active) {
          setItems(data.gameSearches);
        }
      } catch {
        return;
      }
    }

    const interval = window.setInterval(loadSearches, 10000);

    return () => {
      active = false;
      window.clearInterval(interval);
    };
  }, []);

  return (
    <div className="space-y-4">
      {items.length === 0 ? (
        <Panel className="text-center">
          <div className="text-xl font-bold text-ink">У тебя пока нет поисков игры</div>
          <div className="mt-2 text-sm leading-6 text-ink/65">
            Создай поиск и дождись откликов от игроков.
          </div>
          <Link href="/play/searches/new" className="mt-4 inline-block rounded-2xl bg-ink px-4 py-3 text-sm font-semibold text-white">
            Создать поиск
          </Link>
        </Panel>
      ) : null}

      {items.map((search) => (
        <GameSearchCard key={search.id} search={search} />
      ))}
    </div>
  );
}

function GameSearchCard({ search }: { search: SearchItem }) {
  const [previewUser, setPreviewUser] = useState<SearchResponse["responderUser"] | null>(null);
  const days = Array.isArray(search.preferredDays) ? search.preferredDays : [];
  const timeRanges = Array.isArray(search.preferredTimeRanges) ? search.preferredTimeRanges : [];
  const pendingResponses = search.responses.filter((response) => response.status === "pending");
  const approvedResponses = search.responses.filter((response) => response.status === "approved");
  const playersNeeded = Math.max(search.playersNeeded ?? 1, 1);
  const isSearchOpen = search.isActive && search.status !== "closed";
  const lifecycleStatus = resolveSearchLifecycleStatus({
    status: search.status,
    approvedCount: approvedResponses.length,
    playersNeeded,
    startAt: search.scheduledAt ?? search.hotStartsAt,
    durationMinutes: search.scheduledDurationMinutes ?? search.durationMinutes
  });
  const hotScheduleLabel =
    search.searchType === "hot" && search.hotStartsAt
      ? `${new Date(search.hotStartsAt).toLocaleString("ru-RU", {
          day: "2-digit",
          month: "2-digit",
          hour: "2-digit",
          minute: "2-digit"
        })}${search.durationMinutes ? ` · ${search.durationMinutes} мин` : ""}`
      : null;
  const hotCountdownLabel = search.searchType === "hot" ? formatTimeUntilHotSearch(search.hotStartsAt) : null;
  const nextStep = resolveSearchNextStep({
    searchType: search.searchType,
    status: search.status,
    approvedCount: approvedResponses.length,
    playersNeeded,
    scheduledAt: search.scheduledAt,
    regularPairMatchId: search.regularPair?.matchId ?? null
  });

  return (
    <Panel
      className={cn(
        "space-y-4 transition-all duration-500",
        isSearchOpen
          ? "search-card-active border-emerald-200/80 bg-emerald-50/72"
          : "search-card-closed border-slate-200/80 bg-slate-100/72"
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Мой поиск игры</div>
          <div className="mt-1 flex flex-wrap items-center gap-2">
            <div className="text-xl font-bold text-ink">{lifecycleStatus}</div>
            <span
              className={cn(
                "inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-[11px] font-semibold uppercase tracking-[0.18em]",
                isSearchOpen ? "bg-emerald-600 text-white" : "bg-slate-500 text-white"
              )}
            >
              <span
                className={cn(
                  "h-2 w-2 rounded-full",
                  isSearchOpen ? "bg-emerald-100 shadow-[0_0_0_4px_rgba(16,185,129,0.18)]" : "bg-slate-200"
                )}
              />
              {isSearchOpen ? "Открыт" : "Закрыт"}
            </span>
          </div>
          <div className="mt-1 text-sm text-ink/60">
            Собрано {approvedResponses.length} из {playersNeeded} · Ожидают ответа: {pendingResponses.length}
          </div>
        </div>
        <SearchStatusActions
          searchId={search.id}
          isActive={search.isActive}
          status={search.status}
          lifecycleStatus={lifecycleStatus}
          regularPairId={search.regularPair?.id ?? null}
          regularPairMatchId={search.regularPair?.matchId ?? null}
          hasResponses={search.responses.length > 0}
        />
      </div>

      <div className="flex flex-wrap gap-2">
        <span
          className={`rounded-full px-3 py-2 text-xs font-semibold ${search.searchType === "hot" ? "bg-red-50 text-red-700" : "bg-cream text-ink"}`}
        >
          <span className="inline-flex items-center gap-1.5">
            {search.searchType === "hot" ? <Flame className="h-3.5 w-3.5" /> : null}
            {GAME_SEARCH_TYPE_LABELS[search.searchType]}
          </span>
        </span>
        <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
          {getSportPlayFormatLabelRu(search.sport, search.format, { playersNeeded })}
        </span>
        <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
          Нужно игроков: {playersNeeded}
        </span>
        <SportBadge sport={search.sport} className="bg-cream text-ink" />
        <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
          {search.selfLevelUnknown ? "Свой уровень: не знаю" : `Свой уровень: ${search.selfLevel ?? "из профиля"}`}
        </span>
        <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
          Ищу уровень {search.desiredLevelMin ?? 1}–{search.desiredLevelMax ?? 10}
        </span>
        {search.hotWindow ? (
          <span className="rounded-full bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
            {HOT_SEARCH_WINDOW_LABELS[search.hotWindow]}
          </span>
        ) : null}
        {hotScheduleLabel ? (
          <span className="rounded-full bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">{hotScheduleLabel}</span>
        ) : null}
        {hotCountdownLabel ? (
          <span className="rounded-full bg-red-600 px-3 py-2 text-xs font-semibold text-white">{hotCountdownLabel}</span>
        ) : null}
        {search.hasCourtBooked ? (
          <span className="rounded-full bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
            {SPORT_SEARCH_LABELS[search.sport].bookedTitle}
          </span>
        ) : null}
        {days.map((day) => (
          <span key={String(day)} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
            {DAY_LABELS[day as keyof typeof DAY_LABELS]}
          </span>
        ))}
        {timeRanges.map((timeRange) => (
          <span key={String(timeRange)} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
            {TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]}
          </span>
        ))}
        {search.preferredCourt?.name ? (
          <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
            {search.preferredCourt.name}
          </span>
        ) : null}
      </div>

      {search.comment ? <div className="text-sm leading-6 text-ink/72">{search.comment}</div> : null}

      <div className="rounded-2xl bg-white/70 px-4 py-3 text-sm text-ink/72">{nextStep.description}</div>

      {approvedResponses.length > 0 ? (
        <ApprovedPlayersCard
          responses={approvedResponses}
          searchSport={search.sport}
          playersNeeded={playersNeeded}
          regularPair={search.regularPair}
        />
      ) : null}

      <div className="space-y-3">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Отклики</div>
        {search.responses.length === 0 ? (
          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/65">
            Пока никто не откликнулся.
          </div>
        ) : null}
        {search.responses.map((response) => (
          <SearchResponseCard
            key={response.id}
            response={response}
            canApprove={search.status !== "matched" && approvedResponses.length < playersNeeded}
            searchSport={search.sport}
            isSearchMatched={search.status === "matched"}
            regularPairId={search.regularPair?.id ?? null}
            searchId={search.id}
            onOpenProfile={() => setPreviewUser(response.responderUser)}
          />
        ))}
      </div>

      <PlayerPreviewSheet
        user={previewUser}
        searchSport={search.sport}
        onClose={() => setPreviewUser(null)}
      />
    </Panel>
  );
}

function SearchStatusActions({
  searchId,
  isActive,
  status,
  lifecycleStatus,
  regularPairId,
  regularPairMatchId,
  hasResponses
}: {
  searchId: string;
  isActive: boolean;
  status: SearchItem["status"];
  lifecycleStatus: string;
  regularPairId: string | null;
  regularPairMatchId: string | null;
  hasResponses: boolean;
}) {
  const router = useRouter();

  async function updateSearch(active: boolean) {
    await apiFetch(`/game-searches/${searchId}`, {
      method: "PATCH",
      body: JSON.stringify({ isActive: active })
    });
    router.refresh();
  }

  if (status === "matched") {
    return (
      <div className="flex flex-col items-end gap-2">
        <span className="rounded-full bg-mint px-3 py-2 text-xs font-semibold uppercase tracking-[0.18em] text-court">
          {lifecycleStatus}
        </span>
        {regularPairMatchId ? (
          <Link
            href={`/inbox/${regularPairMatchId}`}
            className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink"
          >
            Открыть чат
          </Link>
        ) : null}
        {regularPairId ? (
          <Link
            href={`/play/regular/${regularPairId}`}
            className="rounded-full bg-ink px-3 py-2 text-xs font-semibold text-white"
          >
            Открыть пару
          </Link>
        ) : null}
      </div>
    );
  }

  return (
    <div className="flex flex-col items-end gap-2">
      {hasResponses ? (
        <Link href={`/play/searches/${searchId}`} className="rounded-full bg-ink px-3 py-2 text-xs font-semibold text-white">
          Чат и отклики
        </Link>
      ) : null}
      {status !== "closed" ? <SearchInviteButton searchId={searchId} /> : null}
      <Button variant="ghost" onClick={() => updateSearch(!isActive)}>
        {isActive ? "Закрыть" : "Открыть снова"}
      </Button>
    </div>
  );
}

function SearchResponseCard({
  response,
  canApprove,
  searchSport,
  isSearchMatched,
  regularPairId,
  searchId,
  onOpenProfile
}: {
  response: SearchResponse;
  canApprove: boolean;
  searchSport: SearchItem["sport"];
  isSearchMatched: boolean;
  regularPairId: string | null;
  searchId: string;
  onOpenProfile: () => void;
}) {
  const router = useRouter();

  async function updateStatus(status: SearchResponse["status"]) {
    const data = await apiFetch<{ matchId?: string | null; gameRequestId?: string | null; regularPairId?: string | null }>(`/game-search-responses/${response.id}`, {
      method: "PATCH",
      body: JSON.stringify({ status })
    });
    if (status === "approved" && data.gameRequestId) {
      router.push(`/play/games/${data.gameRequestId}`);
      return;
    }
    if (status === "approved" && data.regularPairId) {
      router.push(`/play/regular/${data.regularPairId}`);
      return;
    }
    if (status === "approved" && data.matchId) {
      if (!data.gameRequestId) {
        router.push(`/play/searches/${searchId}`);
        return;
      }
      router.push(`/inbox/${data.matchId}`);
      return;
    }
    router.refresh();
  }

  return (
    <div className="rounded-[24px] bg-cream p-3">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onOpenProfile}
          className="flex min-w-0 flex-1 items-center gap-3 rounded-[20px] text-left transition-transform duration-200 active:scale-[0.98]"
        >
          <Avatar src={response.responderUser.avatarUrl} alt={response.responderUser.name ?? "Игрок"} className="shrink-0" />
          <div className="min-w-0 flex-1">
            <div className="text-lg font-bold text-ink">{response.responderUser.name}</div>
            <div className="text-sm text-ink/60">
              Уровень {getSportLevel(response.responderUser.sportLevels, searchSport, response.responderUser.tennisLevel ?? 5)}
              {response.responderUser.city ? ` · ${response.responderUser.city}` : ""}
            </div>
          </div>
        </button>
        <span className="rounded-full bg-white px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
          {responseStatusLabel(response.status, isSearchMatched)}
        </span>
      </div>
      {response.status === "approved" && regularPairId ? (
        <div className="mt-3 flex flex-wrap gap-2">
          <Link
            href={`/play/regular/${regularPairId}`}
            className="inline-flex rounded-full bg-mint px-3 py-2 text-xs font-semibold text-court"
          >
            Перейти к регулярной паре
          </Link>
          <Button variant="ghost" onClick={() => updateStatus("rejected")}>
            Убрать из состава
          </Button>
        </div>
      ) : null}
      {response.status === "approved" && !regularPairId ? (
        <div className="mt-3 flex flex-wrap gap-2">
          <Link href={`/play/searches/${searchId}`} className="inline-flex rounded-full bg-mint px-3 py-2 text-xs font-semibold text-court">
            Перейти в чат
          </Link>
          <Button variant="ghost" onClick={() => updateStatus("rejected")}>
            Убрать из состава
          </Button>
        </div>
      ) : null}
      {response.status === "pending" && canApprove ? (
        <div className="mt-3 grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateStatus("approved")}>
            Подтвердить
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateStatus("rejected")}>
            Отменить отклик
          </Button>
        </div>
      ) : null}
    </div>
  );
}

function ApprovedPlayersCard({
  responses,
  searchSport,
  playersNeeded,
  regularPair
}: {
  responses: SearchResponse[];
  searchSport: SearchItem["sport"];
  playersNeeded: number;
  regularPair: SearchItem["regularPair"];
}) {
  const [previewUser, setPreviewUser] = useState<SearchResponse["responderUser"] | null>(null);

  return (
    <div className="rounded-[24px] bg-mint p-4">
      <div className="flex items-center justify-between gap-3">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Подтвержденные игроки</div>
        <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
          {responses.length}/{playersNeeded}
        </span>
      </div>
      <div className="mt-3 space-y-3">
        {responses.map((response) => (
          <button
            key={response.id}
            type="button"
            onClick={() => setPreviewUser(response.responderUser)}
            className="flex w-full items-center gap-3 rounded-[20px] text-left transition-transform duration-200 active:scale-[0.98]"
          >
            <Avatar src={response.responderUser.avatarUrl} alt={response.responderUser.name ?? "Игрок"} className="shrink-0" />
            <div>
              <div className="text-lg font-bold text-ink">{response.responderUser.name}</div>
              <div className="text-sm text-ink/60">
                Уровень {getSportLevel(response.responderUser.sportLevels, searchSport, response.responderUser.tennisLevel ?? 5)}
              </div>
            </div>
          </button>
        ))}
        {responses.length < playersNeeded ? (
          <div className="rounded-2xl bg-white/80 px-4 py-3 text-sm text-ink/65">
            Поиск ещё открыт. Нужно добрать ещё {playersNeeded - responses.length}.
          </div>
        ) : null}
        {regularPair ? (
          <div className="rounded-2xl bg-white/85 px-4 py-3 text-sm text-ink/75">
            Регулярная пара активна с {regularPair.partnerUser.name ?? "игроком"}.
            <div className="mt-3 flex flex-wrap gap-2">
              <Link href={`/play/regular/${regularPair.id}`} className="rounded-full bg-ink px-3 py-2 text-xs font-semibold text-white">
                Открыть регулярную пару
              </Link>
              <Link
                href={`/play/proposals/new?matchId=${regularPair.matchId}`}
                className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink"
              >
                Предложить ближайшую игру
              </Link>
            </div>
          </div>
        ) : null}
      </div>

      <PlayerPreviewSheet
        user={previewUser}
        searchSport={searchSport}
        onClose={() => setPreviewUser(null)}
      />
    </div>
  );
}

function PlayerPreviewSheet({
  user,
  searchSport,
  onClose
}: {
  user: SearchResponse["responderUser"] | null;
  searchSport: SearchItem["sport"];
  onClose: () => void;
}) {
  if (!user) {
    return null;
  }

  const sportEntries = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
  const preferredDistricts = Array.isArray(user.preferredDistricts)
    ? user.preferredDistricts
        .filter((district): district is string => typeof district === "string")
        .map((district) => getDistrictLabel(district) ?? district)
    : [];
  const availabilityDays = Array.isArray(user.availableDays)
    ? user.availableDays.filter((day): day is keyof typeof DAY_LABELS => typeof day === "string" && day in DAY_LABELS)
    : [];
  const availabilityRanges = Array.isArray(user.availableTimeRanges)
    ? user.availableTimeRanges.filter(
        (range): range is keyof typeof TIME_RANGE_LABELS => typeof range === "string" && range in TIME_RANGE_LABELS
      )
    : [];
  const primaryLevel = getSportLevel(user.sportLevels, searchSport, user.tennisLevel ?? 5);
  const locationLine = [user.city, preferredDistricts[0] ?? getDistrictLabel(user.district)].filter(Boolean).join(" · ");

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/42 px-4 pb-6 pt-10 backdrop-blur-[2px]">
      <div className="w-full max-w-md rounded-[30px] border border-white/70 bg-white/96 p-5 shadow-[0_24px_70px_rgba(17,38,29,0.18)]">
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <Avatar src={user.avatarUrl} alt={user.name ?? "Игрок"} size="lg" className="shrink-0" />
            <div className="min-w-0">
              <div className="text-xs font-semibold uppercase tracking-[0.2em] text-court">Профиль игрока</div>
              <div className="mt-1 text-xl font-bold text-ink">
                {user.name ?? "Игрок"}
                {user.age ? `, ${user.age}` : ""}
              </div>
              {locationLine ? (
                <div className="mt-1 flex items-center gap-1.5 text-sm text-ink/62">
                  <MapPin className="h-4 w-4 shrink-0" />
                  <span className="line-clamp-1">{locationLine}</span>
                </div>
              ) : null}
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-full bg-cream p-2 text-ink/60 transition-colors hover:text-ink"
            aria-label="Закрыть"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="mt-4 rounded-[24px] bg-mint p-4">
          <div className="text-xs font-semibold uppercase tracking-[0.2em] text-court">Уровень по твоему поиску</div>
          <div className="mt-2 flex items-center justify-between gap-3">
            <SportBadge sport={searchSport} className="bg-white text-ink" />
            <div className="rounded-full bg-white px-3 py-2 text-sm font-bold text-ink">Уровень {primaryLevel}</div>
          </div>
        </div>

        {sportEntries.length > 0 ? (
          <div className="mt-4">
            <div className="text-xs font-semibold uppercase tracking-[0.2em] text-court">Виды спорта</div>
            <div className="mt-2 flex flex-wrap gap-2">
              {sportEntries.slice(0, 4).map(({ sport, level }) => (
                <SportLevelBadge key={sport} sport={sport} level={level} />
              ))}
            </div>
          </div>
        ) : null}

        {preferredDistricts.length > 0 ? (
          <div className="mt-4">
            <div className="text-xs font-semibold uppercase tracking-[0.2em] text-court">Удобные районы</div>
            <div className="mt-2 flex flex-wrap gap-2">
              {preferredDistricts.slice(0, 4).map((district) => (
                <span key={district} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                  {district}
                </span>
              ))}
            </div>
          </div>
        ) : null}

        {(availabilityDays.length > 0 || availabilityRanges.length > 0) ? (
          <div className="mt-4">
            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em] text-court">
              <CalendarDays className="h-4 w-4" />
              Когда обычно удобно
            </div>
            <div className="mt-2 flex flex-wrap gap-2">
              {availabilityDays.map((day) => (
                <span key={day} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                  {DAY_LABELS[day]}
                </span>
              ))}
              {availabilityRanges.map((range) => (
                <span key={range} className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                  {TIME_RANGE_LABELS[range]}
                </span>
              ))}
            </div>
          </div>
        ) : null}

        <div className="mt-4 rounded-[24px] bg-cream px-4 py-3 text-sm leading-6 text-ink/72">
          {user.bio?.trim() || "Похоже, этот игрок хочет быстро договориться и выйти на игру без лишней переписки."}
        </div>

        <div className="mt-4">
          <Button fullWidth onClick={onClose}>
            Закрыть
          </Button>
        </div>
      </div>
    </div>
  );
}

function responseStatusLabel(status: SearchResponse["status"], isSearchMatched = false) {
  return translateGameSearchResponseStatus(status, { isSearchMatched });
}
