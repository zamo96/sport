import { NextRequest } from "next/server";

import { createSession, getLegalAcceptanceRequestMeta, recordUserAgreementAcceptance, verifyAuthCode } from "@/lib/auth";
import { fail, ok } from "@/lib/http";
import { resolveLocalizedAuthError } from "@/lib/i18n/server/auth-errors";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { translateServer } from "@/lib/i18n/server";
import { prisma } from "@/lib/prisma";
import { verifySchema } from "@/lib/validators";
import { enforceAuthRateLimit } from "@/server/auth-rate-limit";

export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  try {
    const body = verifySchema.parse(await request.json());
    await enforceAuthRateLimit("verify", body.email, request);
    const user = await verifyAuthCode(body.email, body.code, body.showOnMap);

    if (!user) {
      return fail(translateServer(locale, "auth.error.invalidCode"), 401, "AUTH_INVALID_CODE");
    }

    const userWithAgreement = await recordUserAgreementAcceptance(
      user.id,
      "email_otp",
      body.userAgreement.version,
      getLegalAcceptanceRequestMeta(request)
    );
    const sessionToken = await createSession(userWithAgreement.id);
    await prisma.user.update({
      where: { id: userWithAgreement.id },
      data: {
        lastActiveAt: new Date()
      }
    });

    return ok({
      ok: true,
      user: {
        id: userWithAgreement.id,
        email: userWithAgreement.email,
        onboardingCompleted: userWithAgreement.onboardingCompleted,
        showOnMap: userWithAgreement.showOnMap === true
      },
      sessionToken
    });
  } catch (error) {
    const localizedError = resolveLocalizedAuthError(error, locale);
    return fail(localizedError.message, localizedError.status, localizedError.errorCode);
  }
}
