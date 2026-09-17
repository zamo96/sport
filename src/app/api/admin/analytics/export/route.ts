import { requireAdminUser } from "@/lib/admin";
import { analyticsJournalCsv } from "@/lib/admin-analytics";
import { fail, getErrorMessage } from "@/lib/http";
import { getAdminAnalyticsExport } from "@/server/admin-analytics";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    await requireAdminUser();
    const params = new URL(request.url).searchParams;
    const result = await getAdminAnalyticsExport({
      days: Number(params.get("days") ?? 30), userId: params.get("userId") ?? "", eventType: params.get("eventType") ?? ""
    });
    return new Response(analyticsJournalCsv(result.items, result.truncated), {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="tennissearch-events-${new Date().toISOString().slice(0, 10)}${result.truncated ? "-truncated" : ""}.csv"`,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
        "X-Export-Truncated": String(result.truncated)
      }
    });
  } catch (error) {
    const message = getErrorMessage(error);
    if (message === "UNAUTHORIZED") return fail("Требуется авторизация", 401);
    if (message === "FORBIDDEN") return fail("Недостаточно прав", 403);
    if (message === "ADMIN_UNCONFIGURED") return fail("Доступ администратора не настроен", 503);
    console.error("Analytics export failed", error);
    return fail("Не удалось выгрузить события", 500);
  }
}
