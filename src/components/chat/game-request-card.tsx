"use client";

import { useRouter } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import { SportBadge } from "@/components/ui/sport-badge";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

type GameRequestCardProps = {
  gameRequest: {
    id: string;
    status: "pending" | "accepted" | "declined" | "canceled";
    proposedDatetime: string;
    comment: string | null;
    sport: "tennis" | "padel" | "badminton" | "squash" | "pickleball";
    format: string;
    createdByUserId: string;
    matchedUserId: string;
    proposedCourt: {
      name: string;
      address: string;
    };
  };
  currentUserId: string;
};

export function GameRequestCard({ gameRequest, currentUserId }: GameRequestCardProps) {
  const router = useRouter();
  const isRecipient = gameRequest.matchedUserId === currentUserId;
  const isPending = gameRequest.status === "pending";

  async function updateStatus(status: "accepted" | "declined" | "canceled") {
    await apiFetch(`/game-requests/${gameRequest.id}`, {
      method: "PATCH",
      body: JSON.stringify({ status })
    });
    router.refresh();
  }

  return (
    <Panel className="space-y-3 bg-cream">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Предложение игры</div>
          <div className="mt-1 text-lg font-bold text-ink">{new Date(gameRequest.proposedDatetime).toLocaleString()}</div>
        </div>
        <span className="rounded-full bg-mint px-3 py-2 text-xs font-semibold uppercase tracking-[0.18em] text-court">
          {translateGameRequestStatus(gameRequest.status)}
        </span>
      </div>
      <div className="text-sm leading-6 text-ink/72">
        {gameRequest.proposedCourt.name}, {gameRequest.proposedCourt.address}
      </div>
      <div className="flex flex-wrap gap-2">
        <SportBadge sport={gameRequest.sport} className="bg-white text-ink" />
        <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">{gameRequest.format}</span>
        {gameRequest.comment ? (
          <span className="rounded-full bg-white px-3 py-2 text-xs font-semibold text-ink">
            {gameRequest.comment}
          </span>
        ) : null}
      </div>
      {isPending && isRecipient ? (
        <div className="grid grid-cols-2 gap-3">
          <Button fullWidth onClick={() => updateStatus("accepted")}>
            Принять
          </Button>
          <Button fullWidth variant="ghost" onClick={() => updateStatus("declined")}>
            Отклонить
          </Button>
        </div>
      ) : null}
      {isPending && !isRecipient ? (
        <Button fullWidth variant="ghost" onClick={() => updateStatus("canceled")}>
          Отменить предложение
        </Button>
      ) : null}
    </Panel>
  );
}

function translateGameRequestStatus(status: GameRequestCardProps["gameRequest"]["status"]) {
  switch (status) {
    case "pending":
      return "ожидает";
    case "accepted":
      return "принято";
    case "declined":
      return "отклонено";
    case "canceled":
      return "отменено";
    default:
      return status;
  }
}
