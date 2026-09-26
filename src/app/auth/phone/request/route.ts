import { NextRequest } from "next/server";

import { getLegalAcceptanceRequestMeta } from "@/lib/auth";
import { ok } from "@/lib/http";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { phoneRequestSchema } from "@/lib/validators";
import { enforceAuthRateLimit } from "@/server/auth-rate-limit";
import { issuePhoneCode, PHONE_CODE_TTL_MINUTES } from "@/server/phone-auth";
import { phoneAuthFailure } from "@/server/phone-auth-http";
import { isSmsDevFallback } from "@/server/sms";

/** Вход для России: код по SMS на российский мобильный номер (ч. 10 ст. 8 149-ФЗ). */
export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  let phone: string | undefined;
  try {
    const body = phoneRequestSchema.parse(await request.json());
    phone = body.phone;
    await enforceAuthRateLimit("phone-request", body.phone, request);
    const code = await issuePhoneCode(body.phone, { ip: getLegalAcceptanceRequestMeta(request).ip });
    return ok({
      ok: true,
      expiresInMinutes: PHONE_CODE_TTL_MINUTES,
      // Как debugCode у email: только при локальной разработке без ключа SMS.ru.
      debugCode: isSmsDevFallback() ? code : undefined
    });
  } catch (error) {
    return phoneAuthFailure(error, locale, phone);
  }
}
