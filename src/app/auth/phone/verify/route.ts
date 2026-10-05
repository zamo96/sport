import { NextRequest } from "next/server";

import { createSession, getLegalAcceptanceRequestMeta, recordUserAgreementAcceptance } from "@/lib/auth";
import { ok } from "@/lib/http";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { prisma } from "@/lib/prisma";
import { phoneVerifySchema } from "@/lib/validators";
import { enforceAuthRateLimit } from "@/server/auth-rate-limit";
import { consumePhoneCode, PhoneAuthError, signInWithPhone } from "@/server/phone-auth";
import { phoneAuthFailure } from "@/server/phone-auth-http";

/** Проверка SMS-кода и вход. Ответ того же вида, что у /auth/verify. */
export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  let phone: string | undefined;
  try {
    const body = phoneVerifySchema.parse(await request.json());
    phone = body.phone;
    await enforceAuthRateLimit("phone-verify", body.phone, request);
    if (!(await consumePhoneCode(body.phone, body.code))) {
      throw new PhoneAuthError("INVALID_CODE");
    }

    const user = await signInWithPhone(body.phone, { showOnMap: body.showOnMap, consentReview: body.consentReview });
    const userWithAgreement = await recordUserAgreementAcceptance(
      user.id,
      "phone_otp",
      body.userAgreement.version,
      getLegalAcceptanceRequestMeta(request)
    );
    const sessionToken = await createSession(userWithAgreement.id);
    await prisma.user.update({ where: { id: userWithAgreement.id }, data: { lastActiveAt: new Date() } });

    return ok({
      ok: true,
      user: {
        id: userWithAgreement.id,
        email: userWithAgreement.email,
        phone: userWithAgreement.phone,
        onboardingCompleted: userWithAgreement.onboardingCompleted,
        showOnMap: userWithAgreement.showOnMap === true
      },
      sessionToken
    });
  } catch (error) {
    return phoneAuthFailure(error, locale, phone);
  }
}
