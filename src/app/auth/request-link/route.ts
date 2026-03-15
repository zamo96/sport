import { NextRequest } from "next/server";

import { createAuthCode } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";
import { requestLinkSchema } from "@/lib/validators";

export async function POST(request: NextRequest) {
  try {
    const body = requestLinkSchema.parse(await request.json());
    const existingUser = await prisma.user.findUnique({
      where: { email: body.email }
    });
    const code = await createAuthCode(body.email, existingUser?.id);

    console.log(`[auth] OTP for ${body.email}: ${code}`);

    return ok({
      ok: true,
      message: "Код подтверждения отправлен",
      debugCode: process.env.NODE_ENV !== "production" ? code : undefined
    });
  } catch (error) {
    return fail(getErrorMessage(error));
  }
}
