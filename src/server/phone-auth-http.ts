import { ZodError } from "zod";

import { fail, getErrorMessage } from "@/lib/http";
import { resolveLocalizedAuthError } from "@/lib/i18n/server/auth-errors";
import { translateServer } from "@/lib/i18n/server";
import type { SupportedLocale } from "@/lib/locales";
import { PhoneAuthError, phoneTakenMessage } from "@/server/phone-auth";
import { SmsUnavailableError } from "@/server/sms";
import { VkAuthError } from "@/server/vk-auth";

/**
 * Ошибки входа по телефону и VK ID. Сообщения схем уже человеческие
 * («Укажите российский мобильный номер…»), поэтому показываются как есть.
 */
export function phoneAuthFailure(error: unknown, locale: SupportedLocale, phone?: string) {
  if (error instanceof ZodError) {
    const issue = error.issues[0];
    if (issue?.path[0] === "userAgreement") {
      return fail(translateServer(locale, "auth.error.agreementRequired"), 400, "AUTH_AGREEMENT_REQUIRED");
    }
    return fail(issue?.message ?? translateServer(locale, "auth.error.invalidRequest"), 400, "AUTH_INVALID_REQUEST");
  }
  if (error instanceof SmsUnavailableError) {
    return fail(translateServer(locale, "auth.error.smsUnavailable"), 503, "AUTH_SMS_UNAVAILABLE");
  }
  if (error instanceof VkAuthError) {
    return fail(error.message, 401, "AUTH_VK_FAILED");
  }
  if (error instanceof PhoneAuthError) {
    return error.code === "PHONE_TAKEN"
      ? fail(phone ? phoneTakenMessage(phone) : "Номер уже привязан к другому аккаунту", 409, "AUTH_PHONE_TAKEN")
      : fail(translateServer(locale, "auth.error.invalidPhoneCode"), 401, "AUTH_INVALID_CODE");
  }
  if (getErrorMessage(error) === "UNAUTHORIZED") {
    return fail("Требуется авторизация", 401);
  }
  const localized = resolveLocalizedAuthError(error, locale);
  return fail(localized.message, localized.status, localized.errorCode);
}
