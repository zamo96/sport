import { createPublicKey, randomInt, randomUUID, verify as verifySignature, type JsonWebKey as CryptoJsonWebKey } from "crypto";

import { cookies, headers } from "next/headers";

import { AUTH_CODE_TTL_MINUTES, SESSION_COOKIE, SESSION_TTL_DAYS } from "@/lib/constants";
import { prisma } from "@/lib/prisma";

type AppleIdentityTokenHeader = {
  alg?: string;
  kid?: string;
};

type AppleIdentityTokenPayload = {
  iss?: string;
  aud?: string | string[];
  exp?: number;
  iat?: number;
  sub?: string;
  email?: string;
  email_verified?: boolean | string;
};

type AppleJwk = CryptoJsonWebKey & {
  kid?: string;
  alg?: string;
  use?: string;
};

type AppleAuthProfile = {
  email?: string;
  givenName?: string;
  familyName?: string;
};

const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";
const DEFAULT_APPLE_AUDIENCE = "shop.sportsearch.app";
const APPLE_JWKS_CACHE_TTL_MS = 60 * 60 * 1000;

let appleJwksCache: { keys: AppleJwk[]; expiresAt: number } | null = null;

function sessionExpiresAt() {
  return new Date(Date.now() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
}

function authCodeExpiresAt() {
  return new Date(Date.now() + AUTH_CODE_TTL_MINUTES * 60 * 1000);
}

function base64UrlToBuffer(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4 || 4)) % 4);
  return Buffer.from(padded, "base64");
}

function parseTokenPart<T>(value: string) {
  return JSON.parse(base64UrlToBuffer(value).toString("utf8")) as T;
}

function resolveAppleAudiences() {
  const configured = process.env.APPLE_CLIENT_IDS ?? process.env.APPLE_CLIENT_ID ?? process.env.APPLE_IOS_BUNDLE_ID;
  const values = configured
    ?.split(",")
    .map((item) => item.trim())
    .filter(Boolean) ?? [DEFAULT_APPLE_AUDIENCE];

  return Array.from(new Set(values));
}

async function getAppleJwks() {
  if (appleJwksCache && appleJwksCache.expiresAt > Date.now()) {
    return appleJwksCache.keys;
  }

  const response = await fetch(APPLE_JWKS_URL, {
    cache: "no-store"
  });

  if (!response.ok) {
    throw new Error("Не удалось получить ключи Apple для входа");
  }

  const payload = (await response.json()) as { keys?: AppleJwk[] };
  const keys = payload.keys ?? [];

  if (!keys.length) {
    throw new Error("Apple не вернул ключи для проверки identity token");
  }

  appleJwksCache = {
    keys,
    expiresAt: Date.now() + APPLE_JWKS_CACHE_TTL_MS
  };

  return keys;
}

