import { ZodError } from "zod";

import { getErrorMessage } from "@/lib/http";
import { translateServer } from "@/lib/i18n/server";
import type { SupportedLocale } from "@/lib/locales";

export type AuthErrorCode =
  | "ACCOUNT_DEACTIVATED"
  | "AUTH_AGREEMENT_REQUIRED"
  | "AUTH_APPLE_EMAIL_REQUIRED"
  | "AUTH_APPLE_INVALID_TOKEN"
  | "AUTH_APPLE_UNAVAILABLE"
  | "AUTH_INVALID_REQUEST"
  | "AUTH_RATE_LIMITED"
  | "AUTH_UNAVAILABLE";

export type AppleAuthPhase = "request" | "apple" | "session";

const APPLE_EMAIL_REQUIRED_ERROR = "Apple не передал email для нового аккаунта. Попробуй снова или используй вход по email.";
const APPLE_PROVIDER_UNAVAILABLE_ERRORS = new Set([
  "Не удалось получить ключи Apple для входа",
  "Apple не вернул ключи для проверки identity token"
]);

export function resolveLocalizedAppleAuthError(
  error: unknown,
  locale: SupportedLocale,
  phase: AppleAuthPhase
): { message: string; status: number; errorCode: AuthErrorCode } {
  const rawMessage = getErrorMessage(error);
  if (rawMessage === "ACCOUNT_DEACTIVATED" || phase !== "apple") {
    return resolveLocalizedAuthError(error, locale);
  }

  if (rawMessage === APPLE_EMAIL_REQUIRED_ERROR) {
    return {
      message: translateServer(locale, "auth.error.appleEmailRequired"),
      status: 422,
      errorCode: "AUTH_APPLE_EMAIL_REQUIRED"
    };
  }

  if (APPLE_PROVIDER_UNAVAILABLE_ERRORS.has(rawMessage)) {
    return {
      message: translateServer(locale, "auth.error.appleUnavailable"),
      status: 503,
      errorCode: "AUTH_APPLE_UNAVAILABLE"
    };
  }

  return {
    message: translateServer(locale, "auth.error.appleInvalid"),
    status: 401,
    errorCode: "AUTH_APPLE_INVALID_TOKEN"
  };
}

export function resolveLocalizedAuthError(error: unknown, locale: SupportedLocale): {
  message: string;
  status: number;
  errorCode: AuthErrorCode;
} {
  const rawMessage = getErrorMessage(error);
  if (rawMessage === "AUTH_RATE_LIMITED") {
    return { message: translateServer(locale, "auth.error.rateLimited"), status: 429, errorCode: "AUTH_RATE_LIMITED" };
  }
  if (rawMessage === "ACCOUNT_DEACTIVATED") {
    return {
      message: translateServer(locale, "auth.error.deactivated"),
      status: 403,
      errorCode: "ACCOUNT_DEACTIVATED"
    };
  }

  if (error instanceof ZodError && error.issues.some((issue) => issue.path[0] === "country")) {
    // Email, Apple и Google — для тех, кто не в России (ч. 10 ст. 8 149-ФЗ).
    return { message: translateServer(locale, "auth.error.russiaPhoneOnly"), status: 400, errorCode: "AUTH_INVALID_REQUEST" };
  }

  if (error instanceof ZodError || error instanceof SyntaxError) {
    const agreementIssue = error instanceof ZodError && error.issues.some((issue) => issue.path[0] === "userAgreement");
    return agreementIssue
      ? {
          message: translateServer(locale, "auth.error.agreementRequired"),
          status: 400,
          errorCode: "AUTH_AGREEMENT_REQUIRED"
        }
      : {
          message: translateServer(locale, "auth.error.invalidRequest"),
          status: 400,
          errorCode: "AUTH_INVALID_REQUEST"
        };
  }

  return {
    message: translateServer(locale, "auth.error.unavailable"),
    status: 503,
    errorCode: "AUTH_UNAVAILABLE"
  };
}
