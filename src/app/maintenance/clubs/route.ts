import { NextRequest } from "next/server";

import { fail, ok } from "@/lib/http";
import { type ClubSyncSummary, runClubSync } from "@/server/club-sync";
import { buildClubSyncReport } from "@/server/club-sync-report";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  return handleClubMaintenance(request);
}

export async function POST(request: NextRequest) {
  return handleClubMaintenance(request);
}

async function handleClubMaintenance(request: NextRequest) {
  const configuredSecret = process.env.MAINTENANCE_SECRET?.trim() || process.env.CRON_SECRET?.trim();

  if (!configuredSecret) {
    return fail("Maintenance secret is not configured", 503);
  }

  const authorization = request.headers.get("authorization")?.trim() ?? "";
  const bearer = authorization.startsWith("Bearer ") ? authorization.slice("Bearer ".length).trim() : "";
  const querySecret = request.nextUrl.searchParams.get("secret")?.trim() ?? "";

  if (bearer !== configuredSecret && querySecret !== configuredSecret) {
    return fail("Нет доступа", 403);
  }

  if (request.nextUrl.searchParams.get("reportOnly") === "1") {
    const report = await buildClubSyncReport({
      runId: request.nextUrl.searchParams.get("runId"),
      sourceType: request.nextUrl.searchParams.get("sourceType"),
      city: request.nextUrl.searchParams.get("city"),
      limit: parsePositiveInt(request.nextUrl.searchParams.get("limit")) ?? undefined
    });

    if (!report) {
      return fail("Отчет не найден", 404);
    }

    return ok({ success: true, report });
  }

  const provider = parseProvider(request.nextUrl.searchParams.get("provider"));
  const staleAfterDays = parsePositiveInt(request.nextUrl.searchParams.get("staleAfterDays"));
  const websiteLimit = parsePositiveInt(request.nextUrl.searchParams.get("websiteLimit"));
  const summary = await runClubSync({
    provider,
    city: request.nextUrl.searchParams.get("city") ?? undefined,
    sourceType: request.nextUrl.searchParams.get("sourceType") ?? undefined,
    autoPublishNew: request.nextUrl.searchParams.get("autoPublishNew") === "1" ? true : undefined,
    autoHideStale: request.nextUrl.searchParams.get("autoHideStale") === "1" ? true : undefined,
    staleAfterDays: staleAfterDays ?? undefined,
    checkWebsites: request.nextUrl.searchParams.get("checkWebsites") === "0" ? false : undefined,
    websitesOnly: request.nextUrl.searchParams.get("websitesOnly") === "1",
    websiteLimit: websiteLimit ?? undefined,
    autoApplyWebsiteChanges: request.nextUrl.searchParams.get("autoApplyWebsiteChanges") === "1" ? true : undefined
  });

  return ok(await buildMaintenanceResponse(summary, request.nextUrl.searchParams.get("includeReport") === "1"));
}

async function buildMaintenanceResponse(summary: ClubSyncSummary, includeReport: boolean) {
  const response: {
    success: true;
    clubs: ClubSyncSummary;
    report?: Awaited<ReturnType<typeof buildClubSyncReport>>;
  } = {
    success: true,
    clubs: summary
  };

  if (includeReport) {
    response.report = await buildClubSyncReport({ runId: summary.runId });
  }

  return response;
}

function parseProvider(value: string | null) {
  return value === "json" || value === "yandex" ? value : undefined;
}

function parsePositiveInt(value: string | null) {
  if (!value) {
    return null;
  }

  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}
