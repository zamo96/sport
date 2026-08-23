import { readFile } from "node:fs/promises";

import { CourtSetting, CourtStatus, Prisma, PrismaClient, Surface } from "@prisma/client";

import { DEFAULT_CITY } from "@/lib/constants";
import {
  type ClubCourtMatchCandidate,
  type ClubSyncSourceRecord,
  type NormalizedClubSyncRecord,
  normalizeClubSports,
  normalizeClubSyncRecord,
  normalizePhone,
  normalizeUrl,
  scoreClubCourtMatch
} from "@/lib/club-sync";
import { type ClubWebsiteSnapshot, extractClubWebsiteSnapshot } from "@/lib/club-website";
import {
  analyzeClubWebsite,
  mergeClubWebsiteAnalystReviews,
  type ClubWebsiteAnalystField,
  type ClubWebsiteAnalystInput,
  type ClubWebsiteAnalystReview
} from "@/lib/club-website-analyst";
import {
  analyzeClubWebsiteWithLlm,
  isClubWebsiteLlmAnalystEnabled
} from "@/lib/club-website-llm-analyst";
import { captureClubWebsiteScreenshotDataUrl, type ClubWebsiteScreenshotResult } from "@/lib/club-website-screenshot";
import { haversineDistanceKm } from "@/lib/geo";
import { prisma as defaultPrisma } from "@/lib/prisma";

const DEFAULT_SOURCE_TYPE = "yandex-places";
const DEFAULT_YANDEX_RESULTS_PER_QUERY = 50;
const DEFAULT_MATCH_THRESHOLD = 0.78;
const DEFAULT_WEBSITE_LIMIT = 100;
const DEFAULT_WEBSITE_TIMEOUT_MS = 10_000;
const DEFAULT_NEW_COURT_STATUS = CourtStatus.needs_review;
const DEFAULT_YANDEX_QUERIES = [
  "теннисный клуб",
  "теннисные корты",
  "падел клуб",
  "сквош клуб",
  "бадминтон клуб",
  "настольный теннис клуб",
  "футбольный манеж",
  "волейбольный клуб"
];

type ClubSyncProvider = "yandex" | "json";

type ClubSyncOptions = {
  city?: string;
  provider?: ClubSyncProvider;
  sourceType?: string;
  records?: ClubSyncSourceRecord[];
  autoPublishNew?: boolean;
  autoHideStale?: boolean;
  staleAfterDays?: number;
  matchThreshold?: number;
  checkWebsites?: boolean;
  websitesOnly?: boolean;
  websiteLimit?: number;
  autoApplyWebsiteChanges?: boolean;
  prisma?: PrismaClient;
};

type CourtForSync = ClubCourtMatchCandidate & {
  status: CourtStatus;
  district: string | null;
  nearestMetroId: string | null;
  supportedSports: Prisma.JsonValue | null;
  workingHours: string | null;
  yandexMapsUrl: string | null;
  bookingUrl: string | null;
  about: string | null;
  amenities: Prisma.JsonValue | null;
  messengerType: string | null;
  messengerUrl: string | null;
  photoUrl: string | null;
  photoUrls: Prisma.JsonValue | null;
  rating: number | null;
  sourceUrl: string | null;
  syncHash: string | null;
  lastSeenAt: Date | null;
  manualOverrideFields: Prisma.JsonValue | null;
  manualStatusOverride: boolean;
  updatedAt: Date;
};

type WebsiteProposedField = {
  field: ClubWebsiteAnalystField;
  value: string | string[];
  confidence: number;
  autoApply: boolean;
  reason: string;
  evidence?: Prisma.InputJsonValue;
};

export type ClubSyncSummary = {
  runId: string;
  sourceType: string;
  city: string;
  fetchedCount: number;
  createdCount: number;
  updatedCount: number;
  unchangedCount: number;
  proposedCount: number;
  hiddenCount: number;
  websiteCheckedCount: number;
  websiteChangedCount: number;
  websiteFailedCount: number;
};

export async function runClubSync(options: ClubSyncOptions = {}): Promise<ClubSyncSummary> {
  const city = options.city?.trim() || process.env.CLUB_SYNC_CITY?.trim() || DEFAULT_CITY;
  const provider = options.provider ?? resolveProvider();
  const sourceType = options.sourceType?.trim() || process.env.CLUB_SYNC_SOURCE_TYPE?.trim() || DEFAULT_SOURCE_TYPE;
  const checkWebsites = options.checkWebsites ?? process.env.CLUB_SYNC_CHECK_WEBSITES !== "0";

  if (options.websitesOnly || process.env.CLUB_SYNC_WEBSITES_ONLY === "1") {
    return runClubWebsiteChecks({
      ...options,
      city,
      sourceType: "club-website"
    });
  }

  const records = options.records ?? (await fetchClubSyncRecords({ provider, city, sourceType }));

  return syncClubRecords(records, {
    ...options,
    city,
    sourceType,
    checkWebsites
  });
}

export async function runClubWebsiteChecks(options: ClubSyncOptions = {}): Promise<ClubSyncSummary> {
  const prisma = options.prisma ?? defaultPrisma;
  const city = options.city?.trim() || process.env.CLUB_SYNC_CITY?.trim() || DEFAULT_CITY;
  const sourceType = options.sourceType?.trim() || "club-website";
  const run = await prisma.courtSyncRun.create({
    data: {
      sourceType,
      city,
      status: "running",
      metadata: {
        provider: "website"
      }
    }
  });

  const summary = emptySummary(run.id, sourceType, city);

  try {
    const websiteSummary = await runWebsiteChecksForRun(prisma, run.id, {
      city,
      limit: options.websiteLimit,
      autoApplyWebsiteChanges: options.autoApplyWebsiteChanges
    });
    summary.websiteCheckedCount = websiteSummary.checkedCount;
    summary.websiteChangedCount = websiteSummary.changedCount;
    summary.websiteFailedCount = websiteSummary.failedCount;
    summary.proposedCount = websiteSummary.proposedCount;

    await updateRunCompletion(prisma, run.id, summary);
    return summary;
  } catch (error) {
    await markRunFailed(prisma, run.id, error);
    throw error;
  }
}

