import { attributeInviteFromCookie } from "@/lib/auth";
import { normalizeRussianMobile } from "@/lib/phone";
import { prisma } from "@/lib/prisma";
import { initialProfileVisibility } from "@/lib/profile-visibility";
import { recordUserEventsOnce } from "@/server/user-events";

/** Документация: https://id.vk.ru/about/business/go/docs/ru/vkid/latest/vk-id/connection/api-description */
const VK_ID_BASE_URL = "https://id.vk.ru";
/** Телефон нужен, чтобы тот же человек попадал в один аккаунт и через SMS, и через VK. */
export const VK_ID_SCOPE = "vkid.personal_info phone";

export class VkAuthError extends Error {}

export type VkProfile = {
  userId: string;
  firstName: string | null;
  lastName: string | null;
  /** Российский мобильный номер, подтверждённый VK, или null. */
  phone: string | null;
};

function appOrigin() {
  return (process.env.NEXT_PUBLIC_APP_URL?.trim() || process.env.APP_URL?.trim() || "https://sportsearch.shop").replace(/\/$/, "");
}

/** То, что клиентам нужно для ссылки на VK ID. Без client_id вход через VK скрыт. */
export function vkIdConfig() {
  const clientId = process.env.VK_ID_CLIENT_ID?.trim() || null;
  return {
    available: Boolean(clientId),
    clientId,
    redirectUri: `${appOrigin()}/auth/vk/callback`,
    scope: VK_ID_SCOPE,
    authorizeUrl: `${VK_ID_BASE_URL}/authorize`
  };
}

async function postForm<T>(path: string, params: Record<string, string>) {
  let response: Response;
  try {
    response = await fetch(`${VK_ID_BASE_URL}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(params),
      cache: "no-store"
    });
  } catch (error) {
    console.error("[vk-id] request failed", path, error);
    throw new VkAuthError("VK ID недоступен. Попробуйте ещё раз или войдите по номеру телефона.");
  }
  const payload = (await response.json().catch(() => ({}))) as T & { error?: string; error_description?: string };
  if (!response.ok || payload.error) {
    console.warn("[vk-id] rejected", path, payload.error, payload.error_description);
    throw new VkAuthError("VK ID не подтвердил вход. Попробуйте ещё раз.");
  }
  return payload;
}

/**
 * Обмен кода на токен (OAuth 2.1 + PKCE). code_verifier знает только клиент,
 * который начал вход, поэтому перехваченный код без него бесполезен.
 */
export async function fetchVkProfile(input: { code: string; codeVerifier: string; deviceId: string; state: string }): Promise<VkProfile> {
  const config = vkIdConfig();
  if (!config.clientId) throw new VkAuthError("Вход через VK ID пока не настроен.");

  const tokens = await postForm<{ access_token?: string; user_id?: number | string }>("/oauth2/auth", {
    grant_type: "authorization_code",
    code: input.code,
    code_verifier: input.codeVerifier,
    device_id: input.deviceId,
    state: input.state,
    redirect_uri: config.redirectUri,
    client_id: config.clientId
  });
  if (!tokens.access_token) throw new VkAuthError("VK ID не выдал токен. Попробуйте ещё раз.");

  const info = await postForm<{ user?: { user_id?: number | string; first_name?: string; last_name?: string; phone?: string } }>(
    "/oauth2/user_info",
    { access_token: tokens.access_token, client_id: config.clientId }
  );
  const userId = String(info.user?.user_id ?? tokens.user_id ?? "");
  if (!userId) throw new VkAuthError("VK ID не передал идентификатор пользователя.");

  return {
    userId,
    firstName: info.user?.first_name?.trim() || null,
    lastName: info.user?.last_name?.trim() || null,
    phone: info.user?.phone ? normalizeRussianMobile(info.user.phone) : null
  };
}

/**
 * Находит аккаунт по VK или по подтверждённому VK номеру, иначе создаёт новый.
 * В имя анкеты попадает только имя: фамилия публично не показывается.
 */
export async function signInWithVk(profile: VkProfile, options: { showOnMap?: boolean; consentReview?: boolean } = {}) {
  const byVk = await prisma.user.findUnique({ where: { vkSubject: profile.userId } });
  if (byVk) {
    return prisma.user.update({ where: { id: byVk.id }, data: { isVerified: true, signupCountry: "RU" } });
  }

  if (profile.phone) {
    const byPhone = await prisma.user.findUnique({ where: { phone: profile.phone } });
    if (byPhone) {
      if (byPhone.vkSubject && byPhone.vkSubject !== profile.userId) {
        throw new VkAuthError("Этот номер уже привязан к другому аккаунту VK. Войдите по номеру телефона.");
      }
      return prisma.user.update({
        where: { id: byPhone.id },
        data: { vkSubject: profile.userId, phoneVerifiedAt: new Date(), isVerified: true, signupCountry: "RU" }
      });
    }
  }

  const user = await prisma.user.create({
    data: {
      vkSubject: profile.userId,
      phone: profile.phone,
      phoneVerifiedAt: profile.phone ? new Date() : null,
      name: profile.firstName,
      signupCountry: "RU",
      showOnMap: options.showOnMap ?? true,
      profileVisibility: initialProfileVisibility(options.consentReview),
      isVerified: true
    }
  });
  await recordUserEventsOnce([{ userId: user.id, type: "registration_completed", entityType: "user", entityId: user.id, context: { method: "vk" } }]);
  await attributeInviteFromCookie(user.id);
  return user;
}