async function verifyAppleIdentityToken(identityToken: string) {
  const segments = identityToken.split(".");

  if (segments.length !== 3) {
    throw new Error("Некорректный Apple identity token");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = segments;
  const header = parseTokenPart<AppleIdentityTokenHeader>(encodedHeader);

  if (!header.kid || (header.alg !== "RS256" && header.alg !== "ES256")) {
    throw new Error("Apple identity token использует неподдерживаемый алгоритм");
  }

  const keys = await getAppleJwks();
  const jwk = keys.find((item) => item.kid === header.kid);

  if (!jwk) {
    throw new Error("Не найден ключ Apple для проверки identity token");
  }

  const signingInput = Buffer.from(`${encodedHeader}.${encodedPayload}`);
  const signature = base64UrlToBuffer(encodedSignature);
  const publicKey = createPublicKey({
    key: jwk as CryptoJsonWebKey,
    format: "jwk"
  });

  const isValidSignature =
    header.alg === "RS256"
      ? verifySignature("RSA-SHA256", signingInput, publicKey, signature)
      : verifySignature(
          "sha256",
          signingInput,
          {
            key: publicKey,
            dsaEncoding: "ieee-p1363"
          },
          signature
        );

  if (!isValidSignature) {
    throw new Error("Apple identity token не прошёл проверку подписи");
  }

  const payload = parseTokenPart<AppleIdentityTokenPayload>(encodedPayload);
  const now = Math.floor(Date.now() / 1000);
  const audiences = resolveAppleAudiences();
  const tokenAudiences = Array.isArray(payload.aud) ? payload.aud : payload.aud ? [payload.aud] : [];

  if (payload.iss !== APPLE_ISSUER) {
    throw new Error("Apple identity token выпущен неизвестным issuer");
  }

  if (!payload.exp || payload.exp <= now) {
    throw new Error("Apple identity token просрочен");
  }

  if (!payload.sub) {
    throw new Error("Apple identity token не содержит идентификатор пользователя");
  }

  if (!tokenAudiences.some((audience) => audiences.includes(audience))) {
    throw new Error("Apple identity token выпущен не для этого приложения");
  }

  return payload;
}

function buildAppleDisplayName(profile?: AppleAuthProfile) {
  const parts = [profile?.givenName?.trim(), profile?.familyName?.trim()].filter(Boolean);
  return parts.length ? parts.join(" ") : undefined;
}

export async function createAuthCode(email: string, userId?: string) {
  const code = String(randomInt(100000, 999999));

  await prisma.authCode.create({
    data: {
      email,
      code,
      expiresAt: authCodeExpiresAt(),
      userId
    }
  });

  return code;
}

export async function verifyAuthCode(email: string, code: string) {
  const authCode = await prisma.authCode.findFirst({
    where: {
      email,
      code,
      consumedAt: null,
      expiresAt: {
        gt: new Date()
      }
    },
    orderBy: {
      createdAt: "desc"
    }
  });

  if (!authCode) {
    return null;
  }

  await prisma.authCode.update({
    where: { id: authCode.id },
    data: { consumedAt: new Date() }
  });

  let user = authCode.userId
    ? await prisma.user.findUnique({ where: { id: authCode.userId } })
    : await prisma.user.findUnique({ where: { email } });

  if (!user) {
    user = await prisma.user.create({
      data: {
        email,
        isVerified: true
      }
    });
  } else if (!user.isVerified) {
    user = await prisma.user.update({
      where: { id: user.id },
      data: { isVerified: true }
    });
  }

  return user;
}

export async function signInWithAppleIdentityToken(identityToken: string, profile?: AppleAuthProfile) {
  const payload = await verifyAppleIdentityToken(identityToken);
  const appleSubject = payload.sub!;
  const tokenEmail = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : undefined;
  const providedEmail = profile?.email?.trim().toLowerCase();
  const email = tokenEmail || providedEmail;
  const displayName = buildAppleDisplayName(profile);

  let user = await prisma.user.findUnique({
    where: { appleSubject }
  });

  if (!user && email) {
    user = await prisma.user.findUnique({
      where: { email }
    });
  }

  if (!user) {
    if (!email) {
      throw new Error("Apple не передал email для нового аккаунта. Попробуй снова или используй вход по email.");
    }

    user = await prisma.user.create({
      data: {
        email,
        appleSubject,
        name: displayName,
        isVerified: true
      }
    });
  } else {
    const nextData: {
      appleSubject?: string;
      isVerified?: boolean;
      name?: string;
    } = {};

    if (!user.appleSubject) {
      nextData.appleSubject = appleSubject;
    }

    if (!user.isVerified) {
      nextData.isVerified = true;
    }

    if (!user.name && displayName) {
      nextData.name = displayName;
    }

    if (Object.keys(nextData).length > 0) {
      user = await prisma.user.update({
        where: { id: user.id },
        data: nextData
      });
    }
  }

  return user;
}

export async function createSession(userId: string) {
  const token = randomUUID();

  await prisma.session.create({
    data: {
      userId,
      token,
      expiresAt: sessionExpiresAt()
    }
  });

  cookies().set(SESSION_COOKIE, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    expires: sessionExpiresAt(),
    path: "/"
  });

  return token;
}

export async function destroySession() {
  const token = cookies().get(SESSION_COOKIE)?.value;

  if (token) {
    await prisma.session.deleteMany({ where: { token } });
  }

  cookies().delete(SESSION_COOKIE);
}

function getBearerSessionToken() {
  const authorization = headers().get("authorization");
  const [scheme, token] = authorization?.split(" ") ?? [];

  if (scheme?.toLowerCase() !== "bearer" || !token?.trim()) {
    return null;
  }

  return token.trim();
}

export async function getSessionUser() {
  const token = cookies().get(SESSION_COOKIE)?.value ?? getBearerSessionToken();

  if (!token) {
    return null;
  }

  const session = await prisma.session.findUnique({
    where: { token },
    include: { user: true }
  });

  if (!session || session.expiresAt < new Date()) {
    return null;
  }

  return session.user;
}

export async function requireSessionUser() {
  const user = await getSessionUser();

  if (!user) {
    throw new Error("UNAUTHORIZED");
  }

  return user;
}