export async function syncClubRecords(records: ClubSyncSourceRecord[], options: ClubSyncOptions = {}): Promise<ClubSyncSummary> {
  const prisma = options.prisma ?? defaultPrisma;
  const city = options.city?.trim() || DEFAULT_CITY;
  const sourceType = options.sourceType?.trim() || DEFAULT_SOURCE_TYPE;
  const matchThreshold = options.matchThreshold ?? DEFAULT_MATCH_THRESHOLD;
  const autoPublishNew = options.autoPublishNew ?? process.env.CLUB_SYNC_AUTO_PUBLISH_NEW === "1";
  const autoHideStale = options.autoHideStale ?? process.env.CLUB_SYNC_AUTO_HIDE_STALE === "1";
  const staleAfterDays = options.staleAfterDays ?? parseOptionalPositiveInt(process.env.CLUB_SYNC_STALE_AFTER_DAYS);
  const startedAt = new Date();

  const normalized = records
    .map((record) => normalizeClubSyncRecord({ ...record, sourceType: record.sourceType || sourceType }, city))
    .filter((record): record is NormalizedClubSyncRecord => record !== null);

  const run = await prisma.courtSyncRun.create({
    data: {
      sourceType,
      city,
      status: "running",
      fetchedCount: normalized.length,
      metadata: {
        rawCount: records.length,
        provider: options.provider ?? null
      }
    }
  });

  const summary: ClubSyncSummary = {
    ...emptySummary(run.id, sourceType, city),
    fetchedCount: normalized.length
  };

  try {
    const metroByName = await ensureMetroMap(prisma, normalized, city);
    const courts = await loadCourtsForSync(prisma, city, normalized);
    const seenCourtIds = new Set<string>();

    for (const record of dedupeRecords(normalized)) {
      const match = findBestCourtMatch(courts, record, matchThreshold);

      if (!match) {
        const created = await createSyncedCourt(prisma, record, metroByName, {
          status: autoPublishNew ? CourtStatus.active : DEFAULT_NEW_COURT_STATUS,
          now: startedAt
        });
        await syncCourtMetroLinks(prisma, created.id, record.metroNames, metroByName);
        courts.push(toCourtForSync(created));
        seenCourtIds.add(created.id);
        summary.createdCount += 1;

        await prisma.courtChangeProposal.create({
          data: {
            runId: run.id,
            courtId: created.id,
            sourceType: record.sourceType,
            sourceExternalId: record.sourceExternalId,
            action: "create",
            status: autoPublishNew ? "applied" : "pending",
            appliedAt: autoPublishNew ? startedAt : null,
            confidence: 1,
            reason: autoPublishNew ? "auto_published_new_source_record" : "new_source_record_needs_review",
            after: proposalAfter(record)
          }
        });

        if (!autoPublishNew) {
          summary.proposedCount += 1;
        }

        continue;
      }

      seenCourtIds.add(match.court.id);
      const result = await updateSyncedCourt(prisma, match.court, record, metroByName, {
        now: startedAt,
        runId: run.id,
        confidence: match.confidence,
        reason: match.reason
      });

      if (result.proposed) {
        summary.proposedCount += 1;
      }

      if (result.updated) {
        summary.updatedCount += 1;
        replaceCourtForSync(courts, result.court);
      } else {
        summary.unchangedCount += 1;
      }
    }

    if (staleAfterDays && staleAfterDays > 0) {
      const staleResult = await handleStaleCourts(prisma, {
        runId: run.id,
        sourceType,
        city,
        seenCourtIds,
        staleAfterDays,
        autoHideStale,
        now: startedAt
      });
      summary.hiddenCount += staleResult.hiddenCount;
      summary.proposedCount += staleResult.proposedCount;
    }

    if (options.checkWebsites) {
      const websiteSummary = await runWebsiteChecksForRun(prisma, run.id, {
        city,
        limit: options.websiteLimit,
        autoApplyWebsiteChanges: options.autoApplyWebsiteChanges
      });
      summary.websiteCheckedCount = websiteSummary.checkedCount;
      summary.websiteChangedCount = websiteSummary.changedCount;
      summary.websiteFailedCount = websiteSummary.failedCount;
      summary.proposedCount += websiteSummary.proposedCount;
    }

    await updateRunCompletion(prisma, run.id, summary);

    return summary;
  } catch (error) {
    await markRunFailed(prisma, run.id, error);
    throw error;
  }
}

function emptySummary(runId: string, sourceType: string, city: string): ClubSyncSummary {
  return {
    runId,
    sourceType,
    city,
    fetchedCount: 0,
    createdCount: 0,
    updatedCount: 0,
    unchangedCount: 0,
    proposedCount: 0,
    hiddenCount: 0,
    websiteCheckedCount: 0,
    websiteChangedCount: 0,
    websiteFailedCount: 0
  };
}

async function updateRunCompletion(prisma: PrismaClient, runId: string, summary: ClubSyncSummary) {
  await prisma.courtSyncRun.update({
    where: { id: runId },
    data: {
      status: "completed",
      finishedAt: new Date(),
      fetchedCount: summary.fetchedCount,
      createdCount: summary.createdCount,
      updatedCount: summary.updatedCount,
      unchangedCount: summary.unchangedCount,
      proposedCount: summary.proposedCount,
      hiddenCount: summary.hiddenCount,
      websiteCheckedCount: summary.websiteCheckedCount,
      websiteChangedCount: summary.websiteChangedCount,
      websiteFailedCount: summary.websiteFailedCount
    }
  });
}

async function markRunFailed(prisma: PrismaClient, runId: string, error: unknown) {
  await prisma.courtSyncRun.update({
    where: { id: runId },
    data: {
      status: "failed",
      finishedAt: new Date(),
      errorMessage: error instanceof Error ? error.message : String(error)
    }
  });
}

