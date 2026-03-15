import { randomInt, randomUUID } from "crypto";

import { cookies } from "next/headers";

import { AUTH_CODE_TTL_MINUTES, SESSION_COOKIE, SESSION_TTL_DAYS } from "@/lib/constants";
import { prisma } from "@/lib/prisma";

function sessionExpiresAt() {
  return new Date(Date.now() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
}

function authCodeExpiresAt() {
  return new Date(Date.now() + AUTH_CODE_TTL_MINUTES * 60 * 1000);
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

export async function getSessionUser() {
  const token = cookies().get(SESSION_COOKIE)?.value;

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
