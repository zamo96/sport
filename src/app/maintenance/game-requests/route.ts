import { NextRequest } from "next/server";

import { fail, ok } from "@/lib/http";
import { runGameRequestMaintenance } from "@/server/game-request-maintenance";
import { runHotSearchDigestMaintenance } from "@/server/hot-search-digest";
import { runLifecycleCampaigns } from "@/server/lifecycle-campaigns";
import { runPendingActionReminders } from "@/server/pending-action-reminders";

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

  // dryRun=1 показывает, кого выберут кампании и с каким текстом, ничего не
  // отправляя и не записывая — единственный способ проверить аудиторию до
  // первой реальной рассылки.
  const dryRun = ["1", "true"].includes(request.nextUrl.searchParams.get("dryRun")?.trim() ?? "");
  const now = new Date();

  // Дайджест и кампании делят один дневной лимит на игрока, поэтому идут
  // последовательно: параллельно оба прошли бы проверку до записи доставки.
  // Общий на прогон счётчик доставок: в dry-run записей в базе нет, а дневной
  // лимит у дайджеста и кампаний один на игрока.
  const simulatedDeliveries = new Map<string, number>();
  const gameRequests = dryRun ? null : await runGameRequestMaintenance();
  // Напоминания транзакционные: общий дневной лимит они не расходуют, поэтому
  // их порядок относительно рассылок ни на что не влияет.
  const pendingActionReminders = await runPendingActionReminders(now, { dryRun });
  const hotSearchDigest = await runHotSearchDigestMaintenance(now, { dryRun, simulatedDeliveries });
  const lifecycleCampaigns = await runLifecycleCampaigns(now, { dryRun, simulatedDeliveries });

  return ok({ success: true, dryRun, gameRequests, pendingActionReminders, hotSearchDigest, lifecycleCampaigns });
}