async function fetchClubSyncRecords(options: { provider: ClubSyncProvider; city: string; sourceType: string }) {
  switch (options.provider) {
    case "json":
      return fetchJsonRecords(options.sourceType);
    case "yandex":
      return fetchYandexPlacesRecords(options);
    default:
      return [];
  }
}

async function fetchJsonRecords(sourceType: string): Promise<ClubSyncSourceRecord[]> {
  const jsonFile = process.env.CLUB_SYNC_JSON_FILE?.trim();
  const jsonUrl = process.env.CLUB_SYNC_JSON_URL?.trim();
  let parsed: unknown;

  if (jsonFile) {
    parsed = JSON.parse(await readFile(jsonFile, "utf8"));
  } else if (jsonUrl) {
    const response = await fetch(jsonUrl);
    if (!response.ok) {
      throw new Error(`JSON source failed: ${response.status} ${response.statusText}`);
    }
    parsed = await response.json();
  } else {
    throw new Error("Set CLUB_SYNC_JSON_FILE or CLUB_SYNC_JSON_URL for CLUB_SYNC_PROVIDER=json");
  }

  const rows = Array.isArray(parsed) ? parsed : Array.isArray((parsed as { clubs?: unknown }).clubs) ? (parsed as { clubs: unknown[] }).clubs : [];
  return rows
    .filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === "object" && !Array.isArray(row))
    .map((row) => ({
      ...row,
      sourceType: typeof row.sourceType === "string" ? row.sourceType : sourceType
    }));
}

