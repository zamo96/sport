import { NextRequest } from "next/server";

import {
  createSession,
  getLegalAcceptanceRequestMeta,
  recordUserAgreementAcceptance,
  signInWithAppleIdentityToken
} from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import {
  resolveLocalizedAppleAuthError,
  type AppleAuthPhase
} from "@/lib/i18n/server/auth-errors";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { prisma } from "@/lib/prisma";
import { appleAuthSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  let phase: AppleAuthPhase = "request";
  try {
    const body = appleAuthSchema.parse(await request.json());
    phase = "apple";
    const user = await signInWithAppleIdentityToken(body.identityToken, {
      email: body.email,
      givenName: body.givenName,
      familyName: body.familyName
    });
    phase = "session";

    const userWithAgreement = await recordUserAgreementAcceptance(
      user.id,
      "apple",
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
        onboardingCompleted: userWithAgreement.onboardingCompleted
      },
      sessionToken
    });
  } catch (error) {
    const message = getErrorMessage(error);
    console.warn("[auth/apple] rejected Apple sign-in:", message);
    const localizedError = resolveLocalizedAppleAuthError(error, locale, phase);
    return fail(localizedError.message, localizedError.status, localizedError.errorCode);
  }
}
