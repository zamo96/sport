import { Prisma, PrismaClient } from "@prisma/client";

import { prisma as defaultPrisma } from "@/lib/prisma";

const DEFAULT_REPORT_LIMIT = 100;

export type ClubSyncReportField = {
  field: string;
  beforeValue: unknown;
  afterValue: unknown;
  confidence: number | null;
  autoApply: boolean | null;
  reason: string | null;
  evidence: ClubSyncReportEvidence[];
};

export type ClubSyncReportEvidence = {
  source: string;
  confidence: number | null;
  snippet: string | null;
  value: unknown;
};

export type ClubSyncReportWebsiteCheck = {
  id: string;
  courtId: string;
  courtName: string;
  url: string;
  status: string;
  checkedAt: string;
  httpStatus: number | null;
  changed: boolean;
  errorMessage: string | null;
  detectedPhones: string[];
  detectedBookingUrls: string[];
  closureSignals: string[];
  analystProvider: string | null;
  analystModel: string | null;
  analystStatus: string | null;
  analystErrorMessage: string | null;
  screenshotStatus: string | null;
  screenshotErrorMessage: string | null;
};

export type ClubSyncReportChange = {
  id: string;
  courtId: string | null;
  courtName: string | null;
  action: string;
  status: string;
  confidence: number;
  reason: string;
  createdAt: string;
  appliedAt: string | null;
  proposedFields: ClubSyncReportField[];
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
};

export type ClubSyncReport = {
  run: {
    id: string;
    sourceType: string;
    city: string;
    status: string;
    startedAt: string;
    finishedAt: string | null;
    durationMs: number | null;
    errorMessage: string | null;
  };
  counters: {
    fetched: number;
    created: number;
    updated: number;
    unchanged: number;
    proposed: number;
    hidden: number;
    websiteChecked: number;
    websiteChanged: number;
    websiteFailed: number;
  };
  websiteChecks: {
    total: number;
    byStatus: Record<string, number>;
    changed: ClubSyncReportWebsiteCheck[];
    failed: ClubSyncReportWebsiteCheck[];
    analystFailed: ClubSyncReportWebsiteCheck[];
  };
  changes: {
    total: number;
    byStatus: Record<string, number>;
    applied: ClubSyncReportChange[];
    pending: ClubSyncReportChange[];
    other: ClubSyncReportChange[];
  };
  notes: string[];
};

type ClubSyncReportOptions = {
  runId?: string | null;
  sourceType?: string | null;
  city?: string | null;
  limit?: number;
  prisma?: PrismaClient;
};

export async function buildClubSyncReport(options: ClubSyncReportOptions = {}): Promise<ClubSyncReport | null> {
  const prisma = options.prisma ?? defaultPrisma;
  const limit = options.limit && options.limit > 0 ? options.limit : DEFAULT_REPORT_LIMIT;
  const run = options.runId
    ? await prisma.courtSyncRun.findUnique({ where: { id: options.runId } })
    : await prisma.courtSyncRun.findFirst({
        where: {
          ...(options.sourceType ? { sourceType: options.sourceType } : {}),
          ...(options.city ? { city: options.city } : {})
        },
        orderBy: {
          startedAt: "desc"
        }
      });

  if (!run) {
    return null;
  }

  const [websiteChecks, changes] = await Promise.all([
    prisma.courtWebsiteCheck.findMany({
      where: { runId: run.id },
      include: {
        court: {
          select: {
            name: true
          }
        }
      },
      orderBy: {
        checkedAt: "asc"
      }
    }),
    prisma.courtChangeProposal.findMany({
      where: { runId: run.id },
      include: {
        court: {
          select: {
            name: true
          }
        }
      },
      orderBy: {
        createdAt: "asc"
      }
    })
  ]);

  const mappedChecks = websiteChecks.map(mapWebsiteCheck);
  const mappedChanges = changes.map(mapChange);
  const failedChecks = mappedChecks.filter((check) => check.status === "failed");
  const analystFailedChecks = mappedChecks.filter((check) => check.analystStatus === "failed" || check.screenshotStatus === "failed");
  const changedChecks = mappedChecks.filter((check) => check.changed || check.status === "changed");
  const appliedChanges = mappedChanges.filter((change) => change.status === "applied");
  const pendingChanges = mappedChanges.filter((change) => change.status === "pending");
  const otherChanges = mappedChanges.filter((change) => change.status !== "applied" && change.status !== "pending");

  return {
    run: {
      id: run.id,
      sourceType: run.sourceType,
      city: run.city,
      status: run.status,
      startedAt: run.startedAt.toISOString(),
      finishedAt: run.finishedAt?.toISOString() ?? null,
      durationMs: run.finishedAt ? run.finishedAt.getTime() - run.startedAt.getTime() : null,
      errorMessage: run.errorMessage
    },
    counters: {
      fetched: run.fetchedCount,
      created: run.createdCount,
      updated: run.updatedCount,
      unchanged: run.unchangedCount,
      proposed: run.proposedCount,
      hidden: run.hiddenCount,
      websiteChecked: run.websiteCheckedCount,
      websiteChanged: run.websiteChangedCount,
      websiteFailed: run.websiteFailedCount
    },
    websiteChecks: {
      total: mappedChecks.length,
      byStatus: countBy(mappedChecks.map((check) => check.status)),
      changed: changedChecks.slice(0, limit),
      failed: failedChecks.slice(0, limit),
      analystFailed: analystFailedChecks.slice(0, limit)
    },
    changes: {
      total: mappedChanges.length,
      byStatus: countBy(mappedChanges.map((change) => change.status)),
      applied: appliedChanges.slice(0, limit),
      pending: pendingChanges.slice(0, limit),
      other: otherChanges.slice(0, limit)
    },
    notes: buildReportNotes({
      failedChecksCount: failedChecks.length,
      analystFailedChecksCount: analystFailedChecks.length,
      pendingChangesCount: pendingChanges.length,
      appliedChangesCount: appliedChanges.length,
      errorMessage: run.errorMessage
    })
  };
}

