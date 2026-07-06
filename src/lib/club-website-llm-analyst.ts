import { normalizePhone, normalizeUrl } from "@/lib/club-sync";
import type { ClubWebsiteEvidence } from "@/lib/club-website";
import type {
  ClubWebsiteAnalystDecision,
  ClubWebsiteAnalystField,
  ClubWebsiteAnalystInput,
  ClubWebsiteAnalystReview,
  ClubWebsiteAnalystRisk
} from "@/lib/club-website-analyst";

const DEFAULT_OPENAI_MODEL = "gpt-4.1-mini";
const DEFAULT_TIMEOUT_MS = 20_000;
const DEFAULT_MAX_TEXT_CHARS = 16_000;
const MAX_DECISIONS = 8;

const ANALYST_FIELDS = [
  "name",
  "address",
  "phone",
  "workingHours",
  "bookingUrl",
  "supportedSports",
  "about",
  "closureSignals",
  "websiteContent"
] as const satisfies readonly ClubWebsiteAnalystField[];

const SPORTS = [
  "tennis",
  "padel",
  "squash",
  "badminton",
  "table_tennis",
  "football",
  "volleyball",
  "fitness",
  "boxing",
  "yoga",
  "running"
];

type LlmAnalystStatus = "disabled" | "completed" | "failed";

type LlmAnalystResult = {
  status: LlmAnalystStatus;
  provider: "openai" | null;
  model: string | null;
  review: ClubWebsiteAnalystReview | null;
  errorMessage: string | null;
  screenshotIncluded: boolean;
};

type RawLlmDecision = {
  field: string;
  action: string;
  candidateValue: string;
  confidence: number;
  risk: string;
  reason: string;
  rationale: string;
  evidenceSnippet: string;
  evidenceSource: string;
};

type RawLlmReview = {
  summary: string;
  risk: string;
  decisions: RawLlmDecision[];
};

export function isClubWebsiteLlmAnalystEnabled() {
  const mode = process.env.CLUB_SYNC_ANALYST_MODE?.trim().toLowerCase();
  return mode === "llm" || mode === "hybrid" || process.env.CLUB_SYNC_LLM_ANALYST === "1";
}

export async function analyzeClubWebsiteWithLlm(input: {
  analystInput: ClubWebsiteAnalystInput;
  screenshotDataUrl?: string | null;
}): Promise<LlmAnalystResult> {
  if (!isClubWebsiteLlmAnalystEnabled()) {
    return {
      status: "disabled",
      provider: null,
      model: null,
      review: null,
      errorMessage: null,
      screenshotIncluded: false
    };
  }

  const apiKey = process.env.OPENAI_API_KEY?.trim();
  const model = process.env.CLUB_SYNC_ANALYST_MODEL?.trim() || process.env.OPENAI_CLUB_ANALYST_MODEL?.trim() || DEFAULT_OPENAI_MODEL;
  const screenshotIncluded = Boolean(input.screenshotDataUrl);

  if (!apiKey) {
    return {
      status: "failed",
      provider: "openai",
      model,
      review: null,
      errorMessage: "OPENAI_API_KEY is required when CLUB_SYNC_ANALYST_MODE=llm|hybrid",
      screenshotIncluded
    };
  }

  try {
    const rawReview = await requestOpenAiReview({
      apiKey,
      model,
      analystInput: input.analystInput,
      screenshotDataUrl: input.screenshotDataUrl
    });
    const decisions = rawReview.decisions
      .slice(0, MAX_DECISIONS)
      .map((decision) => mapRawDecision(decision, input.analystInput, screenshotIncluded))
      .filter((decision): decision is ClubWebsiteAnalystDecision => decision !== null);

    return {
      status: "completed",
      provider: "openai",
      model,
      review: {
        provider: "openai",
        model,
        summary: truncateText(rawReview.summary || summarizeLlmDecisions(input.analystInput.court.name, decisions), 500),
        risk: normalizeRisk(rawReview.risk),
        decisions
      },
      errorMessage: null,
      screenshotIncluded
    };
  } catch (error) {
    return {
      status: "failed",
      provider: "openai",
      model,
      review: null,
      errorMessage: error instanceof Error ? error.message : String(error),
      screenshotIncluded
    };
  }
}

