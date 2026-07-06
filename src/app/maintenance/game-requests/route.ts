import { NextRequest } from "next/server";

import { fail, ok } from "@/lib/http";
import { runGameRequestMaintenance } from "@/server/game-request-maintenance";
import { runHotSearchDigestMaintenance } from "@/server/hot-search-digest";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  return handleMaintenance(request);
}

export async function POST(request: NextRequest) {
  return handleMaintenance(request);
}

async function handleMaintenance(request: NextRequest) {
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

  const [gameRequests, hotSearchDigest] = await Promise.all([
    runGameRequestMaintenance(),
    runHotSearchDigestMaintenance()
  ]);

  return ok({ success: true, gameRequests, hotSearchDigest });
}
