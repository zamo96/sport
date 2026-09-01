import { describe, expect, it } from "vitest";

import {
  DEFAULT_LOCALE,
  recommendLocaleForConfirmedCountry,
  resolveRequestLocale,
  RUSSIAN_RECOMMENDED_COUNTRY_CODES
} from "@/lib/locales";
import { webMessages, interpolateWebMessage, translateWeb } from "@/lib/web-i18n";
import { resolveServerRequestLocale } from "@/lib/i18n/web/request-locale";

describe("locale resolution", () => {
  it("uses a supported explicit locale before the browser preference", () => {
    expect(resolveRequestLocale({ explicitLocale: "ru-RU", acceptLanguage: "en-US,en;q=0.9" })).toBe("ru");
  });

  it("uses the highest-quality supported Accept-Language entry", () => {
    expect(resolveRequestLocale({ acceptLanguage: "de-DE, en;q=0.7, ru;q=0.9" })).toBe("ru");
    expect(resolveRequestLocale({ explicitLocale: "de", acceptLanguage: "en-GB" })).toBe("en");
  });

  it("falls back to English when no supported language is present", () => {
    expect(resolveRequestLocale({ acceptLanguage: "de-DE,*;q=0.5" })).toBe(DEFAULT_LOCALE);
  });

  it("recommends Russian only for the mutable product country list", () => {
    expect(recommendLocaleForConfirmedCountry("kz")).toBe("ru");
    expect(recommendLocaleForConfirmedCountry("DE")).toBe("en");
    expect(recommendLocaleForConfirmedCountry(undefined)).toBe("en");
    expect(Array.from(RUSSIAN_RECOMMENDED_COUNTRY_CODES).sort()).toEqual(
      ["AM", "AZ", "BY", "KZ", "KG", "MD", "RU", "TJ", "TM", "UZ"].sort()
    );
  });

  it("resolves server-rendered locale from cookie before Accept-Language", () => {
    expect(resolveServerRequestLocale({ cookieLocale: "ru", acceptLanguage: "en-US" })).toBe("ru");
    expect(resolveServerRequestLocale({ cookieLocale: "de", acceptLanguage: "ru-RU" })).toBe("ru");
    expect(resolveServerRequestLocale({ cookieLocale: null, acceptLanguage: "fr-FR" })).toBe("en");
  });
});

describe("web message catalogs", () => {
  it("keeps English and Russian key sets in parity", () => {
    expect(Object.keys(webMessages.ru).sort()).toEqual(Object.keys(webMessages.en).sort());
  });

  it("supports named interpolation without corrupting missing placeholders", () => {
    expect(interpolateWebMessage("Hello, {name}. You have {count} games.", { name: "Alex", count: 2 })).toBe(
      "Hello, Alex. You have 2 games."
    );
    expect(interpolateWebMessage("Hello, {name}.")).toBe("Hello, {name}.");
    expect(translateWeb("ru", "nav.profile")).toBe("Профиль");
  });
});
