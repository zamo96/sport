import { PlayFormat as PrismaPlayFormat, type Sport } from "@prisma/client";

import {
  getSportPlayFormatLabelRu as getSportPlayFormatLabelRuCanonical,
  type SportPlayFormatLabelOptions
} from "@/lib/sport-semantics";

export type PlayFormat = "singles" | "doubles" | "both";

export function getSportPlayFormatLabelRu(
  sport: Sport | null | undefined,
  format: PlayFormat,
  options: SportPlayFormatLabelOptions = {}
) {
  if (!sport) {
    switch (format) {
      case "singles":
        return "Одиночная";
      case "doubles":
        return "Парная";
      case "both":
      default:
        return "Любой формат";
    }
  }

  return getSportPlayFormatLabelRuCanonical(sport, format as PrismaPlayFormat, options);
}
