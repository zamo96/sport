import { normalizePhone, normalizeUrl } from "@/lib/club-sync";
import type { ClubWebsiteEvidence, ClubWebsiteSnapshot } from "@/lib/club-website";

export type ClubWebsiteAnalystAction = "apply" | "review" | "ignore";
export type ClubWebsiteAnalystField =
  | "name"
  | "address"
  | "phone"
  | "workingHours"
  | "bookingUrl"
  | "supportedSports"
  | "about"
  | "closureSignals"
  | "websiteContent";
export type ClubWebsiteAnalystRisk = "low" | "medium" | "high";
export type ClubWebsiteAnalystProvider = "rules" | "openai" | "rules+openai";

export type ClubWebsiteAnalystDecision = {
  field: ClubWebsiteAnalystField;
  action: ClubWebsiteAnalystAction;
  source?: "rules" | "llm";
  currentValue: string | string[] | null;
  candidateValue: string | string[] | null;
  confidence: number;
  risk: ClubWebsiteAnalystRisk;
  reason: string;
  rationale: string;
  evidence: ClubWebsiteEvidence[];
};

export type ClubWebsiteAnalystReview = {
  provider: ClubWebsiteAnalystProvider;
  model?: string | null;
  summary: string;
  risk: ClubWebsiteAnalystRisk;
  decisions: ClubWebsiteAnalystDecision[];
  errorMessage?: string | null;
};

export type ClubWebsiteAnalystInput = {
  court: {
    name: string;
    address?: string | null;
    phone: string | null;
    workingHours?: string | null;
    bookingUrl: string | null;
    supportedSports?: unknown;
    about?: string | null;
  };
  snapshot: ClubWebsiteSnapshot;
  changed: boolean;
};

export function analyzeClubWebsite(input: ClubWebsiteAnalystInput): ClubWebsiteAnalystReview {
  const decisions = [
    analyzePhone(input),
    analyzeBookingUrl(input),
    analyzeClosureSignals(input),
    analyzeWebsiteContent(input)
  ].filter((decision): decision is ClubWebsiteAnalystDecision => decision !== null && decision.action !== "ignore");

  return {
    provider: "rules",
    summary: summarizeDecisions(input.court.name, decisions),
    risk: resolveReviewRisk(decisions),
    decisions
  };
}

function analyzePhone(input: ClubWebsiteAnalystInput): ClubWebsiteAnalystDecision | null {
  const candidate = input.snapshot.phoneEvidence[0] ?? null;
  const candidatePhone = candidate?.value ?? null;
  const currentPhone = normalizePhone(input.court.phone);

  if (!candidatePhone || candidatePhone === currentPhone) {
    return null;
  }

  const hasMultiplePhones = input.snapshot.phoneEvidence.length > 1;
  return {
    field: "phone",
    action: "review",
    source: "rules",
    currentValue: currentPhone,
    candidateValue: candidatePhone,
    confidence: candidate.confidence,
    risk: hasMultiplePhones ? "high" : "medium",
    reason: hasMultiplePhones ? "phone_changed_multiple_candidates" : "phone_changed_needs_review",
    rationale: hasMultiplePhones
      ? "Сайт содержит несколько телефонных кандидатов; нужен ручной выбор основного контакта клуба."
      : "Телефон найден на сайте, но телефонные изменения не применяются автоматически.",
    evidence: input.snapshot.phoneEvidence
  };
}

function analyzeBookingUrl(input: ClubWebsiteAnalystInput): ClubWebsiteAnalystDecision | null {
  const candidate = input.snapshot.bookingUrlEvidence[0] ?? null;
  const candidateUrl = candidate?.value ?? null;
  const currentBookingUrl = normalizeUrl(input.court.bookingUrl);

  if (!candidateUrl || candidateUrl === currentBookingUrl) {
    return null;
  }

  const canApply = candidate.confidence >= 0.86 && candidate.sameHost === true;
  return {
    field: "bookingUrl",
    action: canApply ? "apply" : "review",
    source: "rules",
    currentValue: currentBookingUrl,
    candidateValue: candidateUrl,
    confidence: candidate.confidence,
    risk: canApply ? "low" : "medium",
    reason: canApply ? "same_host_booking_link" : "booking_link_needs_review",
    rationale: canApply
      ? "Ссылка бронирования найдена на том же домене и имеет явный booking/расписание-контекст."
      : "Ссылка бронирования найдена, но домен или контекст требуют ручной проверки.",
    evidence: [candidate]
  };
}