async function requestOpenAiReview(input: {
  apiKey: string;
  model: string;
  analystInput: ClubWebsiteAnalystInput;
  screenshotDataUrl?: string | null;
}): Promise<RawLlmReview> {
  const timeoutMs = parsePositiveInt(process.env.CLUB_SYNC_ANALYST_TIMEOUT_MS) ?? DEFAULT_TIMEOUT_MS;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${input.apiKey}`
      },
      body: JSON.stringify({
        model: input.model,
        store: false,
        input: [
          {
            role: "user",
            content: buildOpenAiContent(input.analystInput, input.screenshotDataUrl)
          }
        ],
        text: {
          format: {
            type: "json_schema",
            name: "club_website_analyst_review",
            strict: true,
            schema: CLUB_WEBSITE_ANALYST_SCHEMA
          }
        },
        max_output_tokens: 1800
      })
    });

    const body = await response.json().catch(() => null) as unknown;
    if (!response.ok) {
      throw new Error(`OpenAI analyst failed: ${response.status} ${readOpenAiError(body) ?? response.statusText}`);
    }

    const outputText = extractOpenAiOutputText(body);
    const parsed = JSON.parse(outputText) as unknown;
    return normalizeRawReview(parsed);
  } finally {
    clearTimeout(timer);
  }
}

function buildOpenAiContent(input: ClubWebsiteAnalystInput, screenshotDataUrl?: string | null) {
  const prompt = buildAnalystPrompt(input);
  const content: Array<{ type: "input_text"; text: string } | { type: "input_image"; image_url: string }> = [
    {
      type: "input_text",
      text: prompt
    }
  ];

  if (screenshotDataUrl) {
    content.push({
      type: "input_image",
      image_url: screenshotDataUrl
    });
  }

  return content;
}

function buildAnalystPrompt(input: ClubWebsiteAnalystInput) {
  const maxTextChars = parsePositiveInt(process.env.CLUB_SYNC_ANALYST_MAX_TEXT_CHARS) ?? DEFAULT_MAX_TEXT_CHARS;
  const pageText = input.snapshot.analysisText.slice(0, maxTextChars);

  return [
    "Ты аналитик качества справочника спортивных клубов Санкт-Петербурга.",
    "Твоя задача: изучить официальный сайт клуба, сравнить его с текущей карточкой и вернуть только подтвержденные изменения.",
    "Не выдумывай данные. Если на сайте нет явного подтверждения, не создавай decision.",
    "Телефоны, адреса, часы работы, виды спорта, описание и признаки закрытия всегда отправляй на review.",
    "Для каждого decision дай короткий evidenceSnippet: точную фразу со страницы или видимый текст со скриншота.",
    "Для supportedSports используй только эти значения: " + SPORTS.join(", ") + ".",
    "",
    "Текущая карточка:",
    JSON.stringify({
      name: input.court.name,
      address: input.court.address ?? null,
      phone: normalizePhone(input.court.phone),
      workingHours: input.court.workingHours ?? null,
      bookingUrl: normalizeUrl(input.court.bookingUrl),
      supportedSports: input.court.supportedSports ?? null,
      about: input.court.about ?? null
    }, null, 2),
    "",
    "Факты, уже извлеченные правилами:",
    JSON.stringify({
      title: input.snapshot.title,
      description: input.snapshot.description,
      detectedPhones: input.snapshot.detectedPhones,
      detectedBookingUrls: input.snapshot.detectedBookingUrls,
      closureSignals: input.snapshot.closureSignals,
      phoneEvidence: input.snapshot.phoneEvidence,
      bookingUrlEvidence: input.snapshot.bookingUrlEvidence,
      closureSignalEvidence: input.snapshot.closureSignalEvidence
    }, null, 2),
    "",
    "Текст сайта:",
    pageText
  ].join("\n");
}

function mapRawDecision(
  raw: RawLlmDecision,
  input: ClubWebsiteAnalystInput,
  screenshotIncluded: boolean
): ClubWebsiteAnalystDecision | null {
  const field = normalizeField(raw.field);
  if (!field) {
    return null;
  }

  const candidateValue = normalizeCandidateValue(field, raw.candidateValue);
  if (!candidateValue || valuesEqual(currentValueForField(field, input), candidateValue)) {
    return null;
  }

  const source = raw.evidenceSource === "vision" && screenshotIncluded ? "llm_vision" : "llm_text";
  const evidence: ClubWebsiteEvidence = {
    value: Array.isArray(candidateValue) ? candidateValue.join("|") : candidateValue,
    source,
    confidence: clampConfidence(raw.confidence),
    snippet: truncateText(raw.evidenceSnippet || raw.rationale || raw.reason, 220)
  };

  return {
    field,
    action: "review",
    source: "llm",
    currentValue: currentValueForField(field, input),
    candidateValue,
    confidence: clampConfidence(raw.confidence),
    risk: normalizeRisk(raw.risk),
    reason: normalizeReason(raw.reason),
    rationale: truncateText(raw.rationale, 500),
    evidence: [evidence]
  };
}

function normalizeField(value: string): ClubWebsiteAnalystField | null {
  return (ANALYST_FIELDS as readonly string[]).includes(value) ? value as ClubWebsiteAnalystField : null;
}

function normalizeCandidateValue(field: ClubWebsiteAnalystField, value: string): string | string[] | null {
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  if (field === "phone") {
    return normalizePhone(trimmed);
  }
  if (field === "bookingUrl") {
    return normalizeUrl(trimmed);
  }
  if (field === "supportedSports" || field === "closureSignals") {
    const values = splitListValue(trimmed);
    if (field === "supportedSports") {
      return values.map((item) => item.toLowerCase()).filter((item) => SPORTS.includes(item));
    }
    return values;
  }

  return truncateText(trimmed, field === "about" ? 600 : 240);
}

function currentValueForField(field: ClubWebsiteAnalystField, input: ClubWebsiteAnalystInput): string | string[] | null {
  switch (field) {
    case "name":
      return input.court.name;
    case "address":
      return input.court.address ?? null;
    case "phone":
      return normalizePhone(input.court.phone);
    case "workingHours":
      return input.court.workingHours ?? null;
    case "bookingUrl":
      return normalizeUrl(input.court.bookingUrl);
    case "supportedSports":
      return normalizeCurrentSports(input.court.supportedSports);
    case "about":
      return input.court.about ?? null;
    case "closureSignals":
    case "websiteContent":
      return null;
  }
}

function normalizeCurrentSports(value: unknown): string[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const sports = value.filter((item): item is string => typeof item === "string" && SPORTS.includes(item));
  return sports.length > 0 ? sports : null;
}

function valuesEqual(currentValue: string | string[] | null, candidateValue: string | string[]) {
  if (Array.isArray(currentValue) || Array.isArray(candidateValue)) {
    const current = Array.isArray(currentValue) ? currentValue : currentValue ? [currentValue] : [];
    const candidate = Array.isArray(candidateValue) ? candidateValue : [candidateValue];
    return current.length === candidate.length && current.every((item) => candidate.includes(item));
  }

  return normalizeComparable(currentValue) === normalizeComparable(candidateValue);
}

function normalizeComparable(value: string | null) {
  return value?.trim().toLowerCase().replace(/\s+/g, " ") ?? null;
}

function splitListValue(value: string) {
  return value
    .split(/[|,;]\s*|\n/g)
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 10);
}

function normalizeRisk(value: string): ClubWebsiteAnalystRisk {
  return value === "low" || value === "medium" || value === "high" ? value : "medium";
}

function clampConfidence(value: number) {
  if (!Number.isFinite(value)) {
    return 0.5;
  }
  return Math.min(1, Math.max(0, value));
}

function normalizeReason(value: string) {
  const reason = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 80);
  return reason ? `llm_${reason}` : "llm_detected_website_change";
}

function summarizeLlmDecisions(courtName: string, decisions: ClubWebsiteAnalystDecision[]) {
  return decisions.length === 0
    ? `${courtName}: LLM не нашел подтвержденных изменений.`
    : `${courtName}: LLM предложил ${decisions.length} изменений на проверку.`;
}

function normalizeRawReview(value: unknown): RawLlmReview {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("OpenAI analyst returned non-object JSON");
  }

  const object = value as Record<string, unknown>;
  return {
    summary: typeof object.summary === "string" ? object.summary : "",
    risk: typeof object.risk === "string" ? object.risk : "medium",
    decisions: Array.isArray(object.decisions)
      ? object.decisions
          .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object" && !Array.isArray(item))
          .map((item) => ({
            field: stringValue(item.field),
            action: stringValue(item.action),
            candidateValue: stringValue(item.candidateValue),
            confidence: numberValue(item.confidence),
            risk: stringValue(item.risk),
            reason: stringValue(item.reason),
            rationale: stringValue(item.rationale),
            evidenceSnippet: stringValue(item.evidenceSnippet),
            evidenceSource: stringValue(item.evidenceSource)
          }))
      : []
  };
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown) {
  return typeof value === "number" ? value : 0.5;
}

function extractOpenAiOutputText(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("OpenAI analyst returned an invalid response");
  }

  const object = value as Record<string, unknown>;
  if (typeof object.output_text === "string" && object.output_text.trim()) {
    return object.output_text;
  }

  const output = Array.isArray(object.output) ? object.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const contentValue = (item as Record<string, unknown>).content;
    const content: unknown[] = Array.isArray(contentValue) ? contentValue : [];
    for (const contentItem of content) {
      if (!contentItem || typeof contentItem !== "object" || Array.isArray(contentItem)) {
        continue;
      }
      const text = (contentItem as Record<string, unknown>).text;
      if (typeof text === "string" && text.trim()) {
        return text;
      }
    }
  }

  throw new Error("OpenAI analyst response did not contain output_text");
}

function readOpenAiError(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const error = (value as Record<string, unknown>).error;
  if (!error || typeof error !== "object" || Array.isArray(error)) {
    return null;
  }
  const message = (error as Record<string, unknown>).message;
  return typeof message === "string" ? message : null;
}

function parsePositiveInt(value: string | undefined) {
  if (!value) {
    return null;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function truncateText(value: string, maxLength: number) {
  return value.length > maxLength ? `${value.slice(0, maxLength).trim()}...` : value;
}

const CLUB_WEBSITE_ANALYST_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "risk", "decisions"],
  properties: {
    summary: {
      type: "string"
    },
    risk: {
      type: "string",
      enum: ["low", "medium", "high"]
    },
    decisions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "field",
          "action",
          "candidateValue",
          "confidence",
          "risk",
          "reason",
          "rationale",
          "evidenceSnippet",
          "evidenceSource"
        ],
        properties: {
          field: {
            type: "string",
            enum: ANALYST_FIELDS
          },
          action: {
            type: "string",
            enum: ["apply", "review", "ignore"]
          },
          candidateValue: {
            type: "string"
          },
          confidence: {
            type: "number"
          },
          risk: {
            type: "string",
            enum: ["low", "medium", "high"]
          },
          reason: {
            type: "string"
          },
          rationale: {
            type: "string"
          },
          evidenceSnippet: {
            type: "string"
          },
          evidenceSource: {
            type: "string",
            enum: ["text", "vision"]
          }
        }
      }
    }
  }
} as const;
