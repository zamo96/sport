import { Prisma } from "@prisma/client";
import { createHash, randomInt, timingSafeEqual } from "node:crypto";

import { attributeInviteFromCookie } from "@/lib/auth";
import { formatRussianPhone } from "@/lib/phone";
import { prisma } from "@/lib/prisma";
import { initialProfileVisibility } from "@/lib/profile-visibility";
import { sendSms } from "@/server/sms";
import { recordUserEventsOnce } from "@/server/user-events";

export const PHONE_CODE_TTL_MINUTES = 5;
/** A new SMS to the same number no sooner than this: every SMS is paid. */
export const PHONE_CODE_RESEND_SECONDS = 60;
/** The SMS text up to the code; changing it means a new operator template. */
export const PHONE_CODE_SMS_PREFIX = "Никому не сообщайте код. Код для входа в НаТреню: ";
const MAX_CODE_ATTEMPTS = 5;

export class PhoneAuthError extends Error {
  constructor(
    readonly code: "PHONE_TAKEN" | "INVALID_CODE" | "RESEND_TOO_SOON",
    readonly retryAfterSeconds?: number
  ) {
    super(code);
  }
}

function hashCode(phone: string, code: string) {
  return createHash("sha256").update(`${phone}:${code}`).digest("hex");
}

/**
 * Новый код отменяет предыдущие: в SMS всегда действует только последний.
 * Возвращает код, чтобы вне production его можно было отдать как debugCode.
 */
export async function issuePhoneCode(phone: string, meta: { ip?: string | null } = {}) {
  const now = new Date();
  const previous = await prisma.phoneAuthCode.findFirst({
    where: { phone },
    orderBy: { createdAt: "desc" },
    select: { createdAt: true }
  });
  const waitMs = previous ? previous.createdAt.getTime() + PHONE_CODE_RESEND_SECONDS * 1000 - now.getTime() : 0;
  if (waitMs > 0) throw new PhoneAuthError("RESEND_TOO_SOON", Math.ceil(waitMs / 1000));

  const code = String(randomInt(100000, 1000000));
  await prisma.$transaction([
    prisma.phoneAuthCode.updateMany({ where: { phone, consumedAt: null }, data: { consumedAt: now } }),
    prisma.phoneAuthCode.create({
      data: {
        phone,
        codeHash: hashCode(phone, code),
        expiresAt: new Date(now.getTime() + PHONE_CODE_TTL_MINUTES * 60 * 1000)
      }
    })
  ]);
  // Matches the SMS.ru operator template "Никому не сообщайте код. Код для входа в НаТреню: %d"
  // word for word: a template variable must stand apart, so the code goes last.
  await sendSms(phone, `${PHONE_CODE_SMS_PREFIX}${code}`, meta);
  return code;
}

/** Не больше пяти попыток на один код; успешная проверка гасит код. */
export async function consumePhoneCode(phone: string, code: string) {
  const record = await prisma.phoneAuthCode.findFirst({
    where: { phone, consumedAt: null, expiresAt: { gt: new Date() } },
    orderBy: { createdAt: "desc" }
  });
  if (!record || record.attempts >= MAX_CODE_ATTEMPTS) return false;

  const expected = Buffer.from(record.codeHash, "hex");
  const actual = Buffer.from(hashCode(phone, code.trim()), "hex");
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
    await prisma.phoneAuthCode.update({ where: { id: record.id }, data: { attempts: { increment: 1 } } });
    return false;
  }

  const consumed = await prisma.phoneAuthCode.updateMany({
    where: { id: record.id, consumedAt: null },
    data: { consumedAt: new Date() }
  });
  return consumed.count === 1;
}

/** Вход по подтверждённому номеру: находит аккаунт или создаёт новый. */
export async function signInWithPhone(phone: string, options: { showOnMap?: boolean; consentReview?: boolean } = {}) {
  const existing = await prisma.user.findUnique({ where: { phone } });
  if (existing) {
    return prisma.user.update({
      where: { id: existing.id },
      data: { phoneVerifiedAt: new Date(), isVerified: true, signupCountry: "RU" }
    });
  }

  const user = await prisma.user.create({
    data: {
      phone,
      phoneVerifiedAt: new Date(),
      signupCountry: "RU",
      showOnMap: options.showOnMap ?? true,
      profileVisibility: initialProfileVisibility(options.consentReview),
      isVerified: true
    }
  });
  await recordUserEventsOnce([{ userId: user.id, type: "registration_completed", entityType: "user", entityId: user.id, context: { method: "phone" } }]);
  await attributeInviteFromCookie(user.id);
  return user;
}

/**
 * Привязка номера к уже существующему аккаунту — чтобы тот, кто входил по email
 * или через Apple, дальше входил в России по телефону в тот же аккаунт.
 */
export async function linkPhoneToUser(userId: string, phone: string) {
  const owner = await prisma.user.findUnique({ where: { phone }, select: { id: true } });
  if (owner && owner.id !== userId) throw new PhoneAuthError("PHONE_TAKEN");
  try {
    return await prisma.user.update({
      where: { id: userId },
      data: { phone, phoneVerifiedAt: new Date(), signupCountry: "RU" },
      include: { location: { include: { serviceArea: true } } }
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      throw new PhoneAuthError("PHONE_TAKEN");
    }
    throw error;
  }
}

export function phoneTakenMessage(phone: string) {
  return `Номер ${formatRussianPhone(phone)} уже привязан к другому аккаунту. Войдите по нему или напишите в поддержку.`;
}
