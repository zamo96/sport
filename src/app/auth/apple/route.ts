import { NextRequest } from "next/server";

import { createSession, signInWithAppleIdentityToken } from "@/lib/auth";
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

    const sessionToken = await createSession(user.id);
    await prisma.user.update({
      where: { id: user.id },
      data: {
        lastActiveAt: new Date()
      }
    });

    return ok({
      ok: true,
      user: {
        id: user.id,
        email: user.email,
        onboardingCompleted: user.onboardingCompleted
      },
      sessionToken
    });
  } catch (error) {
    const message = getErrorMessage(error);
    console.warn("[auth/apple] rejected Apple sign-in:", message);
    return fail(message, 401);
  }
}
