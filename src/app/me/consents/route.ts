import { NextRequest } from "next/server";
import { ZodError } from "zod";

import { getLegalAcceptanceRequestMeta, requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { resolveRequestLocale } from "@/lib/locales";
import { consentUpdateSchema } from "@/lib/validators";
import { applyConsentUpdate, ConsentUpdateError } from "@/server/consents";
import { serializeMe } from "@/server/serializers";

/**
 * Ответ на экран согласий и изменения в настройках: принятие новой редакции
 * соглашения, согласие на показ анкеты, согласие на аналитику — каждое
 * фиксируется отдельно.
 */
export async function POST(request: NextRequest) {
  try {
    const user = await requireSessionUser();
    const body = consentUpdateSchema.parse(await request.json());
    const updated = await applyConsentUpdate(user.id, body, getLegalAcceptanceRequestMeta(request));
    const requestLocale = resolveRequestLocale({ acceptLanguage: request.headers.get("accept-language") });
    return ok({ user: serializeMe(updated, requestLocale) });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }
    if (error instanceof ConsentUpdateError) {
      return fail(error.message, 422);
    }
    if (error instanceof ZodError) {
      return fail(getErrorMessage(error), 400);
    }
    return fail(getErrorMessage(error));
  }
}
