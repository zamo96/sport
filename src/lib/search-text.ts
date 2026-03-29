import type { Sport } from "@prisma/client";

import { getDistrictLabel, SPORT_LABELS } from "@/lib/constants";

const CYRILLIC_TO_LATIN: Array<[RegExp, string]> = [
  [/щ/gi, "shch"],
  [/ш/gi, "sh"],
  [/ч/gi, "ch"],
  [/ц/gi, "ts"],
  [/ю/gi, "yu"],
  [/я/gi, "ya"],
  [/ж/gi, "zh"],
  [/х/gi, "kh"],
  [/ё/gi, "yo"],
  [/й/gi, "y"],
  [/а/gi, "a"],
  [/б/gi, "b"],
  [/в/gi, "v"],
  [/г/gi, "g"],
  [/д/gi, "d"],
  [/е/gi, "e"],
  [/з/gi, "z"],
  [/и/gi, "i"],
  [/к/gi, "k"],
  [/л/gi, "l"],
  [/м/gi, "m"],
  [/н/gi, "n"],
  [/о/gi, "o"],
  [/п/gi, "p"],
  [/р/gi, "r"],
  [/с/gi, "s"],
  [/т/gi, "t"],
  [/у/gi, "u"],
  [/ф/gi, "f"],
  [/ы/gi, "y"],
  [/э/gi, "e"],
  [/ъ/gi, ""],
  [/ь/gi, ""]
];

const LATIN_TO_CYRILLIC: Array<[RegExp, string]> = [
  [/shch/gi, "щ"],
  [/sch/gi, "щ"],
  [/yo/gi, "ё"],
  [/yu/gi, "ю"],
  [/ya/gi, "я"],
  [/zh/gi, "ж"],
  [/kh/gi, "х"],
  [/ts/gi, "ц"],
  [/ch/gi, "ч"],
  [/sh/gi, "ш"],
  [/a/gi, "а"],
  [/b/gi, "б"],
  [/c/gi, "к"],
  [/d/gi, "д"],
  [/e/gi, "е"],
  [/f/gi, "ф"],
  [/g/gi, "г"],
  [/h/gi, "х"],
  [/i/gi, "и"],
  [/j/gi, "дж"],
  [/k/gi, "к"],
  [/l/gi, "л"],
  [/m/gi, "м"],
  [/n/gi, "н"],
  [/o/gi, "о"],
  [/p/gi, "п"],
  [/q/gi, "к"],
  [/r/gi, "р"],
  [/s/gi, "с"],
  [/t/gi, "т"],
  [/u/gi, "у"],
  [/v/gi, "в"],
  [/w/gi, "в"],
  [/x/gi, "кс"],
  [/y/gi, "й"],
  [/z/gi, "з"]
];

export function normalizeSearchText(value: string | null | undefined) {
  if (!value) {
    return "";
  }

  return value
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}\s-]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function transliterateRuToEn(value: string | null | undefined) {
  let result = normalizeSearchText(value);
  for (const [pattern, replacement] of CYRILLIC_TO_LATIN) {
    result = result.replace(pattern, replacement);
  }
  return result;
}

export function transliterateEnToRu(value: string | null | undefined) {
  let result = normalizeSearchText(value);
  for (const [pattern, replacement] of LATIN_TO_CYRILLIC) {
    result = result.replace(pattern, replacement);
  }
  return result;
}

export function buildCourtSearchTerms(input: {
  name: string;
  address: string;
  district?: string | null;
  nearestMetroName?: string | null;
  sports?: Sport[];
}) {
  const districtLabel = getDistrictLabel(input.district);
  const sportLabels = (input.sports ?? []).flatMap((sport) => [sport, SPORT_LABELS[sport]]);
  const rawParts = [
    input.name,
    input.address,
    input.nearestMetroName ?? "",
    input.district ?? "",
    districtLabel ?? "",
    ...sportLabels
  ].filter(Boolean);

  const raw = rawParts.join(" ");
  return Array.from(
    new Set([
      normalizeSearchText(raw),
      transliterateRuToEn(raw),
      transliterateEnToRu(raw)
    ].filter(Boolean))
  );
}

export function matchesSearchTerms(terms: string[], query: string) {
  const normalizedQuery = normalizeSearchText(query);
  if (!normalizedQuery) {
    return true;
  }

  const queryVariants = Array.from(
    new Set([
      normalizedQuery,
      transliterateRuToEn(normalizedQuery),
      transliterateEnToRu(normalizedQuery)
    ].filter(Boolean))
  );

  return queryVariants.some((variant) => terms.some((term) => term.includes(variant)));
}
