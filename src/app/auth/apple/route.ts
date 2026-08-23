import { NextRequest } from "next/server";

import {
  createSession,
  getLegalAcceptanceRequestMeta,
  recordUserAgreementAcceptance,
  signInWithAppleIdentityToken
} from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { appleAuthSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const body = appleAuthSchema.parse(await request.json());
    const user = await signInWithAppleIdentityToken(body.identityToken, {
      email: body.email,
      givenName: body.givenName,
      familyName: body.familyName
    });

    const userWithAgreement = await recordUserAgreementAcceptance(
      user.id,
      "apple",
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
    return fail(message === "ACCOUNT_DEACTIVATED" ? "Аккаунт деактивирован" : message, message === "ACCOUNT_DEACTIVATED" ? 403 : 401);
  }
}
