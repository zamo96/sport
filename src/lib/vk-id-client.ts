"use client";

export type VkIdConfig = {
  available: boolean;
  clientId: string | null;
  redirectUri: string;
  scope: string;
  authorizeUrl: string;
};

type PendingVkSignIn = { codeVerifier: string; state: string; continueHref: string };

const PENDING_KEY = "natrenyu.vkid.pending";

function base64Url(bytes: Uint8Array) {
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomUrlSafe(byteLength: number) {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

async function codeChallenge(verifier: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64Url(new Uint8Array(digest));
}

/**
 * Начинает вход через VK ID (OAuth 2.1 + PKCE): code_verifier остаётся в этой
 * вкладке, VK возвращает на /auth/vk/callback. Префикс state «web_» говорит
 * странице возврата, что вход начат в браузере, а не в приложении.
 */
export async function startVkIdSignIn(config: VkIdConfig, continueHref: string) {
  if (!config.clientId) throw new Error("VK ID не настроен");
  const codeVerifier = randomUrlSafe(48);
  const state = `web_${randomUrlSafe(32)}`;
  const pending: PendingVkSignIn = { codeVerifier, state, continueHref };
  sessionStorage.setItem(PENDING_KEY, JSON.stringify(pending));

  const url = new URL(config.authorizeUrl);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", config.clientId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("state", state);
  url.searchParams.set("code_challenge", await codeChallenge(codeVerifier));
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("scope", config.scope);
  window.location.assign(url.toString());
}

export function takePendingVkSignIn(): PendingVkSignIn | null {
  try {
    const raw = sessionStorage.getItem(PENDING_KEY);
    sessionStorage.removeItem(PENDING_KEY);
    return raw ? (JSON.parse(raw) as PendingVkSignIn) : null;
  } catch {
    return null;
  }
}
