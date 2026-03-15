import { NextRequest } from "next/server";

import { createSession, verifyAuthCode } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { verifySchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const body = verifySchema.parse(await request.json());
    const user = await verifyAuthCode(body.email, body.code);

    if (!user) {
      return fail("Неверный или просроченный код", 401);
    }

    await createSession(user.id);

    return ok({
      ok: true,
      user: {
        id: user.id,
        email: user.email,
        onboardingCompleted: user.onboardingCompleted
      }
    });
  } catch (error) {
    return fail(getErrorMessage(error));
  }
}
