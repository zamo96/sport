import { NextRequest } from "next/server";

import { createSession, getLegalAcceptanceRequestMeta, recordUserAgreementAcceptance } from "@/lib/auth";
import { ok } from "@/lib/http";
import { getServerRequestLocale } from "@/lib/i18n/server/request-locale";
import { prisma } from "@/lib/prisma";
import { vkAuthSchema } from "@/lib/validators";
import { enforceAuthRateLimit } from "@/server/auth-rate-limit";
import { phoneAuthFailure } from "@/server/phone-auth-http";
import { fetchVkProfile, signInWithVk } from "@/server/vk-auth";

/**
 * Вход через VK ID. Клиент сам проходит авторизацию в VK с PKCE и присылает код,
 * code_verifier и device_id; сервер меняет их на данные пользователя.
 */
export async function POST(request: NextRequest) {
  const locale = getServerRequestLocale(request);
  try {
    const body = vkAuthSchema.parse(await request.json());
    await enforceAuthRateLimit("vk", "vk", request);
    const profile = await fetchVkProfile(body);
    const user = await signInWithVk(profile, { showOnMap: body.showOnMap, consentReview: body.consentReview });
    const userWithAgreement = await recordUserAgreementAcceptance(
      user.id,
      "vk",
      body.userAgreement.version,
      getLegalAcceptanceRequestMeta(request)
    );
    const sessionToken = await createSession(userWithAgreement.id);
    await prisma.user.update({ where: { id: userWithAgreement.id }, data: { lastActiveAt: new Date() } });

    return ok({
      ok: true,
      user: {
        id: userWithAgreement.id,
        email: userWithAgreement.email,
        phone: userWithAgreement.phone,
        onboardingCompleted: userWithAgreement.onboardingCompleted,
        showOnMap: userWithAgreement.showOnMap === true
      },
      sessionToken
    });
  } catch (error) {
    return phoneAuthFailure(error, locale);
  }
}
