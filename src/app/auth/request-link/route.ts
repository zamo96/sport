import { NextRequest } from "next/server";

import { createAuthCode, isAppReviewDemoEmail } from "@/lib/auth";
import { sendOtpEmail } from "@/lib/email";
import { fail, ok } from "@/lib/http";
import { resolveLocalizedAuthError } from "@/lib/i18n/server/auth-errors";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { translateServer } from "@/lib/i18n/server";
import { prisma } from "@/lib/prisma";
import { requestLinkSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  try {
    const body = requestLinkSchema.parse(await request.json());
    if (isAppReviewDemoEmail(body.email)) {
      return ok({
        ok: true,
        message: translateServer(locale, "auth.request.demo")
      });
    }

    const existingUser = await prisma.user.findUnique({
      where: { email: body.email }
    });
    const code = await createAuthCode(body.email, existingUser?.id);

    await sendOtpEmail({ to: body.email, code, locale });

    return ok({
      ok: true,
      message: translateServer(locale, "auth.request.sent"),
      debugCode: process.env.NODE_ENV !== "production" ? code : undefined
    });
  } catch (error) {
    const localizedError = resolveLocalizedAuthError(error, locale);
    return fail(localizedError.message, localizedError.status, localizedError.errorCode);
  }
}
