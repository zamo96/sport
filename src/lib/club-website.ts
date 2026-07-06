import { createHash } from "node:crypto";

import { normalizePhone, normalizeUrl } from "@/lib/club-sync";

const MAX_TEXT_LENGTH = 80_000;
const MAX_ANALYSIS_TEXT_LENGTH = 16_000;
const MAX_TITLE_LENGTH = 180;
const MAX_DESCRIPTION_LENGTH = 360;
const MAX_DETECTED_VALUES = 10;
const MAX_EVIDENCE_SNIPPET_LENGTH = 220;

const BOOKING_URL_HINTS = [
  "book",
  "booking",
  "bron",
  "reserve",
  "reservation",
  "raspisanie",
  "schedule",
  "zapis",
  "аренд",
  "брон",
  "запис",
  "распис",
  "корт"
];

const CLOSURE_SIGNAL_PATTERNS = [
  { signal: "временно закрыт", pattern: textPattern("временно\\s+закрыт[аоы]?") },
  { signal: "закрыт на ремонт", pattern: textPattern("закрыт[аоы]?\\s+(?:на\\s+)?(?:ремонт|реконструкц)") },
  { signal: "клуб закрыт", pattern: textPattern("(?:клуб|центр|студия|зал|площадка)\\s+(?:временно\\s+)?закрыт[ао]?") },
  { signal: "больше не работает", pattern: textPattern("больше\\s+не\\s+работает") },
  { signal: "временно не работает", pattern: textPattern("временно\\s+не\\s+работает") },
  { signal: "переехал", pattern: textPattern("(?:переехал[ао]?|мы\\s+переехали)") },
  { signal: "переезд", pattern: textPattern("переезд") },
  { signal: "новый адрес", pattern: textPattern("новый\\s+адрес") }
];

const SOCIAL_HOSTS = [
  "facebook.com",
  "fb.com",
  "instagram.com",
  "vk.com",
  "t.me",
  "telegram.me",
  "youtube.com",
  "youtu.be",
  "wa.me",
  "whatsapp.com"
];

export type ClubWebsiteEvidence = {
  value: string;
  source: "tel_link" | "visible_text" | "booking_link" | "closure_text" | "llm_text" | "llm_vision";
  confidence: number;
  snippet: string;
  displayValue?: string | null;
  label?: string | null;
  url?: string | null;
  sameHost?: boolean;
};

export type ClubWebsiteSnapshot = {
  url: string;
  contentHash: string;
  title: string | null;
  description: string | null;
  analysisText: string;
  textSample: string;
  detectedPhones: string[];
  detectedBookingUrls: string[];
  closureSignals: string[];
  phoneEvidence: ClubWebsiteEvidence[];
  bookingUrlEvidence: ClubWebsiteEvidence[];
  closureSignalEvidence: ClubWebsiteEvidence[];
};

