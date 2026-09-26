import { recordUserEventsOnce } from "@/server/user-events";
import { AccountStatus, Gender, PlayFormat, Prisma, Sport, Surface } from "@prisma/client";
import { createPublicKey, randomInt, randomUUID, verify as verifySignature, type JsonWebKey as CryptoJsonWebKey } from "crypto";

import { cookies, headers } from "next/headers";

import { AUTH_CODE_TTL_MINUTES, SESSION_COOKIE, SESSION_TTL_DAYS } from "@/lib/constants";
import {
  buildUserAgreementAcceptanceRecord,
  type AcceptedUserAgreementVersion,
  type LegalAcceptanceSource
} from "@/lib/legal-contract";
import { attributeInvite, INVITE_COOKIE_NAME } from "@/lib/invites";
import { prisma } from "@/lib/prisma";
import { initialProfileVisibility } from "@/lib/profile-visibility";

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
  showOnMap?: boolean;
  consentReview?: boolean;
  email?: string;
  givenName?: string;
  familyName?: string;
};

const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISSUER = "https://appleid.apple.com";
const DEFAULT_APPLE_AUDIENCE = "shop.sportsearch.app";
const APPLE_JWKS_CACHE_TTL_MS = 60 * 60 * 1000;
const LOCAL_APP_REVIEW_DEMO_EMAIL = "review@sportsearch.shop";
const LOCAL_APP_REVIEW_DEMO_CODE = "000000";

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

function getAppReviewDemoCredentials() {
  const allowLocalFallback = process.env.NODE_ENV !== "production";
  const email = (process.env.APP_REVIEW_DEMO_EMAIL ?? (allowLocalFallback ? LOCAL_APP_REVIEW_DEMO_EMAIL : ""))
    .trim()
    .toLowerCase();
  const code = (process.env.APP_REVIEW_DEMO_CODE ?? (allowLocalFallback ? LOCAL_APP_REVIEW_DEMO_CODE : "")).trim();

  if (!email || !code || !/^\d{6}$/.test(code)) {
    return null;
  }

  return { email, code };
}

export function isAppReviewDemoEmail(email: string) {
  const credentials = getAppReviewDemoCredentials();
  return credentials?.email === email.trim().toLowerCase();
}

async function ensureAppReviewDemoUser(email: string, showOnMap = true) {
  return prisma.user.upsert({
    where: { email },
    update: {
      name: "Apple Review",
      age: 29,
      gender: Gender.other,
      city: "Санкт-Петербург",
      district: null,
      preferredDistricts: ["petrogradsky", "primorsky"],
      preferredSports: [Sport.tennis, Sport.padel, Sport.football],
      sportLevels: {
        [Sport.tennis]: 5,
        [Sport.padel]: 5,
        [Sport.football]: 5
      },
      preferredPlayFormat: PlayFormat.both,
      preferredSurface: Surface.any,
      availableDays: ["monday", "wednesday", "saturday"],
      availableTimeRanges: ["evening", "day"],
      availabilityByDay: {
        monday: ["evening"],
        wednesday: ["evening"],
        saturday: ["day"]
      },
      isLookingForGame: true,
      isVerified: true,
      onboardingCompleted: true,
      notificationMatches: true,
      notificationMessages: true,
      notificationGames: true,
      notificationSound: true,
      lastActiveAt: new Date()
    },
    create: {
      email,
      showOnMap,
      name: "Apple Review",
      age: 29,
      gender: Gender.other,
      city: "Санкт-Петербург",
      district: null,
      preferredDistricts: ["petrogradsky", "primorsky"],
      preferredSports: [Sport.tennis, Sport.padel, Sport.football],
      sportLevels: {
        [Sport.tennis]: 5,
        [Sport.padel]: 5,
        [Sport.football]: 5
      },
      preferredPlayFormat: PlayFormat.both,
      preferredSurface: Surface.any,
      availableDays: ["monday", "wednesday", "saturday"],
      availableTimeRanges: ["evening", "day"],
      availabilityByDay: {
        monday: ["evening"],
        wednesday: ["evening"],
        saturday: ["day"]
      },
      isLookingForGame: true,
      isVerified: true,
      onboardingCompleted: true,
      notificationMatches: true,
      notificationMessages: true,
      notificationGames: true,
      notificationSound: true,
      lastActiveAt: new Date()
    }
  });
}

export function getLegalAcceptanceRequestMeta(request: Request) {
  const forwardedFor = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const realIp = request.headers.get("x-real-ip")?.trim();

  return {
    ip: forwardedFor || realIp || null,
    userAgent: request.headers.get("user-agent")?.trim() || null
  };
}

