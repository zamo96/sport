"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { useLocale } from "@/components/i18n/locale-provider";
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
    } | null;
  };
  currentUserId: string;
  detailsHref?: string;
};

export function GameRequestCard({ gameRequest, currentUserId, detailsHref }: GameRequestCardProps) {
  const router = useRouter();
  const { locale } = useLocale();
  const localize = (value: string | null) => (value ? localizeGameRequestText(locale, value) : value);
  const isRegularOccurrence = gameRequest.sourceType === "regular_occurrence";
  const isCreator = gameRequest.createdByUserId === currentUserId;
  const isRecipient = gameRequest.matchedUserId === currentUserId;
  const isPending = gameRequest.status === "pending";
  const isAcceptedUpcoming = gameRequest.status === "accepted" && !isPastGameRequest(gameRequest.proposedDatetime);
  const canEdit = !isRegularOccurrence && (isCreator || isRecipient) && (isPending || isAcceptedUpcoming);
  const tone = getGameRequestTone({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    outcome: gameRequest.outcome,
    isCreator
  });
  const outcomeLabel = localize(translateGameRequestOutcome(gameRequest.outcome));
  const scheduledStatusLabel =
    gameRequest.status === "accepted"
      ? localize(resolveScheduledGameStatus(gameRequest.proposedDatetime, gameRequest.durationMinutes))
      : null;
  const isAwaitingOutcome = needsGameRequestOutcome(
    gameRequest.status,
    gameRequest.proposedDatetime,
    gameRequest.outcome
  );
  const heading = localize(getGameRequestHeading({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    isRegularOccurrence
  }));
  const nextStep = localize(getGameRequestNextStep({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    outcome: gameRequest.outcome,
    isCreator,
    isRegularOccurrence
  }));
  const detailsLabel = localize(getGameRequestDetailsLabel({
    status: gameRequest.status,
    proposedDatetime: gameRequest.proposedDatetime,
    isRegularOccurrence
  }));

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
          <div className="mt-1 text-lg font-bold text-ink">
            {new Date(gameRequest.proposedDatetime).toLocaleString(locale === "ru" ? "ru-RU" : "en-US")}
          </div>
        </div>
        <span className={`rounded-full px-3 py-2 text-xs font-semibold uppercase tracking-[0.18em] ${tone.badgeClassName}`}>
          {localize(tone.badgeLabel)}
        </span>
      </div>
      <div className="text-sm leading-6 text-ink/72">
        {gameRequest.proposedCourt
          ? `${gameRequest.proposedCourt.name}, ${gameRequest.proposedCourt.address}`
          : locale === "ru" ? "Место уточняется в чате игры" : "Venue to be confirmed in the game chat"}
      </div>
      <div className="flex flex-wrap gap-2">
        <SportBadge sport={gameRequest.sport} className="bg-white text-ink" />
        <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">{gameRequest.format}</span>
        {gameRequest.durationMinutes ? (
          <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
            {gameRequest.durationMinutes} {locale === "ru" ? "мин" : "min"}
          </span>
        ) : null}
        {scheduledStatusLabel ? (
          <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">{scheduledStatusLabel}</span>
        ) : null}
        <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
          {localize(translateGameRequestStatus(gameRequest.status, { isCreator }))}
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
      {isPending && isCreator && !isRegularOccurrence ? (
        <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "canceled" })}>
          {locale === "ru" ? "Отменить предложение" : "Cancel proposal"}
        </Button>
      ) : null}
      {isPending && isRecipient && !isRegularOccurrence ? (
        <div className="grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateRequest({ status: "accepted" })}>
            {locale === "ru" ? "Подтвердить" : "Confirm"}
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "declined" })}>
            {locale === "ru" ? "Отклонить" : "Decline"}
          </Button>
        </div>
      ) : null}
      {isAcceptedUpcoming && !isRegularOccurrence ? (
        <Button fullWidth variant="ghost" onClick={() => updateRequest({ status: "canceled" })}>
          {locale === "ru" ? "Отменить подтвержденную игру" : "Cancel confirmed game"}
        </Button>
      ) : null}
      {isAwaitingOutcome && !isRegularOccurrence ? (
        <div className="grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateRequest({ outcome: "played" })}>
            {locale === "ru" ? "Да, сыграли" : "Yes, we played"}
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateRequest({ outcome: "not_played" })}>
            {locale === "ru" ? "Нет, не вышло" : "No, it didn't happen"}
          </Button>
        </div>
      ) : null}
      {canEdit || detailsHref ? (
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {canEdit ? (
            <Link href={`/play/proposals/new?gameRequestId=${gameRequest.id}`} className="block">
              <div className="rounded-2xl bg-ink px-4 py-3 text-center text-sm font-semibold text-white">
                {locale === "ru" ? "Изменить игру" : "Edit game"}
              </div>
            </Link>
          ) : null}
          {detailsHref ? (
            <Link href={detailsHref} className="block">
              <div className="rounded-2xl bg-white/80 px-4 py-3 text-center text-sm font-semibold text-ink">
                {detailsLabel}
              </div>
            </Link>
          ) : null}
        </div>
      ) : null}
    </Panel>
  );
}

