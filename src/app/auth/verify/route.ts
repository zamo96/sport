import { NextRequest } from "next/server";

import { createSession, getLegalAcceptanceRequestMeta, recordUserAgreementAcceptance, verifyAuthCode } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { verifySchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const body = verifySchema.parse(await request.json());
    const user = await verifyAuthCode(body.email, body.code);

    if (!user) {
      return fail("Неверный или просроченный код", 401);
    }

    const userWithAgreement = await recordUserAgreementAcceptance(
      user.id,
      "email_otp",
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
    return message === "ACCOUNT_DEACTIVATED" ? fail("Аккаунт деактивирован", 403) : fail(message);
  }
}