export async function recordUserAgreementAcceptance(
  userId: string,
  source: LegalAcceptanceSource,
  agreementVersion: AcceptedUserAgreementVersion,
  meta?: { ip?: string | null; userAgent?: string | null }
) {
  await prisma.userAgreementAcceptance.createMany({
    data: [
      buildUserAgreementAcceptanceRecord({
        userId,
        source,
        agreementVersion,
        ip: meta?.ip,
        userAgent: meta?.userAgent
      })
    ],
    skipDuplicates: true
  });

  // Версии — даты ISO: старая сборка, принявшая прежнюю редакцию, не откатывает более новую.
  await prisma.user.updateMany({
    where: {
      id: userId,
      OR: [{ agreementVersion: null }, { agreementVersion: { lt: agreementVersion } }]
    },
    data: { agreementVersion }
  });

  return prisma.user.findUniqueOrThrow({
    where: { id: userId }
  });
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

export async function verifyAuthCode(email: string, code: string, showOnMap = true, consentReview?: boolean) {
  const demoCredentials = getAppReviewDemoCredentials();
  if (demoCredentials?.email === email.trim().toLowerCase() && demoCredentials.code === code.trim()) {
    return ensureAppReviewDemoUser(demoCredentials.email, showOnMap);
  }

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

  const consumed = await prisma.authCode.updateMany({
    where: { id: authCode.id, consumedAt: null, expiresAt: { gt: new Date() } },
    data: { consumedAt: new Date() }
  });

  if (consumed.count !== 1) {
    return null;
  }

  let user = authCode.userId
    ? await prisma.user.findUnique({ where: { id: authCode.userId } })
    : await prisma.user.findUnique({ where: { email } });

  if (!user) {
    user = await prisma.user.create({
      data: {
        email,
        showOnMap,
        profileVisibility: initialProfileVisibility(consentReview),
        isVerified: true
      }
    });
    await recordUserEventsOnce([{ userId: user.id, type: "registration_completed", entityType: "user", entityId: user.id, context: { method: "email" } }]);
    await attributeInviteFromCookie(user.id);
  } else if (!user.isVerified) {
    user = await prisma.user.update({
      where: { id: user.id },
      data: { isVerified: true }
    });
  }

  return user;
}

/**
 * Пришёл ли человек по чужой ссылке. Ошибку глотаем намеренно: приглашение —
 * приятный бонус, из-за него регистрация падать не должна.
 */
export async function attributeInviteFromCookie(userId: string) {
  try {
    await attributeInvite(userId, cookies().get(INVITE_COOKIE_NAME)?.value ?? null);
  } catch (error) {
    console.error("invite attribution failed", { userId, error });
  }
}

export async function signInWithAppleIdentityToken(identityToken: string, profile?: AppleAuthProfile) {
  const payload = await verifyAppleIdentityToken(identityToken);
  const appleSubject = payload.sub!;
  // Client-supplied profile fields are not proof of ownership of an email address.
  const emailVerified = payload.email_verified === true || payload.email_verified === "true";
  const email = emailVerified && typeof payload.email === "string" ? payload.email.trim().toLowerCase() : undefined;
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
        showOnMap: profile?.showOnMap ?? true,
        profileVisibility: initialProfileVisibility(profile?.consentReview),
        appleSubject,
        name: displayName,
        isVerified: true
      }
    });
    await recordUserEventsOnce([{ userId: user.id, type: "registration_completed", entityType: "user", entityId: user.id, context: { method: "apple" } }]);
    await attributeInviteFromCookie(user.id);
  } else {
    if (user.appleSubject && user.appleSubject !== appleSubject) {
      throw new Error("Apple identity token не соответствует привязанному аккаунту");
    }

    if (!user.appleSubject) {
      const linked = await prisma.user.updateMany({
        where: { id: user.id, appleSubject: null },
        data: { appleSubject }
      });
      if (linked.count !== 1) {
        throw new Error("Apple identity token не соответствует привязанному аккаунту");
      }
      user = { ...user, appleSubject };
    }

    const nextData: {
      isVerified?: boolean;
      name?: string;
    } = {};

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
  const expiresAt = sessionExpiresAt();

  await prisma.$transaction(async (tx) => {
    const activeUsers = await tx.$queryRaw<Array<{ id: string }>>(Prisma.sql`
      SELECT "id"
      FROM "User"
      WHERE "id" = ${userId} AND "accountStatus" = 'active'
      FOR UPDATE
    `);

    if (activeUsers.length !== 1) {
      throw new Error("ACCOUNT_DEACTIVATED");
    }

    await tx.session.create({
      data: {
        userId,
        token,
        expiresAt
      }
    });
  });

  cookies().set(SESSION_COOKIE, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    expires: expiresAt,
    path: "/"
  });

  return token;
}

export async function destroySession(pushDeviceToken?: string) {
  const token = getRequestSessionToken();

  if (token) {
    await prisma.$transaction(async (tx) => {
      // Registration locks this same row before writing a push device. Once logout
      // wins the lock and removes the row, an old registration cannot reactivate it.
      const [session] = await tx.$queryRaw<Array<{ userId: string }>>(Prisma.sql`
        SELECT "userId" FROM "Session" WHERE "token" = ${token} FOR UPDATE
      `);
      if (session && pushDeviceToken) {
        await tx.pushDevice.updateMany({
          where: { token: pushDeviceToken, userId: session.userId, platform: "ios" },
          data: { isActive: false }
        });
      }
      await tx.session.deleteMany({ where: { token } });
    });
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

export function getRequestSessionToken() {
  return getBearerSessionToken() ?? cookies().get(SESSION_COOKIE)?.value;
}

export async function getSessionUser() {
  const token = getRequestSessionToken();

  if (!token) {
    return null;
  }

  const session = await prisma.session.findUnique({
    where: { token },
    include: { user: true }
  });

  if (!session || session.expiresAt < new Date() || session.user.accountStatus !== AccountStatus.active) {
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