const GAME_REQUEST_ENGLISH: Record<string, string> = {
  "Сыграли": "Played",
  "Не сыграли": "Not played",
  "Нужен ответ": "Response needed",
  "Подтверждено": "Confirmed",
  "Отклонено": "Declined",
  "Отменено": "Canceled",
  "Ожидает подтверждения": "Awaiting confirmation",
  "Требуется ответ": "Response required",
  "Подтвержденная игра": "Confirmed game",
  "Предложение игры": "Game proposal",
  "Игра закончилась": "Game ended",
  "Игра идет": "Game in progress",
  "Игра началась": "Game started",
  "Скоро начнется": "Starting soon",
  "Игроки найдены": "Players found",
  "Игрок найден": "Player found",
  "В процессе набора": "Recruiting players",
  "Закрыт": "Closed",
  "Поиск": "Search",
  "Ближайшая игра по регулярной паре подтверждена. Если нужно поменять следующий слот, открой регулярную пару.":
    "The next regular game is confirmed. Open the regular pair to change the next time slot.",
  "Игра уже должна была пройти. Подтверди, удалось ли сыграть, чтобы состояние договоренности стало понятным обоим.":
    "The game should already have happened. Confirm whether you played so the result is clear to both players.",
  "Предложение отправлено. Ждём подтверждение второго игрока.":
    "Proposal sent. Waiting for the other player's confirmation.",
  "Подтверди или отклони предложение, чтобы игра стала понятна обоим.":
    "Confirm or decline the proposal so the game status is clear to both players.",
  "Игра подтверждена. Следующий шаг: открой детали игры и обсуди только финальные нюансы.":
    "The game is confirmed. Open the game details to discuss the final arrangements.",
  "Эта договоренность не состоялась. Если всё ещё хочешь сыграть, создай новую игру или вернись в общий чат.":
    "This arrangement did not happen. Create a new game or return to the shared chat if you still want to play.",
  "Эта договоренность отменена. Если планы изменились, начни новую договоренность из мэтча или поиска.":
    "This arrangement was canceled. Start a new one from the match or search if plans change.",
  "Открыть регулярную пару": "Open regular pair",
  "Открыть подтвержденную игру": "Open confirmed game",
  "Открыть детали игры": "Open game details",
  "Ожидает ответа": "Awaiting response",
  "Ждёт вашего ответа": "Awaiting your response",
  "Принято": "Accepted"
};

function localizeGameRequestText(locale: "en" | "ru", value: string) {
  return locale === "ru" ? value : GAME_REQUEST_ENGLISH[value] ?? value;
}