async function fetchYandexPlacesRecords(options: { city: string; sourceType: string }): Promise<ClubSyncSourceRecord[]> {
  const apiKey = process.env.YANDEX_PLACES_API_KEY?.trim() || process.env.NEXT_PUBLIC_YANDEX_MAPS_API_KEY?.trim();
  if (!apiKey) {
    throw new Error("Set YANDEX_PLACES_API_KEY for club sync");
  }

  const queries = parseList(process.env.CLUB_SYNC_YANDEX_QUERIES).length > 0
    ? parseList(process.env.CLUB_SYNC_YANDEX_QUERIES)
    : DEFAULT_YANDEX_QUERIES;
  const resultsPerQuery = parseOptionalPositiveInt(process.env.CLUB_SYNC_YANDEX_RESULTS_PER_QUERY) ?? DEFAULT_YANDEX_RESULTS_PER_QUERY;
  const fetched = await Promise.all(
    queries.map(async (query) => {
      const url = new URL("https://search-maps.yandex.ru/v1/");
      url.searchParams.set("apikey", apiKey);
      url.searchParams.set("text", `${options.city}, ${query}`);
      url.searchParams.set("type", "biz");
      url.searchParams.set("lang", "ru_RU");
      url.searchParams.set("results", String(resultsPerQuery));

      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Yandex Places failed: ${response.status} ${response.statusText}`);
      }

      const body = (await response.json()) as YandexPlacesResponse;
      return (body.features ?? []).map((feature) => yandexFeatureToRecord(feature, {
        sourceType: options.sourceType,
        city: options.city,
        query
      }));
    })
  );

  return Array.from(
    new Map(
      fetched
        .flat()
        .filter((record): record is ClubSyncSourceRecord => record !== null)
        .map((record) => [`${record.sourceType}:${record.sourceExternalId ?? `${record.name}:${record.address}`}`, record])
    ).values()
  );
}

function yandexFeatureToRecord(
  feature: YandexFeature,
  context: { sourceType: string; city: string; query: string }
): ClubSyncSourceRecord | null {
  const company = feature.properties?.CompanyMetaData;
  const coordinates = feature.geometry?.coordinates;
  const lng = coordinates?.[0];
  const lat = coordinates?.[1];
  const sourceExternalId = company?.id ?? extractYandexOid(feature.properties?.uri);
  const categoryNames = company?.Categories?.map((category) => category.name).filter(Boolean) ?? [];
  const sports = normalizeClubSports([context.query, company?.name, ...categoryNames].join("|"));

  if (!company?.name || !company.address || lat == null || lng == null || sports.length === 0) {
    return null;
  }

  const yandexMapsUrl = sourceExternalId ? `https://yandex.ru/maps/org/${sourceExternalId}` : normalizeUrl(feature.properties?.uri);

  return {
    sourceType: context.sourceType,
    sourceExternalId,
    sourceUrl: yandexMapsUrl,
    name: company.name,
    address: company.address,
    city: context.city,
    sports,
    phone: company.Phones?.[0]?.formatted,
    workingHours: company.Hours?.text,
    yandexMapsUrl,
    websiteUrl: company.url,
    locationLat: lat,
    locationLng: lng,
    rating: company.Rating,
    raw: feature
  };
}

async function runWebsiteChecksForRun(
  prisma: PrismaClient,
  runId: string,
  options: {
    city: string;
    limit?: number;
    autoApplyWebsiteChanges?: boolean;
  }
) {
  const limit = options.limit ?? parseOptionalPositiveInt(process.env.CLUB_SYNC_WEBSITE_LIMIT) ?? DEFAULT_WEBSITE_LIMIT;
  const autoApplyWebsiteChanges = options.autoApplyWebsiteChanges ?? process.env.CLUB_SYNC_AUTO_APPLY_WEBSITE === "1";
  const courts = await prisma.court.findMany({
    where: {
      city: options.city,
      status: {
        in: [CourtStatus.active, CourtStatus.needs_review]
      },
      websiteUrl: {
        not: null
      }
    },
    select: {
      id: true,
      name: true,
      address: true,
      city: true,
      phone: true,
      workingHours: true,
      bookingUrl: true,
      supportedSports: true,
      about: true,
      websiteUrl: true,
      sourceType: true,
      sourceExternalId: true,
      websiteContentHash: true,
      manualOverrideFields: true,
      updatedAt: true
    },
    orderBy: [
      {
        websiteLastCheckedAt: "asc"
      },
      {
        updatedAt: "asc"
      }
    ],
    take: limit
  });

  const summary = {
    checkedCount: 0,
    changedCount: 0,
    failedCount: 0,
    proposedCount: 0
  };

  for (const court of courts) {
    summary.checkedCount += 1;
    const result = await checkCourtWebsite(prisma, {
      ...court,
      runId,
      autoApplyWebsiteChanges
    });

    if (result.changed) {
      summary.changedCount += 1;
    }

    if (result.failed) {
      summary.failedCount += 1;
    }

    if (result.proposed) {
      summary.proposedCount += 1;
    }
  }

  return summary;
}

async function checkCourtWebsite(
  prisma: PrismaClient,
  court: {
    id: string;
    name: string;
    address: string;
    city: string;
    phone: string | null;
    workingHours: string | null;
    bookingUrl: string | null;
    supportedSports: Prisma.JsonValue | null;
    about: string | null;
    websiteUrl: string | null;
    sourceType: string;
    sourceExternalId: string | null;
    websiteContentHash: string | null;
    manualOverrideFields: Prisma.JsonValue | null;
    updatedAt: Date;
    runId: string;
    autoApplyWebsiteChanges: boolean;
  }
) {
  const url = normalizeUrl(court.websiteUrl);
  if (!url) {
    return { changed: false, failed: false, proposed: false };
  }

  const checkedAt = new Date();

  try {
    const response = await fetchWebsiteHtml(url);
    const snapshot = extractClubWebsiteSnapshot(response.html, url);
    const changed = Boolean(court.websiteContentHash && court.websiteContentHash !== snapshot.contentHash);
    const analystInput: ClubWebsiteAnalystInput = { court, snapshot, changed };
    const rulesReview = analyzeClubWebsite(analystInput);
    const screenshotResult = isClubWebsiteLlmAnalystEnabled()
      ? await captureClubWebsiteScreenshotDataUrl(url)
      : disabledScreenshotResult();
    const llmResult = await analyzeClubWebsiteWithLlm({
      analystInput,
      screenshotDataUrl: screenshotResult.dataUrl
    });
    const analystReview = mergeClubWebsiteAnalystReviews(rulesReview, llmResult.review);
    const proposedFields = buildWebsiteProposedFields(analystReview);
    const shouldPropose = proposedFields.length > 0;
    const unlockedProposedFields = proposedFields.filter(
      (field) => !stringArray(court.manualOverrideFields).includes(field.field)
    );
    const proposalStatus =
      court.autoApplyWebsiteChanges &&
      unlockedProposedFields.length === proposedFields.length &&
      canAutoApplyWebsiteFields(unlockedProposedFields)
        ? "applied"
        : "pending";
    let proposalCreated = false;

    await prisma.courtWebsiteCheck.create({
      data: {
        runId: court.runId,
        courtId: court.id,
        url,
        status: changed ? "changed" : court.websiteContentHash ? "unchanged" : "baseline",
        checkedAt,
        httpStatus: response.httpStatus,
        contentHash: snapshot.contentHash,
        title: snapshot.title,
        description: snapshot.description,
        detectedPhones: snapshot.detectedPhones as Prisma.InputJsonValue,
        detectedBookingUrls: snapshot.detectedBookingUrls as Prisma.InputJsonValue,
        closureSignals: snapshot.closureSignals as Prisma.InputJsonValue,
        analystProvider: analystReview.provider,
        analystModel: llmResult.model,
        analystStatus: llmResult.status,
        analystErrorMessage: llmResult.errorMessage,
        screenshotStatus: screenshotResult.status,
        screenshotErrorMessage: screenshotResult.errorMessage,
        changed
      }
    });

    const courtUpdate = await prisma.court.updateMany({
      where: { id: court.id, updatedAt: court.updatedAt },
      data: {
        websiteContentHash: snapshot.contentHash,
        websiteLastCheckedAt: checkedAt,
        ...(changed ? { websiteLastChangedAt: checkedAt } : {}),
        ...(proposalStatus === "applied" ? buildWebsiteAutoUpdateData(unlockedProposedFields) : {})
      }
    });
    const effectiveProposalStatus = courtUpdate.count === 1 ? proposalStatus : "pending";

    if (shouldPropose) {
      proposalCreated = await createWebsiteChangeProposal(prisma, {
        court,
        snapshot,
        analystReview,
        analystRun: {
          status: llmResult.status,
          provider: llmResult.provider,
          model: llmResult.model,
          errorMessage: llmResult.errorMessage,
          screenshotIncluded: llmResult.screenshotIncluded,
          screenshotStatus: screenshotResult.status,
          screenshotErrorMessage: screenshotResult.errorMessage
        },
        proposedFields,
        changed,
        status: effectiveProposalStatus
      });
    }

    return {
      changed: changed || proposedFields.length > 0,
      failed: false,
      proposed: proposalCreated && effectiveProposalStatus === "pending"
    };
  } catch (error) {
    await prisma.courtWebsiteCheck.create({
      data: {
        runId: court.runId,
        courtId: court.id,
        url,
        status: "failed",
        checkedAt,
        errorMessage: error instanceof Error ? error.message : String(error)
      }
    });
    await prisma.court.update({
      where: { id: court.id },
      data: {
        websiteLastCheckedAt: checkedAt
      }
    });

    return { changed: false, failed: true, proposed: false };
  }
}

async function fetchWebsiteHtml(url: string) {
  const timeoutMs = parseOptionalPositiveInt(process.env.CLUB_SYNC_WEBSITE_TIMEOUT_MS) ?? DEFAULT_WEBSITE_TIMEOUT_MS;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "user-agent": "TennisSearchClubSync/1.0 (+https://sportsearch.app)",
        accept: "text/html,application/xhtml+xml,text/plain;q=0.8,*/*;q=0.2"
      }
    });

    if (!response.ok) {
      throw new Error(`Website fetch failed: ${response.status} ${response.statusText}`);
    }

    const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
    if (contentType && !contentType.includes("text/html") && !contentType.includes("text/plain")) {
      throw new Error(`Unsupported website content-type: ${contentType}`);
    }

    return {
      httpStatus: response.status,
      html: (await response.text()).slice(0, 1_000_000)
    };
  } finally {
    clearTimeout(timer);
  }
}

