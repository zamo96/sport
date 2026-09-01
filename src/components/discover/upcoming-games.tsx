"use client";

import Link from "next/link";

import { useLocale } from "@/components/i18n/locale-provider";
import { GameRequestCard } from "@/components/chat/game-request-card";
import { Panel } from "@/components/ui/panel";

type UpcomingGame = {
  id: string;
  opponentName: string | null;
  matchId: string;
  searchLobbyId?: string | null;
  sourceType?: "game_request" | "regular_occurrence";
  regularPairId?: string | null;
  status: "pending" | "accepted" | "declined" | "canceled";
  outcome?: "played" | "not_played" | null;
  outcomeUpdatedAt?: string | null;
  proposedDatetime: string;
  comment: string | null;
  sport: import("@prisma/client").Sport;
  format: string;
  createdByUserId: string;
  matchedUserId: string;
  participants?: Array<{
    id: string;
    name: string | null;
  }>;
  proposedCourt: {
    name: string;
    address: string;
  } | null;
};

export function UpcomingGames({ currentUserId, games }: { currentUserId: string; games: UpcomingGame[] }) {
  const { t } = useLocale();
  if (games.length === 0) {
    return null;
  }

  function visibleParticipants(game: UpcomingGame) {
    return (game.participants ?? []).filter((participant) => participant.id !== currentUserId);
  }

  function rosterLabel(game: UpcomingGame) {
    const count = visibleParticipants(game).length + 1;
    return t("discover.upcoming.roster", { count });
  }

  function rosterNames(game: UpcomingGame) {
    const names = visibleParticipants(game)
      .map((participant) => participant.name?.trim())
      .filter((name): name is string => Boolean(name));

    if (names.length === 0) {
      return null;
    }

    return names.join(", ");
  }

  return (
    <div className="space-y-3">
      <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">{t("discover.upcoming.title")}</div>
      {games.map((game) => (
        <div key={game.id} className="space-y-2">
          <Panel className="flex items-center justify-between gap-3 bg-cream">
            <div>
              <div className="text-sm font-semibold text-ink">{game.opponentName ?? t("discover.common.player")}</div>
              {(game.participants?.length ?? 0) > 2 ? (
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  <span className="rounded-full bg-white px-2.5 py-1 text-[11px] font-semibold text-ink/80">
                    {rosterLabel(game)}
                  </span>
                  {rosterNames(game) ? (
                    <span className="text-xs text-ink/62">{rosterNames(game)}</span>
                  ) : null}
                </div>
              ) : null}
              <div className="text-xs text-ink/60">
                {game.sourceType === "regular_occurrence"
                  ? t("discover.upcoming.regularText")
                  : t("discover.upcoming.gameText")}
              </div>
            </div>
            <Link
              href={game.searchLobbyId ? `/play/searches/${game.searchLobbyId}` : `/inbox/${game.matchId}`}
              className="rounded-2xl bg-white px-4 py-3 text-sm font-semibold text-ink"
            >
              {game.searchLobbyId ? t("discover.upcoming.rosterChat") : t("discover.upcoming.sharedChat")}
            </Link>
          </Panel>
          <GameRequestCard
            gameRequest={game}
            currentUserId={currentUserId}
            detailsHref={game.sourceType === "regular_occurrence" ? `/play/regular/${game.regularPairId}` : `/play/games/${game.id}`}
          />
        </div>
      ))}
    </div>
  );
}
