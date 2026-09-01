import { NextRequest } from "next/server";
import { z } from "zod";

import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { LOCALE_COOKIE_NAME, resolveRequestLocale } from "@/lib/locales";
import { prisma } from "@/lib/prisma";

const localeOverrideSchema = z.object({
  localeOverride: z.enum(["en", "ru"]).nullable()
});

export async function PATCH(request: NextRequest) {
  try {
    const currentUser = await requireSessionUser();
    const { localeOverride } = localeOverrideSchema.parse(await request.json());
    await prisma.user.update({
      where: { id: currentUser.id },
      data: { localeOverride }
    });
    const effectiveLocale = localeOverride ?? resolveRequestLocale({
      acceptLanguage: request.headers.get("accept-language")
    });

    const response = ok({ localeOverride, effectiveLocale });
    if (localeOverride) {
      response.cookies.set(LOCALE_COOKIE_NAME, localeOverride, {
        httpOnly: false,
        maxAge: 365 * 24 * 60 * 60,
        path: "/",
        sameSite: "lax",
        secure: process.env.NODE_ENV === "production"
      });
    } else {
      response.cookies.delete(LOCALE_COOKIE_NAME);
    }

    return response;
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Authentication required", 401);
    }

    return fail(getErrorMessage(error));
  }
}
