"use client";

import Link from "next/link";

import { GameRequestCard } from "@/components/chat/game-request-card";
import { Panel } from "@/components/ui/panel";

type UpcomingGame = {
  id: string;
  opponentName: string | null;
  matchId: string;
  status: "pending" | "accepted" | "declined" | "canceled";
  outcome?: "played" | "not_played" | null;
  outcomeUpdatedAt?: string | null;
  proposedDatetime: string;
  comment: string | null;
  sport: import("@prisma/client").Sport;
  format: string;
  createdByUserId: string;
  matchedUserId: string;
  proposedCourt: {
    name: string;
    address: string;
  };
};

export function UpcomingGames({ currentUserId, games }: { currentUserId: string; games: UpcomingGame[] }) {
  if (games.length === 0) {
    return null;
  }

  return (
    <div className="space-y-3">
      <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Ближайшие игры</div>
      {games.map((game) => (
        <div key={game.id} className="space-y-2">
          <Panel className="flex items-center justify-between gap-3 bg-cream">
            <div>
              <div className="text-sm font-semibold text-ink">{game.opponentName ?? "Игрок"}</div>
              <div className="text-xs text-ink/60">Не забудь про эту договоренность. Если планы меняются, отмени игру заранее.</div>
            </div>
            <Link href={`/inbox/${game.matchId}`} className="rounded-2xl bg-white px-4 py-3 text-sm font-semibold text-ink">
              Общий чат
            </Link>
          </Panel>
          <GameRequestCard
            gameRequest={game}
            currentUserId={currentUserId}
            detailsHref={`/play/games/${game.id}`}
          />
        </div>
      ))}
    </div>
  );
}