function buildWebsiteProposedFields(review: ClubWebsiteAnalystReview) {
  return review.decisions
    .filter((decision) => decision.candidateValue !== null)
    .map((decision) => ({
      field: decision.field,
      value: decision.candidateValue ?? "",
      confidence: decision.confidence,
      autoApply: decision.action === "apply",
      reason: decision.reason,
      evidence: decision.evidence as Prisma.InputJsonValue
    }));
}

function disabledScreenshotResult(): ClubWebsiteScreenshotResult {
  return {
    status: "disabled",
    dataUrl: null,
    errorMessage: null
  };
}

async function createWebsiteChangeProposal(
  prisma: PrismaClient,
  options: {
    court: {
      id: string;
      name: string;
      address: string;
      city: string;
      phone: string | null;
      workingHours: string | null;
      bookingUrl: string | null;
      supportedSports: Prisma.JsonValue | null;
      about: string | null;
      sourceType: string;
      sourceExternalId: string | null;
      runId: string;
    };
    snapshot: ClubWebsiteSnapshot;
    analystReview: ClubWebsiteAnalystReview;
    analystRun: Prisma.InputJsonValue;
    proposedFields: WebsiteProposedField[];
    changed: boolean;
    status: "pending" | "applied";
  }
) {
  if (options.status === "pending") {
    const existingPending = await prisma.courtChangeProposal.findFirst({
      where: {
        courtId: options.court.id,
        sourceType: "club-website",
        action: "website_update",
        status: "pending"
      },
      select: {
        id: true
      }
    });

    if (existingPending) {
      return false;
    }
  }

  await prisma.courtChangeProposal.create({
    data: {
      runId: options.court.runId,
      courtId: options.court.id,
      sourceType: "club-website",
      sourceExternalId: options.court.sourceExternalId,
      action: "website_update",
      status: options.status,
      appliedAt: options.status === "applied" ? new Date() : null,
      confidence: resolveProposalConfidence(options.proposedFields),
      reason: options.proposedFields.length > 0 ? "website_detected_fields" : "website_snapshot_changed",
      before: {
        id: options.court.id,
        name: options.court.name,
        city: options.court.city,
        address: options.court.address,
        phone: options.court.phone,
        workingHours: options.court.workingHours,
        bookingUrl: options.court.bookingUrl,
        supportedSports: options.court.supportedSports,
        about: options.court.about
      },
      after: {
        websiteUrl: options.snapshot.url,
        contentHash: options.snapshot.contentHash,
        title: options.snapshot.title,
        description: options.snapshot.description,
        textSample: options.snapshot.textSample,
        detectedPhones: options.snapshot.detectedPhones,
        detectedBookingUrls: options.snapshot.detectedBookingUrls,
        closureSignals: options.snapshot.closureSignals,
        phoneEvidence: options.snapshot.phoneEvidence,
        bookingUrlEvidence: options.snapshot.bookingUrlEvidence,
        closureSignalEvidence: options.snapshot.closureSignalEvidence,
        analystReview: options.analystReview as unknown as Prisma.InputJsonValue,
        analystRun: options.analystRun,
        proposedFields: options.proposedFields,
        changed: options.changed
      }
    }
  });

  return true;
}

function resolveProposalConfidence(fields: WebsiteProposedField[]) {
  return fields.length > 0 ? Math.max(...fields.map((field) => field.confidence)) : 0.5;
}

function canAutoApplyWebsiteFields(fields: WebsiteProposedField[]) {
  return fields.length > 0 && fields.every((field) => field.field === "bookingUrl" && field.autoApply);
}

function buildWebsiteAutoUpdateData(fields: WebsiteProposedField[]): Prisma.CourtUncheckedUpdateInput {
  return Object.fromEntries(
    fields
      .filter((field) => field.field === "bookingUrl" && field.autoApply)
      .map((field) => [field.field, Array.isArray(field.value) ? field.value[0] : field.value])
  );
}

export function buildCourtSyncCandidateWhere(
  city: string,
  records: readonly Pick<NormalizedClubSyncRecord, "sourceType" | "sourceExternalId">[] = []
): Prisma.CourtWhereInput {
  const stableSources = Array.from(
    new Map(
      records
        .filter((record): record is typeof record & { sourceExternalId: string } => Boolean(record.sourceExternalId))
        .map((record) => [`${record.sourceType}:${record.sourceExternalId}`, record])
    ).values()
  );
  return {
    OR: [
      { city },
      ...stableSources.map((record) => ({
        sourceType: record.sourceType,
        sourceExternalId: record.sourceExternalId
      }))
    ]
  };
}

async function loadCourtsForSync(
  prisma: Pick<PrismaClient, "court">,
  city: string,
  records: readonly Pick<NormalizedClubSyncRecord, "sourceType" | "sourceExternalId">[] = []
): Promise<CourtForSync[]> {
  const courts = await prisma.court.findMany({
    where: buildCourtSyncCandidateWhere(city, records),
    select: {
      id: true,
      name: true,
      address: true,
      city: true,
      district: true,
      nearestMetroId: true,
      locationLat: true,
      locationLng: true,
      status: true,
      supportedSports: true,
      phone: true,
      workingHours: true,
      yandexMapsUrl: true,
      websiteUrl: true,
      bookingUrl: true,
      about: true,
      amenities: true,
      messengerType: true,
      messengerUrl: true,
      photoUrl: true,
      photoUrls: true,
      rating: true,
      sourceType: true,
      sourceExternalId: true,
      sourceUrl: true,
      normalizedName: true,
      normalizedAddress: true,
      syncHash: true,
      lastSeenAt: true,
      manualOverrideFields: true,
      manualStatusOverride: true,
      updatedAt: true
    }
  });

  return courts;
}

function findBestCourtMatch(courts: CourtForSync[], record: NormalizedClubSyncRecord, threshold: number) {
  let best: { court: CourtForSync; confidence: number; reason: string } | null = null;

  for (const court of courts) {
    const score = scoreClubCourtMatch(court, record);
    if (!best || score.confidence > best.confidence) {
      best = { court, ...score };
    }
  }

  return best && best.confidence >= threshold ? best : null;
}

