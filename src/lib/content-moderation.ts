const OBJECTIONABLE_TEXT_MESSAGE = "Текст содержит недопустимые выражения. Измени его и попробуй снова";

const BLOCKED_TOKENS = new Set([
  "хуй",
  "хуя",
  "хуем",
  "хуём",
  "пизда",
  "пиздец",
  "ебать",
  "еблан",
  "долбоеб",
  "долбоёб",
  "fuck",
  "fucking",
  "cunt",
  "nigger",
  "faggot"
]);

const THREAT_PATTERNS = [
  /(?:^|[^\p{L}])убью\s+(тебя|вас)(?:$|[^\p{L}])/u,
  /(?:^|[^\p{L}])зарежу\s+(тебя|вас)(?:$|[^\p{L}])/u,
  /\bkill\s+(you|them)\b/u
];

function normalizedTokens(text: string) {
  return text
    .normalize("NFKC")
    .toLocaleLowerCase("ru-RU")
    .replace(/[0@]/g, (value) => (value === "0" ? "о" : "а"))
    .split(/[^\p{L}\p{N}ё]+/u)
    .filter(Boolean);
}

export function objectionableTextReason(text: string | null | undefined) {
  if (!text?.trim()) {
    return null;
  }

  const normalized = text.normalize("NFKC").toLocaleLowerCase("ru-RU");
  if (THREAT_PATTERNS.some((pattern) => pattern.test(normalized))) {
    return "credible_threat" as const;
  }

  if (normalizedTokens(text).some((token) => BLOCKED_TOKENS.has(token))) {
    return "objectionable_language" as const;
  }

  return null;
}

export function isPublicTextAllowed(text: string | null | undefined) {
  return objectionableTextReason(text) === null;
}

export const CONTENT_MODERATION_VALIDATION_MESSAGE = OBJECTIONABLE_TEXT_MESSAGE;