export function formatClubSyncReportMarkdown(report: ClubSyncReport) {
  const lines = [
    "# Club Sync Report",
    "",
    `Run: \`${report.run.id}\``,
    `Source: \`${report.run.sourceType}\``,
    `City: ${report.run.city}`,
    `Status: ${report.run.status}`,
    `Started: ${report.run.startedAt}`,
    `Finished: ${report.run.finishedAt ?? "-"}`,
    "",
    "## Counters",
    "",
    `- Fetched: ${report.counters.fetched}`,
    `- Created: ${report.counters.created}`,
    `- Updated: ${report.counters.updated}`,
    `- Unchanged: ${report.counters.unchanged}`,
    `- Proposed: ${report.counters.proposed}`,
    `- Hidden: ${report.counters.hidden}`,
    `- Websites checked: ${report.counters.websiteChecked}`,
    `- Websites changed: ${report.counters.websiteChanged}`,
    `- Websites failed: ${report.counters.websiteFailed}`,
    "",
    "## Website Statuses",
    ""
  ];

  for (const [status, count] of Object.entries(report.websiteChecks.byStatus)) {
    lines.push(`- ${status}: ${count}`);
  }

  appendChangeSection(lines, "Applied Changes", report.changes.applied);
  appendChangeSection(lines, "Pending Review", report.changes.pending);
  appendWebsiteSection(lines, "Changed Websites", report.websiteChecks.changed);
  appendWebsiteSection(lines, "Failed Websites", report.websiteChecks.failed);
  appendWebsiteSection(lines, "Analyst Errors", report.websiteChecks.analystFailed);

  if (report.notes.length > 0) {
    lines.push("", "## Notes", "");
    for (const note of report.notes) {
      lines.push(`- ${note}`);
    }
  }

  return `${lines.join("\n")}\n`;
}

function mapWebsiteCheck(check: {
  id: string;
  courtId: string;
  court: { name: string };
  url: string;
  status: string;
  checkedAt: Date;
  httpStatus: number | null;
  changed: boolean;
  errorMessage: string | null;
  detectedPhones: Prisma.JsonValue | null;
  detectedBookingUrls: Prisma.JsonValue | null;
  closureSignals: Prisma.JsonValue | null;
  analystProvider: string | null;
  analystModel: string | null;
  analystStatus: string | null;
  analystErrorMessage: string | null;
  screenshotStatus: string | null;
  screenshotErrorMessage: string | null;
}): ClubSyncReportWebsiteCheck {
  return {
    id: check.id,
    courtId: check.courtId,
    courtName: check.court.name,
    url: check.url,
    status: check.status,
    checkedAt: check.checkedAt.toISOString(),
    httpStatus: check.httpStatus,
    changed: check.changed,
    errorMessage: check.errorMessage,
    detectedPhones: jsonStringArray(check.detectedPhones),
    detectedBookingUrls: jsonStringArray(check.detectedBookingUrls),
    closureSignals: jsonStringArray(check.closureSignals),
    analystProvider: check.analystProvider,
    analystModel: check.analystModel,
    analystStatus: check.analystStatus,
    analystErrorMessage: check.analystErrorMessage,
    screenshotStatus: check.screenshotStatus,
    screenshotErrorMessage: check.screenshotErrorMessage
  };
}