export function extractClubWebsiteSnapshot(html: string, url: string): ClubWebsiteSnapshot {
  const text = normalizeWebsiteText(html);
  const title = truncateText(decodeHtmlEntities(matchFirst(html, /<title[^>]*>([\s\S]*?)<\/title>/i)), MAX_TITLE_LENGTH);
  const rawDescription =
    matchFirst(html, /<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["'][^>]*>/i)
    ?? matchFirst(html, /<meta[^>]+content=["']([^"']+)["'][^>]+name=["']description["'][^>]*>/i);
  const description = truncateText(
    decodeHtmlEntities(rawDescription),
    MAX_DESCRIPTION_LENGTH
  );
  const phoneEvidence = extractPhoneEvidence(html, text);
  const bookingUrlEvidence = extractBookingUrlEvidence(html, url);
  const closureSignalEvidence = extractClosureSignalEvidence(text);

  return {
    url,
    contentHash: hashWebsiteContent({
      text,
      title,
      description,
      phones: phoneEvidence.map((evidence) => evidence.value),
      bookingUrls: bookingUrlEvidence.map((evidence) => evidence.value),
      closureSignals: closureSignalEvidence.map((evidence) => evidence.value)
    }),
    title,
    description,
    analysisText: text.slice(0, MAX_ANALYSIS_TEXT_LENGTH),
    textSample: text.slice(0, 1200),
    detectedPhones: phoneEvidence.map((evidence) => evidence.value),
    detectedBookingUrls: bookingUrlEvidence.map((evidence) => evidence.value),
    closureSignals: closureSignalEvidence.map((evidence) => evidence.value),
    phoneEvidence,
    bookingUrlEvidence,
    closureSignalEvidence
  };
}

export function normalizeWebsiteText(html: string) {
  return decodeHtmlEntities(
    html
      .replace(/<!--[\s\S]*?-->/g, " ")
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<svg[\s\S]*?<\/svg>/gi, " ")
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_TEXT_LENGTH);
}

export function extractPhones(text: string) {
  return extractPhoneEvidence("", text).map((evidence) => evidence.value);
}

export function extractBookingUrls(html: string, baseUrl: string) {
  return extractBookingUrlEvidence(html, baseUrl).map((evidence) => evidence.value);
}

export function extractPhoneEvidence(html: string, text: string) {
  const evidence: ClubWebsiteEvidence[] = [];

  for (const match of html.matchAll(/<a\b[^>]*href=["']\s*tel:([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    const label = normalizeWebsiteText(match[2]);
    const phone = normalizePhone(match[1]) ?? normalizePhone(label);
    if (!phone || isPlaceholderPhone(phone)) {
      continue;
    }
    evidence.push({
      value: phone,
      displayValue: label || match[1].trim(),
      source: "tel_link",
      confidence: 0.96,
      snippet: truncateEvidenceSnippet(label || match[0])
    });
  }

  const phonePattern = /(?:\+7|8)[\s(.-]*\d{3}[\s).-]*\d{3}[\s.-]*\d{2}[\s.-]*\d{2}/g;
  for (const match of text.matchAll(phonePattern)) {
    const phone = normalizePhone(match[0]);
    if (!phone || isPlaceholderPhone(phone)) {
      continue;
    }
    evidence.push({
      value: phone,
      displayValue: match[0],
      source: "visible_text",
      confidence: 0.78,
      snippet: buildTextSnippet(text, match.index ?? 0, match[0].length)
    });
  }

  return dedupeEvidence(evidence).slice(0, MAX_DETECTED_VALUES);
}

export function extractBookingUrlEvidence(html: string, baseUrl: string) {
  const matches = Array.from(html.matchAll(/<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi));
  const evidence = matches.flatMap((match) => {
    const href = match[1];
    if (/^\s*(?:tel|mailto|javascript):/i.test(href) || href.trim().startsWith("#")) {
      return [];
    }

    const label = normalizeWebsiteText(match[2]).toLowerCase();
    const displayLabel = normalizeWebsiteText(match[2]);
    const absoluteUrl = resolveUrl(href, baseUrl);
    if (!absoluteUrl) {
      return [];
    }
    if (isSocialUrl(absoluteUrl)) {
      return [];
    }

    const haystack = `${absoluteUrl} ${label}`.toLowerCase();
    if (!BOOKING_URL_HINTS.some((hint) => haystack.includes(hint))) {
      return [];
    }

    const sameHost = isSameHost(absoluteUrl, baseUrl);
    return [{
      value: absoluteUrl,
      source: "booking_link" as const,
      confidence: scoreBookingEvidence(absoluteUrl, label, sameHost),
      snippet: truncateEvidenceSnippet(displayLabel || absoluteUrl),
      label: displayLabel || null,
      url: absoluteUrl,
      sameHost
    }];
  });

  return dedupeEvidence(evidence)
    .sort((left, right) => right.confidence - left.confidence)
    .slice(0, MAX_DETECTED_VALUES);
}

export function extractClosureSignals(text: string) {
  return extractClosureSignalEvidence(text).map((evidence) => evidence.value);
}

export function extractClosureSignalEvidence(text: string) {
  const normalized = text.toLowerCase();
  return CLOSURE_SIGNAL_PATTERNS.flatMap((signal) => {
    const match = normalized.match(signal.pattern);
    if (!match || match.index == null) {
      return [];
    }

    return [{
      value: signal.signal,
      source: "closure_text" as const,
      confidence: 0.72,
      snippet: buildTextSnippet(text, match.index, match[0].length)
    }];
  }).slice(0, MAX_DETECTED_VALUES);
}

function hashWebsiteContent(input: {
  text: string;
  title: string | null;
  description: string | null;
  phones: string[];
  bookingUrls: string[];
  closureSignals: string[];
}) {
  return createHash("sha256")
    .update(
      JSON.stringify({
        title: input.title,
        description: input.description,
        text: input.text,
        phones: input.phones,
        bookingUrls: input.bookingUrls,
        closureSignals: input.closureSignals
      })
    )
    .digest("hex");
}

function resolveUrl(value: string, baseUrl: string) {
  try {
    return normalizeUrl(new URL(value, baseUrl).toString());
  } catch {
    return null;
  }
}

function isSameHost(value: string, baseUrl: string) {
  try {
    return normalizeHost(new URL(value).hostname) === normalizeHost(new URL(baseUrl).hostname);
  } catch {
    return false;
  }
}

function isSocialUrl(value: string) {
  try {
    const host = normalizeHost(new URL(value).hostname);
    return SOCIAL_HOSTS.some((socialHost) => host === socialHost || host.endsWith(`.${socialHost}`));
  } catch {
    return false;
  }
}

function normalizeHost(value: string) {
  return value.toLowerCase().replace(/^www\./, "");
}

function scoreBookingEvidence(url: string, label: string, sameHost: boolean) {
  const haystack = `${url} ${label}`.toLowerCase();
  let confidence = sameHost ? 0.82 : 0.64;

  if (/(?:raspisanie|schedule|booking|book|брон|распис|аренд)/i.test(haystack)) {
    confidence += 0.08;
  }
  if (/(?:записаться|запис|оставить заявку)/i.test(label)) {
    confidence += 0.04;
  }

  return Math.min(confidence, 0.95);
}

function matchFirst(value: string, pattern: RegExp) {
  return value.match(pattern)?.[1]?.replace(/\s+/g, " ").trim() ?? null;
}

function truncateText(value: string | null, maxLength: number) {
  if (!value) {
    return null;
  }

  return value.length > maxLength ? value.slice(0, maxLength).trim() : value;
}

function decodeHtmlEntities(value: string | null) {
  if (!value) {
    return "";
  }

  return value
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}

function uniqueNonEmpty(values: string[]) {
  return values.reduce<string[]>((result, value) => {
    const normalized = value.trim();
    if (normalized && !result.includes(normalized)) {
      result.push(normalized);
    }
    return result;
  }, []);
}

function dedupeEvidence<T extends ClubWebsiteEvidence>(values: T[]) {
  const byValue = new Map<string, T>();
  for (const value of values) {
    const existing = byValue.get(value.value);
    if (!existing || value.confidence > existing.confidence) {
      byValue.set(value.value, value);
    }
  }
  return Array.from(byValue.values());
}

function buildTextSnippet(text: string, index: number, length: number) {
  return truncateEvidenceSnippet(text.slice(Math.max(0, index - 90), index + length + 90));
}

function truncateEvidenceSnippet(value: string) {
  const normalized = value.replace(/\s+/g, " ").trim();
  return normalized.length > MAX_EVIDENCE_SNIPPET_LENGTH
    ? `${normalized.slice(0, MAX_EVIDENCE_SNIPPET_LENGTH).trim()}...`
    : normalized;
}

function textPattern(source: string) {
  return new RegExp(`(?:^|[^\\p{L}\\p{N}_])${source}(?=$|[^\\p{L}\\p{N}_])`, "u");
}

function isPlaceholderPhone(value: string) {
  return value === "79999999999" || /^7(\d)\1{9}$/.test(value);
}
