import { createPublicKey, verify as verifySignature, type JsonWebKey as CryptoJsonWebKey } from "crypto";
import { cookies } from "next/headers";
import { ZodError, z } from "zod";

import { getErrorMessage } from "@/lib/http";
import { translateServer } from "@/lib/i18n/server";
import { resolveLocalizedAuthError, type AuthErrorCode } from "@/lib/i18n/server/auth-errors";
import { attributeInvite, INVITE_COOKIE_NAME } from "@/lib/invites";
import { ACCEPTED_USER_AGREEMENT_VERSIONS, LEGAL_ACCEPTANCE_ERROR } from "@/lib/legal-contract";
import type { SupportedLocale } from "@/lib/locales";
import { prisma } from "@/lib/prisma";
import { initialProfileVisibility } from "@/lib/profile-visibility";
import { recordUserEventsOnce } from "@/server/user-events";

/**
 * Sign in with Google, the Android counterpart of Sign in with Apple.
 *
 * The app obtains an ID token through Credential Manager and posts it here; the
 * server checks it against Google's published keys, so a client cannot claim an
 * identity it does not hold. Account linking follows the Apple flow exactly:
 * the Google subject first, then a verified email, then a new account.
 */

const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const GOOGLE_ISSUERS = new Set(["accounts.google.com", "https://accounts.google.com"]);
const GOOGLE_JWKS_CACHE_TTL_MS = 60 * 60 * 1000;

export const GOOGLE_EMAIL_REQUIRED_ERROR = "Google не передал подтверждённый email для нового аккаунта";
const GOOGLE_PROVIDER_UNAVAILABLE_ERRORS = new Set([
  "Не удалось получить ключи Google для входа",
  "Google не вернул ключи для проверки ID token",
  "Вход через Google не настроен на сервере"
]);

type GoogleJwk = CryptoJsonWebKey & { kid?: string; alg?: string };

type GoogleIdTokenHeader = { kid?: string; alg?: string };

type GoogleIdTokenPayload = {
  iss?: string;
  aud?: string | string[];
  azp?: string;
  sub?: string;
  exp?: number;
  email?: string;
  email_verified?: boolean | string;
  name?: string;
};

let googleJwksCache: { keys: GoogleJwk[]; expiresAt: number } | null = null;

/** Exported for tests, so one case's keys never leak into the next. */
export function resetGoogleJwksCache() {
  googleJwksCache = null;
}

const userAgreementAcceptanceSchema = z.object({
  accepted: z.boolean().refine((value) => value, LEGAL_ACCEPTANCE_ERROR),
  version: z.preprocess(
    (value) => (typeof value === "string" ? value.trim() : ""),
    z.enum(ACCEPTED_USER_AGREEMENT_VERSIONS, "Нужно принять актуальную редакцию пользовательского соглашения")
  )
});

export const googleAuthSchema = z.object({
  showOnMap: z.boolean().optional(),
  consentReview: z.boolean().optional(),
  idToken: z.string().min(1),
  userAgreement: userAgreementAcceptanceSchema
});

function base64UrlToBuffer(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4 || 4)) % 4);
  return Buffer.from(padded, "base64");
}

function parseTokenPart<T>(value: string) {
  return JSON.parse(base64UrlToBuffer(value).toString("utf8")) as T;
}

/**
 * The OAuth client IDs whose tokens this server accepts. With Credential
 * Manager the ID token's audience is the *web* client ID the app passes as
 * `serverClientId`, not the Android client, so that is the value to list.
 */
function resolveGoogleAudiences() {
  return Array.from(
    new Set(
      (process.env.GOOGLE_CLIENT_IDS ?? process.env.GOOGLE_CLIENT_ID ?? "")
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean)
    )
  );
}

async function getGoogleJwks() {
  if (googleJwksCache && googleJwksCache.expiresAt > Date.now()) {
    return googleJwksCache.keys;
  }

  const response = await fetch(GOOGLE_JWKS_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error("Не удалось получить ключи Google для входа");
  }

  const payload = (await response.json()) as { keys?: GoogleJwk[] };
  const keys = payload.keys ?? [];
  if (!keys.length) {
    throw new Error("Google не вернул ключи для проверки ID token");
  }

  googleJwksCache = { keys, expiresAt: Date.now() + GOOGLE_JWKS_CACHE_TTL_MS };
  return keys;
}