async function createSyncedCourt(
  prisma: PrismaClient,
  record: NormalizedClubSyncRecord,
  metroByName: Map<string, string>,
  options: { status: CourtStatus; now: Date }
) {
  const firstMetroId = record.metroNames[0] ? metroByName.get(record.metroNames[0].toLowerCase()) ?? null : null;
  return prisma.court.create({
    data: {
      name: record.name,
      address: record.address,
      city: record.city,
      district: record.district,
      nearestMetroId: firstMetroId,
      locationLat: record.locationLat,
      locationLng: record.locationLng,
      surface: Surface.any,
      setting: CourtSetting.indoor,
      status: options.status,
      supportedSports: record.sports as Prisma.InputJsonValue,
      phone: record.phone,
      workingHours: record.workingHours,
      yandexMapsUrl: record.yandexMapsUrl,
      websiteUrl: record.websiteUrl,
      bookingUrl: record.bookingUrl,
      about: record.about,
      amenities: record.amenities as Prisma.InputJsonValue,
      messengerType: record.messengerType,
      messengerUrl: record.messengerUrl,
      photoUrl: record.photoUrl,
      photoUrls: record.photoUrls as Prisma.InputJsonValue,
      priceRange: "Не указано",
      rating: record.rating,
      sourceType: record.sourceType,
      sourceExternalId: record.sourceExternalId,
      sourceUrl: record.sourceUrl,
      normalizedName: record.normalizedName,
      normalizedAddress: record.normalizedAddress,
      syncHash: record.syncHash,
      lastCheckedAt: options.now,
      lastSeenAt: options.now
    }
  });
}

async function updateSyncedCourt(
  prisma: PrismaClient,
  existing: CourtForSync,
  record: NormalizedClubSyncRecord,
  metroByName: Map<string, string>,
  options: { now: Date; runId: string; confidence: number; reason: string }
) {
  const lockedConflictFields = getLockedChangedFields(existing, record);
  const riskyFields = Array.from(new Set([...getRiskyChangedFields(existing, record), ...lockedConflictFields]));
  const hasNewSnapshot = existing.syncHash !== record.syncHash;
  const hasSafeIdentityDrift = riskyFields.length === 0 && hasDisplayIdentityDrift(existing, record);
  const updateData = buildSafeUpdateData(existing, record, options.now, riskyFields.length === 0);
  const shouldUpdate =
    hasNewSnapshot || hasSafeIdentityDrift || existing.status === CourtStatus.hidden || existing.status === CourtStatus.archived;

  let updatedCourt = existing;
  if (shouldUpdate) {
    const outcome = await prisma.$transaction(async (tx) => {
      const updateResult = await tx.court.updateMany({
        where: { id: existing.id, updatedAt: existing.updatedAt },
        data: updateData
      });
      const refreshed = (await loadCourtsForSync(tx, existing.city)).find((court) => court.id === existing.id);
      if (!refreshed) throw new Error("Synced court disappeared during update");
      if (updateResult.count !== 1) return { court: refreshed, updated: false };
      if (shouldSyncCourtMetroLinks(stringArray(existing.manualOverrideFields))) {
        await syncCourtMetroLinks(tx, existing.id, record.metroNames, metroByName);
      }
      const afterMetro = (await loadCourtsForSync(tx, existing.city)).find((court) => court.id === existing.id);
      return { court: afterMetro ?? refreshed, updated: true };
    });
    if (!outcome.updated) return { court: outcome.court, updated: false, proposed: false };
    updatedCourt = outcome.court;
  } else {
    await prisma.court.update({
      where: { id: existing.id },
      data: {
        lastCheckedAt: options.now,
        lastSeenAt: options.now,
        ...(record.sourceExternalId && !existing.sourceExternalId ? { sourceExternalId: record.sourceExternalId } : {})
      }
    });
  }

  const shouldPropose = riskyFields.length > 0 && (hasNewSnapshot || lockedConflictFields.length > 0);
  if (shouldPropose) {
    const existingPending = await prisma.courtChangeProposal.findFirst({
      where: { courtId: existing.id, sourceType: record.sourceType, action: "update", status: "pending" },
      select: { id: true }
    });
    if (!existingPending) {
      await prisma.courtChangeProposal.create({
        data: {
          runId: options.runId,
          courtId: existing.id,
          sourceType: record.sourceType,
          sourceExternalId: record.sourceExternalId,
          action: "update",
          status: "pending",
          confidence: options.confidence,
          reason: `${options.reason}:${riskyFields.join(",")}`,
          before: proposalBefore(existing),
          after: proposalAfter(record)
        }
      });
    }
  }

  return {
    court: updatedCourt,
    updated: shouldUpdate,
    proposed: shouldPropose
  };
}

function buildSafeUpdateData(
  existing: CourtForSync,
  record: NormalizedClubSyncRecord,
  now: Date,
  allowIdentityUpdates: boolean
): Prisma.CourtUncheckedUpdateInput {
  const locks = lockedFields(existing);
  const status = resolveSyncedCourtStatus(existing.status, existing.manualStatusOverride);

  const data: Prisma.CourtUncheckedUpdateInput = {
    ...(allowIdentityUpdates
      ? {
          name: record.name,
          address: record.address,
          district: record.district,
          locationLat: record.locationLat,
          locationLng: record.locationLng
        }
      : {
          ...(existing.district ? {} : { district: record.district })
        }),
    status,
    supportedSports: record.sports as Prisma.InputJsonValue,
    phone: record.phone ?? existing.phone,
    workingHours: record.workingHours ?? existing.workingHours,
    yandexMapsUrl: record.yandexMapsUrl ?? existing.yandexMapsUrl,
    websiteUrl: record.websiteUrl ?? existing.websiteUrl,
    bookingUrl: record.bookingUrl ?? existing.bookingUrl,
    about: record.about ?? existing.about,
    amenities: record.amenities.length > 0 ? (record.amenities as Prisma.InputJsonValue) : existing.amenities ?? Prisma.JsonNull,
    messengerType: record.messengerType ?? existing.messengerType,
    messengerUrl: record.messengerUrl ?? existing.messengerUrl,
    photoUrl: record.photoUrl ?? existing.photoUrl,
    photoUrls: record.photoUrls.length > 0 ? (record.photoUrls as Prisma.InputJsonValue) : existing.photoUrls ?? Prisma.JsonNull,
    rating: record.rating ?? existing.rating,
    sourceType: record.sourceType,
    sourceExternalId: record.sourceExternalId ?? existing.sourceExternalId,
    sourceUrl: record.sourceUrl ?? existing.sourceUrl,
    normalizedName: record.normalizedName,
    normalizedAddress: record.normalizedAddress,
    syncHash: record.syncHash,
    lastCheckedAt: now,
    lastSeenAt: now
  };
  return applyManualCourtOverridesForSync(Array.from(locks), data) as Prisma.CourtUncheckedUpdateInput;
}

