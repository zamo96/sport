import { GameRequestOutcome, GameRequestStatus } from "@prisma/client";

export function isPastGameRequest(proposedDatetime: string | Date) {
  return new Date(proposedDatetime).getTime() < Date.now();
}

export function needsGameRequestOutcome(
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled",
  proposedDatetime: string | Date,
  outcome?: GameRequestOutcome | "played" | "not_played" | null
) {
  return status === "accepted" && isPastGameRequest(proposedDatetime) && !outcome;
}

export function translateGameRequestStatus(
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled"
) {
  switch (status) {
    case "pending":
      return "Ожидает ответа";
    case "accepted":
      return "Игра подтверждена";
    case "declined":
      return "Отклонено";
    case "canceled":
      return "Отменено";
    default:
      return status;
  }
}

export function translateGameRequestOutcome(
  outcome?: GameRequestOutcome | "played" | "not_played" | null
) {
  switch (outcome) {
    case "played":
      return "Сыграли";
    case "not_played":
      return "Не сыграли";
    default:
      return null;
  }
}

export function getGameRequestTone(options: {
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled";
  proposedDatetime: string | Date;
  outcome?: GameRequestOutcome | "played" | "not_played" | null;
}) {
  const { status, proposedDatetime, outcome } = options;

  if (outcome === "played") {
    return {
      panelClassName: "bg-mint/70",
      badgeClassName: "bg-emerald-100 text-emerald-800",
      badgeLabel: "Сыграли"
    };
  }

  if (outcome === "not_played") {
    return {
      panelClassName: "bg-red-50",
      badgeClassName: "bg-red-100 text-red-700",
      badgeLabel: "Не сыграли"
    };
  }

  if (needsGameRequestOutcome(status, proposedDatetime, outcome)) {
    return {
      panelClassName: "bg-amber-50",
      badgeClassName: "bg-amber-100 text-amber-800",
      badgeLabel: "Нужен ответ"
    };
  }

  switch (status) {
    case "accepted":
      return {
        panelClassName: "bg-mint/60",
        badgeClassName: "bg-mint text-court",
        badgeLabel: "Подтверждено"
      };
    case "declined":
      return {
        panelClassName: "bg-stone-100",
        badgeClassName: "bg-stone-200 text-stone-700",
        badgeLabel: "Отклонено"
      };
    case "canceled":
      return {
        panelClassName: "bg-stone-100",
        badgeClassName: "bg-stone-200 text-stone-700",
        badgeLabel: "Отменено"
      };
    case "pending":
    default:
      return {
        panelClassName: "bg-cream",
        badgeClassName: "bg-mint text-court",
        badgeLabel: "Ожидает"
      };
  }
}
