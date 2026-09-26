import { NextRequest } from "next/server";

import { requireSessionUser } from "@/lib/auth";
import { ok } from "@/lib/http";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { resolveRequestLocale } from "@/lib/locales";
import { mePhoneVerifySchema } from "@/lib/validators";
import { enforceAuthRateLimit } from "@/server/auth-rate-limit";
import { consumePhoneCode, linkPhoneToUser, PhoneAuthError } from "@/server/phone-auth";
import { phoneAuthFailure } from "@/server/phone-auth-http";
import { serializeMe } from "@/server/serializers";

/** Привязывает подтверждённый номер к текущему аккаунту и отдаёт обновлённый профиль. */
export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  let phone: string | undefined;
  try {
    const user = await requireSessionUser();
    const body = mePhoneVerifySchema.parse(await request.json());
    phone = body.phone;
    await enforceAuthRateLimit("phone-verify", body.phone, request);
    if (!(await consumePhoneCode(body.phone, body.code))) {
      throw new PhoneAuthError("INVALID_CODE");
    }
    const updated = await linkPhoneToUser(user.id, body.phone);
    const requestLocale = resolveRequestLocale({ acceptLanguage: request.headers.get("accept-language") });
    return ok({ user: serializeMe(updated, requestLocale) });
  } catch (error) {
    return phoneAuthFailure(error, locale, phone);
  }
}