export function resolveSyncedCourtStatus(status: CourtStatus, manualStatusOverride: boolean) {
  return !manualStatusOverride && (status === CourtStatus.hidden || status === CourtStatus.archived)
    ? CourtStatus.needs_review
    : status;
}

export function applyManualCourtOverridesForSync<T extends Record<string, unknown>>(
  manualOverrideFields: readonly string[],
  input: T
) {
  const data: Record<string, unknown> = { ...input };
  const locks = new Set(manualOverrideFields);
  for (const field of locks) {
    if (field !== "metroIds" && field in data) delete data[field];
  }
  if (locks.has("name")) delete data.normalizedName;
  if (locks.has("address")) delete data.normalizedAddress;
  return data;
}

export function shouldSyncCourtMetroLinks(manualOverrideFields: readonly string[]) {
  return !manualOverrideFields.includes("metroIds");
}

function lockedFields(existing: Pick<CourtForSync, "manualOverrideFields">) {
  return new Set(stringArray(existing.manualOverrideFields));
}

function stringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function getLockedChangedFields(existing: CourtForSync, record: NormalizedClubSyncRecord) {
  const incoming: Record<string, unknown> = {
    name: record.name,
    address: record.address,
    city: record.city,
    district: record.district,
    locationLat: record.locationLat,
    locationLng: record.locationLng,
    supportedSports: record.sports,
    phone: record.phone,
    workingHours: record.workingHours,
    yandexMapsUrl: record.yandexMapsUrl,
    websiteUrl: record.websiteUrl,
    bookingUrl: record.bookingUrl,
    about: record.about,
    amenities: record.amenities,
    messengerType: record.messengerType,
    messengerUrl: record.messengerUrl,
    photoUrl: record.photoUrl,
    photoUrls: record.photoUrls
  };
  return Array.from(lockedFields(existing)).filter((field) => {
    if (!(field in incoming) || incoming[field] == null) return false;
    const current = existing[field as keyof CourtForSync];
    return JSON.stringify(current) !== JSON.stringify(incoming[field]);
  });
}

function getRiskyChangedFields(existing: CourtForSync, record: NormalizedClubSyncRecord) {
  const fields: string[] = [];
  const existingName = existing.normalizedName ?? "";
  const existingAddress = existing.normalizedAddress ?? "";
  const distanceKm = haversineDistanceKm(
    { lat: existing.locationLat, lng: existing.locationLng },
    { lat: record.locationLat, lng: record.locationLng }
  );

  if (existingName && existingName !== record.normalizedName) {
    fields.push("name");
  }

  if (existingAddress && existingAddress !== record.normalizedAddress) {
    fields.push("address");
  }

  if (distanceKm != null && distanceKm > 0.25) {
    fields.push("location");
  }

  if (existing.district && record.district && existing.district !== record.district) {
    fields.push("district");
  }

  return fields;
}

function hasDisplayIdentityDrift(existing: CourtForSync, record: NormalizedClubSyncRecord) {
  return existing.name !== record.name || existing.address !== record.address;
}

async function ensureMetroMap(prisma: PrismaClient, records: NormalizedClubSyncRecord[], city: string) {
  const metroNames = Array.from(new Set(records.flatMap((record) => record.metroNames).map((name) => name.trim()).filter(Boolean)));
  if (metroNames.length === 0) {
    return new Map<string, string>();
  }

  await prisma.metro.createMany({
    data: metroNames.map((name) => ({ name, city })),
    skipDuplicates: true
  });

  const metros = await prisma.metro.findMany({
    where: {
      name: {
        in: metroNames
      }
    },
    select: {
      id: true,
      name: true
    }
  });

  return new Map(metros.map((metro) => [metro.name.toLowerCase(), metro.id]));
}

async function syncCourtMetroLinks(
  prisma: Pick<PrismaClient, "court" | "courtMetro">,
  courtId: string,
  metroNames: string[],
  metroByName: Map<string, string>
) {
  if (metroNames.length === 0) {
    return;
  }

  const rows = metroNames.flatMap((name, position) => {
    const metroId = metroByName.get(name.toLowerCase());
    return metroId ? [{ courtId, metroId, position }] : [];
  });

  await prisma.courtMetro.deleteMany({ where: { courtId } });
  if (rows.length > 0) {
    await prisma.courtMetro.createMany({
      data: rows,
      skipDuplicates: true
    });
    await prisma.court.update({
      where: { id: courtId },
      data: {
        nearestMetroId: rows[0].metroId
      }
    });
  }
}

