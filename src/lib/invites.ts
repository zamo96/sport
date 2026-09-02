import { Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";

export const INVITE_COOKIE_NAME = "invite_ref";
/** Приглашение живёт месяц: человек может поставить приложение не сразу. */
export const INVITE_COOKIE_MAX_AGE_SECONDS = 30 * 24 * 60 * 60;

export const INVITE_CODE_LENGTH = 6;
/** Без I, O, 0 и 1 — код диктуют голосом и переписывают от руки. */
const INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const MAX_CODE_ATTEMPTS = 5;

export function generateInviteCode() {
  let code = "";

  for (let index = 0; index < INVITE_CODE_LENGTH; index += 1) {
    code += INVITE_ALPHABET[Math.floor(Math.random() * INVITE_ALPHABET.length)];
  }

  return code;
}

export function normalizeInviteCode(value: unknown) {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim().toUpperCase();

  if (normalized.length !== INVITE_CODE_LENGTH) {
    return null;
  }

  return [...normalized].every((character) => INVITE_ALPHABET.includes(character)) ? normalized : null;
}

/** Код выдаётся по первому обращению, чтобы не тратить его на тех, кто не зовёт. */
export async function ensureInviteCode(userId: string): Promise<string> {
  const existing = await prisma.user.findUnique({
    where: { id: userId },
    select: { inviteCode: true }
  });

  if (existing?.inviteCode) {
    return existing.inviteCode;
  }

  for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt += 1) {
    const code = generateInviteCode();

    try {
      await prisma.user.update({
        where: { id: userId },
        data: { inviteCode: code }
      });

      return code;
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        continue;
      }

      throw error;
    }
  }

  throw new Error("Не удалось выдать код приглашения");
}

export async function registerInviteVisit(code: string) {
  const normalized = normalizeInviteCode(code);

  if (!normalized) {
    return null;
  }

  const inviter = await prisma.user.findUnique({
    where: { inviteCode: normalized },
    select: { id: true, accountStatus: true }
  });

  if (!inviter || inviter.accountStatus !== "active") {
    return null;
  }

  await prisma.user.update({
    where: { id: inviter.id },
    data: { inviteVisits: { increment: 1 } }
  });

  return normalized;
}

/**
 * Отмечает, кто привёл игрока. Вызывается один раз при создании аккаунта:
 * переписать пригласившего задним числом нельзя, иначе счётчики поедут.
 */
export async function attributeInvite(userId: string, code: string | null | undefined) {
  const normalized = normalizeInviteCode(code);

  if (!normalized) {
    return false;
  }

  const inviter = await prisma.user.findUnique({
    where: { inviteCode: normalized },
    select: { id: true, accountStatus: true }
  });

  if (!inviter || inviter.accountStatus !== "active" || inviter.id === userId) {
    return false;
  }

  const result = await prisma.user.updateMany({
    where: { id: userId, invitedByUserId: null },
    data: { invitedByUserId: inviter.id, invitedAt: new Date() }
  });

  return result.count > 0;
}

export async function getInviteSummary(userId: string) {
  const code = await ensureInviteCode(userId);
  const [visits, registered, joined] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { inviteVisits: true } }),
    prisma.user.count({ where: { invitedByUserId: userId } }),
    // Считаем дошедших до конца анкеты: регистрация без профиля никому не нужна.
    prisma.user.count({ where: { invitedByUserId: userId, onboardingCompleted: true } })
  ]);

  return {
    code,
    visits: visits?.inviteVisits ?? 0,
    registered,
    joined
  };
}

export function buildInviteUrl(code: string, origin: string) {
  return `${origin.replace(/\/$/, "")}/i/${code}`;
}
