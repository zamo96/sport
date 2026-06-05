import { GameRequestOutcome, GameRequestStatus } from "@prisma/client";

export { translateGameRequestStatus } from "./status-map";

export function isPastGameRequest(proposedDatetime: string | Date) {
  return new Date(proposedDatetime).getTime() < Date.now();
}

export function isAcceptedUpcomingGameRequest(
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled",
  proposedDatetime: string | Date
) {
  return status === "accepted" && !isPastGameRequest(proposedDatetime);
}

export function needsGameRequestOutcome(
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled",
  proposedDatetime: string | Date,
  outcome?: GameRequestOutcome | "played" | "not_played" | null
) {
  return status === "accepted" && isPastGameRequest(proposedDatetime) && !outcome;
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
  isCreator?: boolean;
}) {
  const { status, proposedDatetime, outcome, isCreator } = options;

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
        badgeLabel: isCreator ? "Ждём ответ" : "Нужно решение"
      };
  }
}

export function getGameRequestHeading(options: {
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled";
  proposedDatetime: string | Date;
  isRegularOccurrence?: boolean;
}) {
  const { status, proposedDatetime, isRegularOccurrence } = options;

  if (isRegularOccurrence && isAcceptedUpcomingGameRequest(status, proposedDatetime)) {
    return "Подтвержденная игра";
  }

  if (isAcceptedUpcomingGameRequest(status, proposedDatetime)) {
    return "Подтвержденная игра";
  }

  return "Предложение игры";
}

export function getGameRequestNextStep(options: {
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled";
  proposedDatetime: string | Date;
  outcome?: GameRequestOutcome | "played" | "not_played" | null;
  isCreator?: boolean;
  isRegularOccurrence?: boolean;
}) {
  const { status, proposedDatetime, outcome, isCreator, isRegularOccurrence } = options;

  if (isRegularOccurrence && isAcceptedUpcomingGameRequest(status, proposedDatetime)) {
    return "Ближайшая игра по регулярной паре подтверждена. Если нужно поменять следующий слот, открой регулярную пару.";
  }

  if (needsGameRequestOutcome(status, proposedDatetime, outcome)) {
    return "Игра уже должна была пройти. Подтверди, удалось ли сыграть, чтобы состояние договоренности стало понятным обоим.";
  }

  switch (status) {
    case "pending":
      return isCreator
        ? "Ждём подтверждение второго игрока. Как только он ответит, игра перейдёт в подтвержденные."
        : "Тебя пригласили на игру. Подтверди, если время и место подходят, чтобы сразу зафиксировать встречу.";
    case "accepted":
      return "Игра подтверждена. Следующий шаг: открой детали игры и обсуди только финальные нюансы.";
    case "declined":
      return "Эта договоренность не состоялась. Если всё ещё хочешь сыграть, создай новую игру или вернись в общий чат.";
    case "canceled":
      return "Эта договоренность отменена. Если планы изменились, начни новую договоренность из мэтча или поиска.";
    default:
      return null;
  }
}

export function getGameRequestDetailsLabel(options: {
  status: GameRequestStatus | "pending" | "accepted" | "declined" | "canceled";
  proposedDatetime: string | Date;
  isRegularOccurrence?: boolean;
}) {
  const { status, proposedDatetime, isRegularOccurrence } = options;

  if (isRegularOccurrence && isAcceptedUpcomingGameRequest(status, proposedDatetime)) {
    return "Открыть регулярную пару";
  }

  if (isAcceptedUpcomingGameRequest(status, proposedDatetime)) {
    return "Открыть подтвержденную игру";
  }

  return "Открыть детали игры";
}
