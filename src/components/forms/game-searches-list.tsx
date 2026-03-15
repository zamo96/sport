"use client";

import Link from "next/link";
import { Flame } from "lucide-react";
import { useRouter } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import { DAY_LABELS, GAME_SEARCH_TYPE_LABELS, HOT_SEARCH_WINDOW_LABELS, PLAY_FORMAT_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { getSportLevel } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";

type SearchResponse = {
  id: string;
  status: "pending" | "approved" | "rejected" | "withdrawn";
  responderUser: {
    id: string;
    name: string | null;
    avatarUrl: string | null;
    tennisLevel: number | null;
    sportLevels?: unknown;
    city: string | null;
  };
};

type SearchItem = {
  id: string;
  status: "active" | "in_review" | "matched" | "closed";
  searchType: "regular" | "hot";
  hotWindow: "today" | "tomorrow" | null;
  hasCourtBooked: boolean;
  sport: "tennis" | "padel" | "badminton" | "squash" | "pickleball";
  preferredDays: unknown;
  preferredTimeRanges: unknown;
  format: "singles" | "doubles" | "both";
  comment: string | null;
  isActive: boolean;
  preferredCourt: {
    name: string;
  } | null;
  responses: SearchResponse[];
};

export function GameSearchesList({ searches }: { searches: SearchItem[] }) {
  return (
    <div className="space-y-4">
      {searches.length === 0 ? (
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

      {searches.map((search) => (
        <GameSearchCard key={search.id} search={search} />
      ))}
    </div>
  );
}

function GameSearchCard({ search }: { search: SearchItem }) {
  const days = Array.isArray(search.preferredDays) ? search.preferredDays : [];
  const timeRanges = Array.isArray(search.preferredTimeRanges) ? search.preferredTimeRanges : [];
  const pendingResponses = search.responses.filter((response) => response.status === "pending");
  const approvedResponse = search.responses.find((response) => response.status === "approved");

  return (
    <Panel className="space-y-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Мой поиск игры</div>
          <div className="mt-1 text-xl font-bold text-ink">{statusLabel(search.status)}</div>
          <div className="mt-1 text-sm text-ink/60">
            Ожидают ответа: {pendingResponses.length}
          </div>
        </div>
        <SearchStatusActions searchId={search.id} isActive={search.isActive} status={search.status} />
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
          {PLAY_FORMAT_LABELS[search.format]}
        </span>
        <SportBadge sport={search.sport} className="bg-cream text-ink" />
        {search.hotWindow ? (
          <span className="rounded-full bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
            {HOT_SEARCH_WINDOW_LABELS[search.hotWindow]}
          </span>
        ) : null}
        {search.hasCourtBooked ? (
          <span className="rounded-full bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">Корт уже есть</span>
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

      {approvedResponse ? (
        <ApprovedPlayerCard response={approvedResponse} searchSport={search.sport} />
      ) : (
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
              canApprove={search.status !== "matched"}
              searchSport={search.sport}
            />
          ))}
        </div>
      )}
    </Panel>
  );
}

function SearchStatusActions({
  searchId,
  isActive,
  status
}: {
  searchId: string;
  isActive: boolean;
  status: SearchItem["status"];
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
      <span className="rounded-full bg-mint px-3 py-2 text-xs font-semibold uppercase tracking-[0.18em] text-court">
        мэтч
      </span>
    );
  }

  return (
    <Button variant="ghost" onClick={() => updateSearch(!isActive)}>
      {isActive ? "Закрыть" : "Открыть снова"}
    </Button>
  );
}

function SearchResponseCard({
  response,
  canApprove,
  searchSport
}: {
  response: SearchResponse;
  canApprove: boolean;
  searchSport: SearchItem["sport"];
}) {
  const router = useRouter();

  async function updateStatus(status: SearchResponse["status"]) {
    const data = await apiFetch<{ matchId?: string | null }>(`/game-search-responses/${response.id}`, {
      method: "PATCH",
      body: JSON.stringify({ status })
    });
    if (status === "approved" && data.matchId) {
      router.push(`/inbox/${data.matchId}`);
      return;
    }
    router.refresh();
  }

  return (
    <div className="rounded-[24px] bg-cream p-3">
      <div className="flex items-center gap-3">
        <Avatar src={response.responderUser.avatarUrl} alt={response.responderUser.name ?? "Игрок"} />
        <div className="min-w-0 flex-1">
          <div className="text-lg font-bold text-ink">{response.responderUser.name}</div>
          <div className="text-sm text-ink/60">
            Уровень {getSportLevel(response.responderUser.sportLevels, searchSport, response.responderUser.tennisLevel ?? 5)}
            {response.responderUser.city ? ` · ${response.responderUser.city}` : ""}
          </div>
        </div>
        <span className="rounded-full bg-white px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
          {responseStatusLabel(response.status)}
        </span>
      </div>
      {response.status === "pending" && canApprove ? (
        <div className="mt-3 grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateStatus("approved")}>
            Подтвердить
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateStatus("rejected")}>
            Отклонить
          </Button>
        </div>
      ) : null}
    </div>
  );
}

function ApprovedPlayerCard({
  response,
  searchSport
}: {
  response: SearchResponse;
  searchSport: SearchItem["sport"];
}) {
  return (
    <div className="rounded-[24px] bg-mint p-4">
      <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Выбранный игрок</div>
      <div className="mt-3 flex items-center gap-3">
        <Avatar src={response.responderUser.avatarUrl} alt={response.responderUser.name ?? "Игрок"} />
        <div>
          <div className="text-lg font-bold text-ink">{response.responderUser.name}</div>
          <div className="text-sm text-ink/60">
            Уровень {getSportLevel(response.responderUser.sportLevels, searchSport, response.responderUser.tennisLevel ?? 5)}
          </div>
        </div>
      </div>
    </div>
  );
}

function statusLabel(status: SearchItem["status"]) {
  switch (status) {
    case "active":
      return "Активен";
    case "in_review":
      return "Есть отклики";
    case "matched":
      return "Игрок выбран";
    case "closed":
      return "Закрыт";
    default:
      return status;
  }
}

function responseStatusLabel(status: SearchResponse["status"]) {
  switch (status) {
    case "pending":
      return "ожидает";
    case "approved":
      return "подтвержден";
    case "rejected":
      return "отклонен";
    case "withdrawn":
      return "отозван";
    default:
      return status;
  }
}