function mapChange(change: {
  id: string;
  courtId: string | null;
  court: { name: string } | null;
  action: string;
  status: string;
  confidence: number;
  reason: string;
  createdAt: Date;
  appliedAt: Date | null;
  before: Prisma.JsonValue | null;
  after: Prisma.JsonValue;
}): ClubSyncReportChange {
  const before = summarizePayload(change.before);
  const after = summarizePayload(change.after);

  return {
    id: change.id,
    courtId: change.courtId,
    courtName: change.court?.name ?? null,
    action: change.action,
    status: change.status,
    confidence: change.confidence,
    reason: change.reason,
    createdAt: change.createdAt.toISOString(),
    appliedAt: change.appliedAt?.toISOString() ?? null,
    proposedFields: extractProposedFields(change.after, before),
    before,
    after
  };
}

function appendChangeSection(lines: string[], title: string, changes: ClubSyncReportChange[]) {
  lines.push("", `## ${title}`, "");

  if (changes.length === 0) {
    lines.push("- none");
    return;
  }

  for (const change of changes) {
    const fieldText = formatFields(change.proposedFields);
    const evidenceText = formatEvidence(change.proposedFields);
    lines.push(
      `- ${change.courtName ?? "Unknown court"}: ${change.action}, ${change.reason}${fieldText ? `; ${fieldText}` : ""}`
    );
    if (evidenceText) {
      lines.push(`  evidence: ${evidenceText}`);
    }
  }
}

function appendWebsiteSection(lines: string[], title: string, checks: ClubSyncReportWebsiteCheck[]) {
  lines.push("", `## ${title}`, "");

  if (checks.length === 0) {
    lines.push("- none");
    return;
  }

  for (const check of checks) {
    const errorText = check.errorMessage ? ` - ${check.errorMessage}` : "";
    const analystText = formatAnalystCheckStatus(check);
    lines.push(`- ${check.courtName}: ${check.status} ${check.url}${errorText}${analystText}`);
  }
}

function formatAnalystCheckStatus(check: ClubSyncReportWebsiteCheck) {
  const parts = [
    check.analystStatus && check.analystStatus !== "disabled"
      ? `analyst=${check.analystStatus}${check.analystModel ? `/${check.analystModel}` : ""}`
      : null,
    check.analystErrorMessage ? `analystError=${check.analystErrorMessage}` : null,
    check.screenshotStatus && check.screenshotStatus !== "disabled" ? `screenshot=${check.screenshotStatus}` : null,
    check.screenshotErrorMessage ? `screenshotError=${check.screenshotErrorMessage}` : null
  ].filter((part): part is string => Boolean(part));

  return parts.length > 0 ? ` (${parts.join("; ")})` : "";
}

function formatFields(fields: ClubSyncReportField[]) {
  return fields
    .map((field) => {
      const reviewMode = field.autoApply ? "auto" : "review";
      const confidence = typeof field.confidence === "number" ? `, confidence ${field.confidence.toFixed(2)}` : "";
      const reason = field.reason ? `, ${field.reason}` : "";
      return `${field.field}: ${formatFieldValue(field.field, field.beforeValue)} -> ${formatFieldValue(field.field, field.afterValue)} (${reviewMode}${confidence}${reason})`;
    })
    .join(", ");
}

function formatEvidence(fields: ClubSyncReportField[]) {
  return fields
    .flatMap((field) =>
      field.evidence.slice(0, 2).map((evidence) => {
        const confidence = typeof evidence.confidence === "number" ? ` ${evidence.confidence.toFixed(2)}` : "";
        const snippet = evidence.snippet ? ` "${evidence.snippet}"` : "";
        return `${field.field}/${evidence.source}${confidence}${snippet}`;
      })
    )
    .join("; ");
}

