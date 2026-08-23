import { NextRequest } from "next/server";

import { createAuthCode, isAppReviewDemoEmail } from "@/lib/auth";
import { sendOtpEmail } from "@/lib/email";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { requestLinkSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const body = requestLinkSchema.parse(await request.json());
    if (isAppReviewDemoEmail(body.email)) {
      return ok({
        ok: true,
        message: "Для проверки Apple используйте demo-код из App Review Information."
      });
    }

    const existingUser = await prisma.user.findUnique({
      where: { email: body.email }
    });
    const code = await createAuthCode(body.email, existingUser?.id);

    await sendOtpEmail({ to: body.email, code });

    return ok({
      ok: true,
      message: "Код подтверждения отправлен",
      debugCode: process.env.NODE_ENV !== "production" ? code : undefined
    });
  } catch (error) {
    return fail(getErrorMessage(error));
  }
}
