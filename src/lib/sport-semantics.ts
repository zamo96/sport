import { PlayFormat, Sport } from "@prisma/client";

const RACKET_LIKE_SPORTS: ReadonlySet<Sport> = new Set([
  Sport.table_tennis,
  Sport.tennis,
  Sport.padel,
  Sport.squash,
  Sport.badminton
]);

export function getSportVenueShortLabelRu(sport: Sport): string {
  switch (sport) {
    case Sport.fitness:
    case Sport.boxing:
      return "Зал";
    case Sport.yoga:
      return "Студия";
    case Sport.football:
      return "Поле";
    case Sport.volleyball:
    case Sport.badminton:
      return "Площадка";
    case Sport.table_tennis:
      return "Стол";
    case Sport.tennis:
    case Sport.padel:
    case Sport.squash:
    default:
      return "Корт";
  }
}

export type SportPlayFormatLabelOptions = {
  playersNeeded?: number | null | undefined;
};

export function getSportPlayFormatLabelRu(
  sport: Sport,
  format: PlayFormat,
  options: SportPlayFormatLabelOptions = {}
): string {
  const playersNeeded = options.playersNeeded ?? 0;

  if (format === PlayFormat.both) {
    return "Любой формат";
  }

  if (format === PlayFormat.singles) {
    if (sport === Sport.football || sport === Sport.volleyball) {
      return "Один на один";
    }

    if (!RACKET_LIKE_SPORTS.has(sport) && playersNeeded > 2) {
      return "Групповая";
    }

    return "Одиночная";
  }

  if (sport === Sport.football || sport === Sport.volleyball) {
    return "Командная";
  }

  if (!RACKET_LIKE_SPORTS.has(sport) && playersNeeded > 2) {
    return "Групповая";
  }

  return "Парная";
}