function analyzeClosureSignals(input: ClubWebsiteAnalystInput): ClubWebsiteAnalystDecision | null {
  if (input.snapshot.closureSignalEvidence.length === 0) {
    return null;
  }

  return {
    field: "closureSignals",
    action: "review",
    source: "rules",
    currentValue: null,
    candidateValue: input.snapshot.closureSignalEvidence.map((evidence) => evidence.value),
    confidence: Math.max(...input.snapshot.closureSignalEvidence.map((evidence) => evidence.confidence)),
    risk: "high",
    reason: "closure_or_relocation_signal_needs_review",
    rationale: "На сайте найден сигнал закрытия, переезда или нерабочего состояния; такие изменения нельзя применять автоматически.",
    evidence: input.snapshot.closureSignalEvidence
  };
}

function analyzeWebsiteContent(input: ClubWebsiteAnalystInput): ClubWebsiteAnalystDecision | null {
  if (!input.changed || process.env.CLUB_SYNC_PROPOSE_ANY_WEBSITE_CHANGE !== "1") {
    return null;
  }

  return {
    field: "websiteContent",
    action: "review",
    source: "rules",
    currentValue: null,
    candidateValue: input.snapshot.contentHash,
    confidence: 0.5,
    risk: "medium",
    reason: "website_snapshot_changed",
    rationale: "Контент сайта изменился, но агент не выделил конкретное поле для обновления.",
    evidence: []
  };
}

function summarizeDecisions(courtName: string, decisions: ClubWebsiteAnalystDecision[]) {
  if (decisions.length === 0) {
    return `${courtName}: изменений для обновления не найдено.`;
  }

  const applyCount = decisions.filter((decision) => decision.action === "apply").length;
  const reviewCount = decisions.filter((decision) => decision.action === "review").length;
  return `${courtName}: apply=${applyCount}, review=${reviewCount}.`;
}

function resolveReviewRisk(decisions: ClubWebsiteAnalystDecision[]): ClubWebsiteAnalystRisk {
  if (decisions.some((decision) => decision.risk === "high")) {
    return "high";
  }
  if (decisions.some((decision) => decision.risk === "medium")) {
    return "medium";
  }
  return "low";
}

export function mergeClubWebsiteAnalystReviews(
  rulesReview: ClubWebsiteAnalystReview,
  llmReview: ClubWebsiteAnalystReview | null
): ClubWebsiteAnalystReview {
  if (!llmReview) {
    return rulesReview;
  }

  const decisions = dedupeDecisions([
    ...rulesReview.decisions,
    ...llmReview.decisions.map(sanitizeLlmDecision)
  ]);

  return {
    provider: "rules+openai",
    model: llmReview.model ?? null,
    summary: `${rulesReview.summary} LLM: ${llmReview.summary}`,
    risk: resolveReviewRisk(decisions),
    decisions,
    errorMessage: llmReview.errorMessage ?? null
  };
}

function sanitizeLlmDecision(decision: ClubWebsiteAnalystDecision): ClubWebsiteAnalystDecision {
  return {
    ...decision,
    source: "llm",
    action: "review"
  };
}

function dedupeDecisions(decisions: ClubWebsiteAnalystDecision[]) {
  const seen = new Set<string>();
  const result: ClubWebsiteAnalystDecision[] = [];

  for (const decision of decisions) {
    const key = JSON.stringify({
      field: decision.field,
      candidateValue: decision.candidateValue
    });
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(decision);
  }

  return result;
}
