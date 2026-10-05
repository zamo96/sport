import { describe, expect, it } from "vitest";

import { buildOtpEmail } from "@/lib/email";
import { serverMessages, translateServer } from "@/lib/i18n/server";
import { resolveLocalizedAuthError } from "@/lib/i18n/server/auth-errors";
import {
  getServerRequestLocale,
  resolveServerLocaleInput
} from "@/lib/i18n/server/request-locale";
import { requestLinkSchema } from "@/lib/validators";

describe("server locale resolution", () => {
  it("uses cookie, app header, Accept-Language, then English", () => {
    expect(resolveServerLocaleInput({ cookieLocale: "ru", appLocale: "en", acceptLanguage: "en" })).toBe("ru");
    expect(resolveServerLocaleInput({ cookieLocale: "de", appLocale: "ru-RU", acceptLanguage: "en" })).toBe("ru");
    expect(resolveServerLocaleInput({ appLocale: "de", acceptLanguage: "ru;q=0.9,en;q=0.8" })).toBe("ru");
    expect(resolveServerLocaleInput({ acceptLanguage: "fr-FR" })).toBe("en");
  });

  it("reads an encoded locale cookie from a request", () => {
    const request = new Request("https://example.com/auth/request-link", {
      headers: {
        cookie: "other=value; app_locale=ru%2DRU",
        "x-app-locale": "en"
      }
    });
    expect(getServerRequestLocale(request)).toBe("ru");
  });
});

describe("server auth localization", () => {
  it("keeps English and Russian server catalogs in parity", () => {
    expect(Object.keys(serverMessages.ru).sort()).toEqual(Object.keys(serverMessages.en).sort());
  });

  it("builds complete English and Russian OTP emails", () => {
    const en = buildOtpEmail("123456", "en");
    const ru = buildOtpEmail("123456", "ru");

    expect(en.subject).toBe("Your TennisSearch sign-in code");
    expect(en.text).toContain("valid for 10 minutes");
    expect(en.html).toContain("123456");
    expect(ru.subject).toBe("Код входа в TennisSearch");
    expect(ru.text).toContain("Код действует 10 минут");
    expect(ru.html).toContain("123456");
  });

  it("localizes validation and account errors with stable codes", () => {
    const invalidRequest = requestLinkSchema.safeParse({ email: "bad", userAgreement: { accepted: true, version: "bad" } });
    expect(invalidRequest.success).toBe(false);
    if (invalidRequest.success) throw new Error("Expected invalid auth request");

    expect(resolveLocalizedAuthError(invalidRequest.error, "en")).toMatchObject({
      errorCode: "AUTH_AGREEMENT_REQUIRED",
      message: "Accept the current user agreement",
      status: 400
    });
    expect(resolveLocalizedAuthError(new Error("ACCOUNT_DEACTIVATED"), "ru")).toMatchObject({
      errorCode: "ACCOUNT_DEACTIVATED",
      message: "Аккаунт деактивирован",
      status: 403
    });
    expect(translateServer("ru", "auth.error.invalidCode")).toBe("Неверный или просроченный код");
  });
});
