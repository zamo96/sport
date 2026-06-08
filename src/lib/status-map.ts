import {
  GameRequestStatus,
  GameSearchResponseStatus,
  GameSearchStatus,
  RegularPairOccurrenceStatus,
  RegularPairStatus
} from "@prisma/client";

export type GameSearchStatusLike = GameSearchStatus | "active" | "in_review" | "matched" | "closed";
export type GameSearchResponseStatusLike =
  | GameSearchResponseStatus
  | "pending"
  | "approved"
  | "rejected"
  | "withdrawn";
export type GameRequestStatusLike = GameRequestStatus | "pending" | "accepted" | "declined" | "canceled";
export type RegularPairStatusLike = RegularPairStatus | "active" | "paused" | "closed";
export type RegularPairOccurrenceStatusLike =
  | RegularPairOccurrenceStatus
  | "pending"
  | "confirmed"
  | "declined"
  | "canceled"
  | "expired";

export function translateGameSearchStatus(status: GameSearchStatusLike) {
  switch (status) {
    case "active":
      return "Идет набор";
    case "in_review":
      return "Ожидает решения";
    case "matched":
      return "Игроки найдены";
    case "closed":
      return "Закрыт";
    default:
      return status;
  }
}

export function translateGameSearchResponseStatus(
  status: GameSearchResponseStatusLike,
  options?: { isSearchMatched?: boolean }
) {
  switch (status) {
    case "pending":
      return "Ожидает";
    case "approved":
      return "Подтвержден";
    case "rejected":
      return options?.isSearchMatched ? "Игрок найден" : "Отклонен";
    case "withdrawn":
      return "Отозван";
    default:
      return status;
  }
}

export function translateGameRequestStatus(status: GameRequestStatusLike, options?: { isCreator?: boolean }) {
  switch (status) {
    case "pending":
      return options?.isCreator ? "Игра создана" : "Тебя добавили";
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

export function translateRegularPairStatus(status: RegularPairStatusLike) {
  switch (status) {
    case "active":
      return "Активная пара";
    case "paused":
      return "Пара на паузе";
    case "closed":
      return "Пара закрыта";
    default:
      return status;
  }
}

export function translateRegularPairOccurrenceStatus(status: RegularPairOccurrenceStatusLike) {
  switch (status) {
    case "pending":
      return "Ожидает подтверждения";
    case "confirmed":
      return "Игра подтверждена";
    case "declined":
      return "Отклонено";
    case "canceled":
      return "Отменено";
    case "expired":
      return "Истекло";
    default:
      return status;
  }
}
