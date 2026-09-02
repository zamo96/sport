import { NextRequest, NextResponse } from "next/server";

import { isIPhoneOrIPadUserAgent } from "@/lib/deep-links";
import { APP_STORE_URL } from "@/lib/deep-links";
import { INVITE_COOKIE_MAX_AGE_SECONDS, INVITE_COOKIE_NAME, registerInviteVisit } from "@/lib/invites";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: NextRequest, { params }: { params: { code: string } }) {
  const code = await registerInviteVisit(params.code);
  const userAgent = request.headers.get("user-agent");
  // Битый код не показываем ошибкой: человек ни при чём, просто открываем приложение.
  const target = isIPhoneOrIPadUserAgent(userAgent)
    ? APP_STORE_URL
    : new URL("/onboarding", request.nextUrl.origin).toString();

  const response = NextResponse.redirect(target);

  if (code) {
    response.cookies.set(INVITE_COOKIE_NAME, code, {
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      path: "/",
      maxAge: INVITE_COOKIE_MAX_AGE_SECONDS
    });
  }

  return response;
}