async function handleStaleCourts(
  prisma: PrismaClient,
  options: {
    runId: string;
    sourceType: string;
    city: string;
    seenCourtIds: Set<string>;
    staleAfterDays: number;
    autoHideStale: boolean;
    now: Date;
  }
) {
  const cutoff = new Date(options.now.getTime() - options.staleAfterDays * 24 * 60 * 60 * 1000);
  const candidates = await prisma.court.findMany({
    where: {
      sourceType: options.sourceType,
      city: options.city,
      id: {
        notIn: Array.from(options.seenCourtIds)
      },
      status: {
        in: [CourtStatus.active, CourtStatus.needs_review]
      },
      manualStatusOverride: false,
      lastSeenAt: {
        lt: cutoff
      }
    },
    select: {
      id: true,
      sourceExternalId: true,
      name: true,
      address: true,
      city: true,
      status: true,
      lastSeenAt: true,
      updatedAt: true
    }
  });

  let hiddenCount = 0;
  let proposedCount = 0;

  for (const court of candidates) {
    const hidden = options.autoHideStale
      ? await prisma.court.updateMany({
          where: { id: court.id, updatedAt: court.updatedAt, manualStatusOverride: false },
          data: { status: CourtStatus.hidden, lastCheckedAt: options.now }
        })
      : { count: 0 };
    const applied = hidden.count === 1;
    await prisma.courtChangeProposal.create({
      data: {
        runId: options.runId,
        courtId: court.id,
        sourceType: options.sourceType,
        sourceExternalId: court.sourceExternalId,
        action: "hide",
        status: applied ? "applied" : "pending",
        appliedAt: applied ? options.now : null,
        confidence: 0.6,
        reason: `not_seen_for_${options.staleAfterDays}_days`,
        before: {
          id: court.id,
          name: court.name,
          address: court.address,
          city: court.city,
          status: court.status,
          lastSeenAt: court.lastSeenAt?.toISOString() ?? null
        },
        after: {
          status: CourtStatus.hidden,
          lastCheckedAt: options.now.toISOString()
        }
      }
    });

    if (applied) {
      hiddenCount += 1;
    } else {
      proposedCount += 1;
    }
  }

  return { hiddenCount, proposedCount };
}

function dedupeRecords(records: NormalizedClubSyncRecord[]) {
  return Array.from(
    new Map(
      records.map((record) => [
        record.sourceExternalId
          ? `${record.sourceType}:${record.sourceExternalId}`
          : `${record.normalizedName}:${record.normalizedAddress}:${record.city}`,
        record
      ])
    ).values()
  );
}

function toCourtForSync(court: Awaited<ReturnType<typeof createSyncedCourt>>): CourtForSync {
  return {
    id: court.id,
    name: court.name,
    address: court.address,
    city: court.city,
    district: court.district,
    nearestMetroId: court.nearestMetroId,
    locationLat: court.locationLat,
    locationLng: court.locationLng,
    status: court.status,
    supportedSports: court.supportedSports,
    phone: court.phone,
    workingHours: court.workingHours,
    yandexMapsUrl: court.yandexMapsUrl,
    websiteUrl: court.websiteUrl,
    bookingUrl: court.bookingUrl,
    about: court.about,
    amenities: court.amenities,
    messengerType: court.messengerType,
    messengerUrl: court.messengerUrl,
    photoUrl: court.photoUrl,
    photoUrls: court.photoUrls,
    rating: court.rating,
    sourceType: court.sourceType,
    sourceExternalId: court.sourceExternalId,
    sourceUrl: court.sourceUrl,
    normalizedName: court.normalizedName,
    normalizedAddress: court.normalizedAddress,
    syncHash: court.syncHash,
    lastSeenAt: court.lastSeenAt,
    manualOverrideFields: court.manualOverrideFields,
    manualStatusOverride: court.manualStatusOverride,
    updatedAt: court.updatedAt
  };
}

function replaceCourtForSync(courts: CourtForSync[], updated: CourtForSync) {
  const index = courts.findIndex((court) => court.id === updated.id);
  if (index >= 0) {
    courts[index] = updated;
  }
}

function proposalBefore(court: CourtForSync) {
  return {
    id: court.id,
    name: court.name,
    address: court.address,
    city: court.city,
    district: court.district,
    locationLat: court.locationLat,
    locationLng: court.locationLng,
    supportedSports: court.supportedSports,
    phone: court.phone,
    workingHours: court.workingHours,
    yandexMapsUrl: court.yandexMapsUrl,
    websiteUrl: court.websiteUrl,
    bookingUrl: court.bookingUrl,
    about: court.about,
    amenities: court.amenities,
    messengerType: court.messengerType,
    messengerUrl: court.messengerUrl,
    photoUrl: court.photoUrl,
    photoUrls: court.photoUrls,
    rating: court.rating,
    status: court.status
  };
}

function proposalAfter(record: NormalizedClubSyncRecord) {
  return {
    name: record.name,
    address: record.address,
    city: record.city,
    district: record.district,
    locationLat: record.locationLat,
    locationLng: record.locationLng,
    supportedSports: record.sports,
    phone: record.phone,
    workingHours: record.workingHours,
    yandexMapsUrl: record.yandexMapsUrl,
    websiteUrl: record.websiteUrl,
    bookingUrl: record.bookingUrl,
    about: record.about,
    amenities: record.amenities,
    messengerType: record.messengerType,
    messengerUrl: record.messengerUrl,
    photoUrl: record.photoUrl,
    photoUrls: record.photoUrls,
    rating: record.rating,
    sourceType: record.sourceType,
    sourceExternalId: record.sourceExternalId,
    sourceUrl: record.sourceUrl,
    syncHash: record.syncHash
  };
}

function resolveProvider(): ClubSyncProvider {
  const value = process.env.CLUB_SYNC_PROVIDER?.trim().toLowerCase();
  return value === "json" ? "json" : "yandex";
}

function parseList(value: string | undefined) {
  return (value ?? "")
    .split(/[|,\n]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseOptionalPositiveInt(value: string | undefined) {
  if (!value) {
    return null;
  }

  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function extractYandexOid(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const match = value.match(/oid=(\d+)/);
  return match?.[1] ?? null;
}

type YandexPlacesResponse = {
  features?: YandexFeature[];
};

type YandexFeature = {
  geometry?: {
    coordinates?: [number, number];
  };
  properties?: {
    uri?: string;
    CompanyMetaData?: {
      id?: string;
      name?: string;
      address?: string;
      url?: string;
      Rating?: number | string;
      Phones?: Array<{ formatted?: string }>;
      Hours?: { text?: string };
      Categories?: Array<{ name?: string }>;
    };
  };
};