export async function verifyGoogleIdToken(idToken: string) {
  const audiences = resolveGoogleAudiences();
  if (!audiences.length) {
    throw new Error("Вход через Google не настроен на сервере");
  }

  const segments = idToken.split(".");
  if (segments.length !== 3) {
    throw new Error("Некорректный Google ID token");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = segments;
  const header = parseTokenPart<GoogleIdTokenHeader>(encodedHeader);
  if (!header.kid || header.alg !== "RS256") {
    throw new Error("Google ID token использует неподдерживаемый алгоритм");
  }

  const keys = await getGoogleJwks();
  const jwk = keys.find((item) => item.kid === header.kid);
  if (!jwk) {
    throw new Error("Не найден ключ Google для проверки ID token");
  }

  const isValidSignature = verifySignature(
    "RSA-SHA256",
    Buffer.from(`${encodedHeader}.${encodedPayload}`),
    createPublicKey({ key: jwk, format: "jwk" }),
    base64UrlToBuffer(encodedSignature)
  );
  if (!isValidSignature) {
    throw new Error("Google ID token не прошёл проверку подписи");
  }

  const payload = parseTokenPart<GoogleIdTokenPayload>(encodedPayload);
  const tokenAudiences = Array.isArray(payload.aud) ? payload.aud : payload.aud ? [payload.aud] : [];

  if (!payload.iss || !GOOGLE_ISSUERS.has(payload.iss)) {
    throw new Error("Google ID token выпущен неизвестным issuer");
  }
  if (!payload.exp || payload.exp <= Math.floor(Date.now() / 1000)) {
    throw new Error("Google ID token просрочен");
  }
  if (!payload.sub) {
    throw new Error("Google ID token не содержит идентификатор пользователя");
  }
  if (!tokenAudiences.some((audience) => audiences.includes(audience))) {
    throw new Error("Google ID token выпущен не для этого приложения");
  }

  return payload;
}

/** Same as the private helper in lib/auth: a failed attribution never blocks sign-up. */
async function attributeInviteFromCookie(userId: string) {
  try {
    await attributeInvite(userId, cookies().get(INVITE_COOKIE_NAME)?.value ?? null);
  } catch (error) {
    console.error("invite attribution failed", { userId, error });
  }
}

export async function signInWithGoogleIdToken(idToken: string, options?: { showOnMap?: boolean; consentReview?: boolean }) {
  const payload = await verifyGoogleIdToken(idToken);
  const googleSubject = payload.sub!;
  // Only a verified address may match an existing account; otherwise anyone
  // could create a Google account with someone else's email and take theirs.
  const emailVerified = payload.email_verified === true || payload.email_verified === "true";
  const email = emailVerified && typeof payload.email === "string" ? payload.email.trim().toLowerCase() : undefined;
  const displayName = payload.name?.trim() || undefined;

  let user = await prisma.user.findUnique({ where: { googleSubject } });

  if (!user && email) {
    user = await prisma.user.findUnique({ where: { email } });
  }

  if (!user) {
    if (!email) {
      throw new Error(GOOGLE_EMAIL_REQUIRED_ERROR);
    }

    user = await prisma.user.create({
      data: {
        email,
        showOnMap: options?.showOnMap ?? true,
        profileVisibility: initialProfileVisibility(options?.consentReview),
        googleSubject,
        name: displayName,
        isVerified: true
      }
    });
    await recordUserEventsOnce([
      { userId: user.id, type: "registration_completed", entityType: "user", entityId: user.id, context: { method: "google" } }
    ]);
    await attributeInviteFromCookie(user.id);
    return user;
  }

  if (user.googleSubject && user.googleSubject !== googleSubject) {
    throw new Error("Google ID token не соответствует привязанному аккаунту");
  }

  if (!user.googleSubject) {
    const linked = await prisma.user.updateMany({
      where: { id: user.id, googleSubject: null },
      data: { googleSubject }
    });
    if (linked.count !== 1) {
      throw new Error("Google ID token не соответствует привязанному аккаунту");
    }
    user = { ...user, googleSubject };
  }

  const nextData: { isVerified?: boolean; name?: string } = {};
  if (!user.isVerified) nextData.isVerified = true;
  if (!user.name && displayName) nextData.name = displayName;

  if (Object.keys(nextData).length > 0) {
    user = await prisma.user.update({ where: { id: user.id }, data: nextData });
  }

  return user;
}

export type GoogleAuthPhase = "request" | "google" | "session";

export function resolveLocalizedGoogleAuthError(
  error: unknown,
  locale: SupportedLocale,
  phase: GoogleAuthPhase
): { message: string; status: number; errorCode: AuthErrorCode | "AUTH_GOOGLE_EMAIL_REQUIRED" | "AUTH_GOOGLE_INVALID_TOKEN" | "AUTH_GOOGLE_UNAVAILABLE" } {
  const rawMessage = getErrorMessage(error);
  if (rawMessage === "ACCOUNT_DEACTIVATED" || phase !== "google" || error instanceof ZodError) {
    return resolveLocalizedAuthError(error, locale);
  }

  if (rawMessage === GOOGLE_EMAIL_REQUIRED_ERROR) {
    return {
      message: translateServer(locale, "auth.error.googleEmailRequired"),
      status: 422,
      errorCode: "AUTH_GOOGLE_EMAIL_REQUIRED"
    };
  }

  if (GOOGLE_PROVIDER_UNAVAILABLE_ERRORS.has(rawMessage)) {
    return {
      message: translateServer(locale, "auth.error.googleUnavailable"),
      status: 503,
      errorCode: "AUTH_GOOGLE_UNAVAILABLE"
    };
  }

  return {
    message: translateServer(locale, "auth.error.googleInvalid"),
    status: 401,
    errorCode: "AUTH_GOOGLE_INVALID_TOKEN"
  };
}
