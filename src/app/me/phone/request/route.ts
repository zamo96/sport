import { NextRequest } from "next/server";

import { getLegalAcceptanceRequestMeta, requireSessionUser } from "@/lib/auth";
import { ok } from "@/lib/http";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { prisma } from "@/lib/prisma";
import { mePhoneRequestSchema } from "@/lib/validators";
import { enforceAuthRateLimit } from "@/server/auth-rate-limit";
import { issuePhoneCode, PHONE_CODE_TTL_MINUTES, PhoneAuthError } from "@/server/phone-auth";
import { phoneAuthFailure } from "@/server/phone-auth-http";
import { isSmsDevFallback } from "@/server/sms";

/** Код для привязки номера к уже открытому аккаунту. */
export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  let phone: string | undefined;
  try {
    const user = await requireSessionUser();
    const body = mePhoneRequestSchema.parse(await request.json());
    phone = body.phone;
    const owner = await prisma.user.findUnique({ where: { phone: body.phone }, select: { id: true } });
    // Не тратим SMS на номер, который всё равно не удастся привязать.
    if (owner && owner.id !== user.id) throw new PhoneAuthError("PHONE_TAKEN");
    await enforceAuthRateLimit("phone-request", body.phone, request);
    const code = await issuePhoneCode(body.phone, { ip: getLegalAcceptanceRequestMeta(request).ip });
    return ok({ ok: true, expiresInMinutes: PHONE_CODE_TTL_MINUTES, debugCode: isSmsDevFallback() ? code : undefined });
  } catch (error) {
    return phoneAuthFailure(error, locale, phone);
  }
}
