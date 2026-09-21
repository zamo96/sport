import { NextRequest } from "next/server";

import { createSession, getLegalAcceptanceRequestMeta, recordUserAgreementAcceptance } from "@/lib/auth";
import {
  googleAuthSchema,
  resolveLocalizedGoogleAuthError,
  signInWithGoogleIdToken,
  type GoogleAuthPhase
} from "@/lib/google-auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { prisma } from "@/lib/prisma";

/** Sign in with Google. Same response shape as /auth/apple and /auth/verify. */
export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  let phase: GoogleAuthPhase = "request";
  try {
    const body = googleAuthSchema.parse(await request.json());
    phase = "google";
    const user = await signInWithGoogleIdToken(body.idToken, { showOnMap: body.showOnMap });
    phase = "session";

    const userWithAgreement = await recordUserAgreementAcceptance(
      user.id,
      "google",
      body.userAgreement.version,
      getLegalAcceptanceRequestMeta(request)
    );
    const sessionToken = await createSession(userWithAgreement.id);
    await prisma.user.update({
      where: { id: userWithAgreement.id },
      data: { lastActiveAt: new Date() }
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
    console.warn("[auth/google] rejected Google sign-in:", getErrorMessage(error));
    const localizedError = resolveLocalizedGoogleAuthError(error, locale, phase);
    return fail(localizedError.message, localizedError.status, localizedError.errorCode);
  }
}
