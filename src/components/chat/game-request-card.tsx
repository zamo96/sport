"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import {
  getGameRequestDetailsLabel,
  getGameRequestHeading,
  getGameRequestNextStep,
  getGameRequestTone,
  isPastGameRequest,
  needsGameRequestOutcome,
  translateGameRequestOutcome,
  translateGameRequestStatus
} from "@/lib/game-requests";
import { resolveScheduledGameStatus } from "@/lib/game-search";
import { SportBadge } from "@/components/ui/sport-badge";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

type GameRequestCardProps = {
  gameRequest: {
    id: string;
    sourceType?: "game_request" | "regular_occurrence";
    regularPairId?: string | null;
    status: "pending" | "accepted" | "declined" | "canceled";
    outcome?: "played" | "not_played" | null;
    outcomeUpdatedAt?: string | null;
    proposedDatetime: string;
    durationMinutes?: number | null;
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
  const isRegularOccurrence = gameRequest.sourceType === "regular_occurrence";
  const isCreator = gameRequest.createdByUserId === currentUserId;
  const isRecipient = gameRequest.matchedUserId === currentUserId;
  const isPending = gameRequest.status === "pending";
  const isAcceptedUpcoming = gameRequest.status === "accepted" && !isPastGameRequest(gameRequest.proposedDatetime);
  const tone = getGameRequestTone({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    outcome: gameRequest.outcome,
    isCreator
  });
  const outcomeLabel = translateGameRequestOutcome(gameRequest.outcome);
  const scheduledStatusLabel =
    gameRequest.status === "accepted"
      ? resolveScheduledGameStatus(gameRequest.proposedDatetime, gameRequest.durationMinutes)
      : null;
  const isAwaitingOutcome = needsGameRequestOutcome(
    gameRequest.status,
    gameRequest.proposedDatetime,
    gameRequest.outcome
  );
  const heading = getGameRequestHeading({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    isRegularOccurrence
  });
  const nextStep = getGameRequestNextStep({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    outcome: gameRequest.outcome,
    isCreator,
    isRegularOccurrence
  });
  const detailsLabel = getGameRequestDetailsLabel({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    isRegularOccurrence
  });

  async function updateRequest(body: {
    status?: "accepted" | "declined" | "canceled";
    outcome?: "played" | "not_played" | null;
  }) {
    if (isRegularOccurrence) {
      return;
    }

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
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">{heading}</div>
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
        {gameRequest.durationMinutes ? (
          <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
            {gameRequest.durationMinutes} мин
          </span>
        ) : null}
        {scheduledStatusLabel ? (
          <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">{scheduledStatusLabel}</span>
        ) : null}
        <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
          {translateGameRequestStatus(gameRequest.status, { isCreator })}
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
      {nextStep ? (
        <div className="rounded-2xl bg-white/85 px-4 py-3 text-sm text-ink/70">
          {nextStep}
        </div>
      ) : null}
      {isPending && isRecipient && !isRegularOccurrence ? (
        <div className="grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateRequest({ status: "accepted" })}>
            Подтвердить
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "declined" })}>
            Отклонить
          </Button>
        </div>
      ) : null}
      {isPending && isCreator && !isRegularOccurrence ? (
        <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "canceled" })}>
          Отменить предложение
        </Button>
      ) : null}
      {isAcceptedUpcoming && !isRegularOccurrence ? (
        <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "canceled" })}>
          Отменить подтвержденную игру
        </Button>
      ) : null}
      {isAwaitingOutcome && !isRegularOccurrence ? (
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
            {detailsLabel}
          </div>
        </Link>
      ) : null}
    </Panel>
  );
}
