"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import {
  getGameRequestTone,
  needsGameRequestOutcome,
  translateGameRequestOutcome,
  translateGameRequestStatus
} from "@/lib/game-requests";
import { SportBadge } from "@/components/ui/sport-badge";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

type GameRequestCardProps = {
  gameRequest: {
    id: string;
    status: "pending" | "accepted" | "declined" | "canceled";
    outcome?: "played" | "not_played" | null;
    outcomeUpdatedAt?: string | null;
    proposedDatetime: string;
    comment: string | null;
    sport: Sport;
    format: string;
    createdByUserId: string;
    matchedUserId: string;
    proposedCourt: {
      name: string;
      address: string;
    };
  };
  currentUserId: string;
  detailsHref?: string;
};

export function GameRequestCard({ gameRequest, currentUserId, detailsHref }: GameRequestCardProps) {
  const router = useRouter();
  const isRecipient = gameRequest.matchedUserId === currentUserId;
  const isPending = gameRequest.status === "pending";
  const tone = getGameRequestTone({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    outcome: gameRequest.outcome
  });
  const outcomeLabel = translateGameRequestOutcome(gameRequest.outcome);
  const isAwaitingOutcome = needsGameRequestOutcome(
    gameRequest.status,
    gameRequest.proposedDatetime,
    gameRequest.outcome
  );

  async function updateRequest(body: {
    status?: "accepted" | "declined" | "canceled";
    outcome?: "played" | "not_played" | null;
  }) {
    await apiFetch(`/game-requests/${gameRequest.id}`, {
      method: "PATCH",
      body: JSON.stringify(body)
    });
    router.refresh();
  }

  return (
    <Panel className={`space-y-3 ${tone.panelClassName}`}>
      <div className="flex items-center justify-between">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Предложение игры</div>
          <div className="mt-1 text-lg font-bold text-ink">{new Date(gameRequest.proposedDatetime).toLocaleString()}</div>
        </div>
        <span className={`rounded-full px-3 py-2 text-xs font-semibold uppercase tracking-[0.18em] ${tone.badgeClassName}`}>
          {tone.badgeLabel}
        </span>
      </div>
      <div className="text-sm leading-6 text-ink/72">
        {gameRequest.proposedCourt.name}, {gameRequest.proposedCourt.address}
      </div>
      <div className="flex flex-wrap gap-2">
        <SportBadge sport={gameRequest.sport} className="bg-white text-ink" />
        <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">{gameRequest.format}</span>
        <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
          {translateGameRequestStatus(gameRequest.status)}
        </span>
        {outcomeLabel ? (
          <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">{outcomeLabel}</span>
        ) : null}
        {gameRequest.comment ? (
          <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
            {gameRequest.comment}
          </span>
        ) : null}
      </div>
      {isAwaitingOutcome ? (
        <div className="rounded-2xl bg-white/85 px-4 py-3 text-sm text-ink/70">
          Игра уже должна была пройти. Подтверди, удалось ли сыграть.
        </div>
      ) : null}
      {isPending && isRecipient ? (
        <div className="grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateRequest({ status: "accepted" })}>
            Принять
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "declined" })}>
            Отклонить
          </Button>
        </div>
      ) : null}
      {isPending && !isRecipient ? (
        <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "canceled" })}>
          Отменить предложение
        </Button>
      ) : null}
      {isAwaitingOutcome ? (
        <div className="grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateRequest({ outcome: "played" })}>
            Да, сыграли
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateRequest({ outcome: "not_played" })}>
            Нет, не вышло
          </Button>
        </div>
      ) : null}
      {detailsHref ? (
        <Link href={detailsHref} className="block">
          <div className="rounded-2xl bg-white/80 px-4 py-3 text-center text-sm font-semibold text-ink">
            Открыть детали и чат
          </div>
        </Link>
      ) : null}
    </Panel>
  );
}