function formatFieldValue(field: string, value: unknown) {
  if (Array.isArray(value)) {
    return value.join("|");
  }
  if (value == null) {
    return "(empty)";
  }
  if (field === "phone" && typeof value === "string") {
    return formatPhoneForReport(value);
  }
  return String(value);
}

function extractProposedFields(value: Prisma.JsonValue, before: Record<string, unknown> | null): ClubSyncReportField[] {
  const proposedFields = jsonObject(value)?.proposedFields;
  if (!Array.isArray(proposedFields)) {
    return [];
  }

  return proposedFields
    .filter((field): field is Record<string, unknown> => Boolean(field) && typeof field === "object" && !Array.isArray(field))
    .map((field) => {
      const fieldName = typeof field.field === "string" ? field.field : "unknown";
      return {
        field: fieldName,
        beforeValue: before?.[fieldName] ?? null,
        afterValue: field.value,
        confidence: typeof field.confidence === "number" ? field.confidence : null,
        autoApply: typeof field.autoApply === "boolean" ? field.autoApply : null,
        reason: typeof field.reason === "string" ? field.reason : null,
        evidence: normalizeEvidence(field.evidence)
      };
    });
}

function summarizePayload(value: Prisma.JsonValue | null) {
  const object = jsonObject(value);
  if (!object) {
    return null;
  }

  const keys = [
    "id",
    "name",
    "address",
    "city",
    "status",
    "phone",
    "websiteUrl",
    "bookingUrl",
    "title",
    "description",
    "changed",
    "detectedPhones",
    "detectedBookingUrls",
    "closureSignals",
    "analystRun",
    "proposedFields"
  ];
  return Object.fromEntries(
    keys
      .filter((key) => key in object)
      .map((key) => [key, truncateReportValue(object[key])])
  );
}

function truncateReportValue(value: unknown): unknown {
  if (typeof value === "string" && value.length > 360) {
    return `${value.slice(0, 360).trim()}...`;
  }
  if (Array.isArray(value)) {
    return value.slice(0, 10).map(truncateReportValue);
  }
  return value;
}

function jsonObject(value: Prisma.JsonValue | null): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function jsonStringArray(value: Prisma.JsonValue | null) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function normalizeEvidence(value: unknown): ClubSyncReportEvidence[] {
  const values = Array.isArray(value) ? value : value && typeof value === "object" ? [value] : [];
  return values
    .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object" && !Array.isArray(item))
    .map((item) => ({
      source: typeof item.source === "string" ? item.source : "unknown",
      confidence: typeof item.confidence === "number" ? item.confidence : null,
      snippet: typeof item.snippet === "string" ? item.snippet : null,
      value: item.value
    }));
}

function countBy(values: string[]) {
  return values.reduce<Record<string, number>>((result, value) => {
    result[value] = (result[value] ?? 0) + 1;
    return result;
  }, {});
}

function buildReportNotes(input: {
  failedChecksCount: number;
  analystFailedChecksCount: number;
  pendingChangesCount: number;
  appliedChangesCount: number;
  errorMessage: string | null;
}) {
  const notes: string[] = [];

  if (input.errorMessage) {
    notes.push(`Run error: ${input.errorMessage}`);
  }
  if (input.failedChecksCount > 0) {
    notes.push(`${input.failedChecksCount} website checks failed and need source cleanup or retry.`);
  }
  if (input.analystFailedChecksCount > 0) {
    notes.push(`${input.analystFailedChecksCount} analyst checks failed; website fetch may still be valid.`);
  }
  if (input.pendingChangesCount > 0) {
    notes.push(`${input.pendingChangesCount} changes are waiting for manual review.`);
  }
  if (input.appliedChangesCount > 0) {
    notes.push(`${input.appliedChangesCount} changes were applied automatically.`);
  }

  return notes;
}

function formatPhoneForReport(value: string) {
  const digits = value.replace(/\D/g, "");
  const normalized = digits.length === 11 && digits.startsWith("8") ? `7${digits.slice(1)}` : digits;
  if (normalized.length !== 11 || !normalized.startsWith("7")) {
    return value;
  }

  return `+7 (${normalized.slice(1, 4)}) ${normalized.slice(4, 7)}-${normalized.slice(7, 9)}-${normalized.slice(9)}`;
}
