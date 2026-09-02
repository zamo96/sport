import { describe, expect, it } from "vitest";

import { notificationMessages, pluralKeySuffix } from "@/lib/i18n/server/notifications";
import { translateServer } from "@/lib/i18n/server";
import { resolveUserLocale } from "@/server/notification-campaigns";

describe("russian plural forms", () => {
  it("picks the right form for counts", () => {
    expect(pluralKeySuffix("ru", 1)).toBe("one");
    expect(pluralKeySuffix("ru", 2)).toBe("few");
    expect(pluralKeySuffix("ru", 4)).toBe("few");
    expect(pluralKeySuffix("ru", 5)).toBe("many");
    expect(pluralKeySuffix("ru", 11)).toBe("many");
    expect(pluralKeySuffix("ru", 21)).toBe("one");
    expect(pluralKeySuffix("ru", 22)).toBe("few");
    expect(pluralKeySuffix("ru", 111)).toBe("many");
  });

  it("keeps english to singular and plural", () => {
    expect(pluralKeySuffix("en", 1)).toBe("one");
    expect(pluralKeySuffix("en", 2)).toBe("many");
    expect(pluralKeySuffix("en", 5)).toBe("many");
  });

  it("produces agreeing digest titles in russian", () => {
    const title = (count: number) =>
      translateServer("ru", `push.hotDigest.title.${pluralKeySuffix("ru", count)}`, { count });

    expect(title(1)).toBe("Есть срочная игра рядом");
    expect(title(3)).toBe("Рядом 3 срочные игры");
    expect(title(5)).toBe("Рядом 5 срочных игр");
  });
});

describe("push message catalogue", () => {
  it("translates every push key in both languages", () => {
    const keys = Object.keys(notificationMessages.en);

    expect(keys.length).toBeGreaterThan(0);
    for (const key of keys) {
      expect(notificationMessages.ru).toHaveProperty(key);
      expect(notificationMessages.ru[key as keyof typeof notificationMessages.ru]).not.toBe("");
      expect(notificationMessages.en[key as keyof typeof notificationMessages.en]).not.toBe("");
    }
  });

  it("leaves no unresolved placeholders", () => {
    expect(translateServer("en", "push.firstPlayers.body", { count: 4 })).toBe(
      "We found 4 — take a look and see who fits"
    );
    expect(translateServer("ru", "push.firstPlayers.body", { count: 4 })).toBe(
      "Мы нашли 4 — посмотрите, кто подойдёт"
    );
  });
});

describe("locale for a push", () => {
  it("prefers the player's explicit choice", () => {
    expect(resolveUserLocale({ localeOverride: "ru", location: { countryCode: "GB" } })).toBe("ru");
    expect(resolveUserLocale({ localeOverride: "en", location: { countryCode: "RU" } })).toBe("en");
  });

  it("falls back to the country of residence", () => {
    expect(resolveUserLocale({ localeOverride: null, location: { countryCode: "RU" } })).toBe("ru");
    expect(resolveUserLocale({ localeOverride: null, location: { countryCode: "KZ" } })).toBe("ru");
    expect(resolveUserLocale({ localeOverride: null, location: { countryCode: "AE" } })).toBe("en");
  });

  it("falls back to the default locale without a country", () => {
    expect(resolveUserLocale({ localeOverride: null, location: null })).toBe("en");
    expect(resolveUserLocale({})).toBe("en");
  });
});

describe("locale from the device", () => {
  it("prefers the app language over the country when no explicit choice", () => {
    expect(
      resolveUserLocale({
        localeOverride: null,
        location: null,
        pushDevices: [{ locale: "ru" }]
      })
    ).toBe("ru");

    expect(
      resolveUserLocale({
        localeOverride: null,
        location: { countryCode: "RU" },
        pushDevices: [{ locale: "en" }]
      })
    ).toBe("en");
  });

  it("still lets an explicit choice win", () => {
    expect(
      resolveUserLocale({
        localeOverride: "en",
        location: { countryCode: "RU" },
        pushDevices: [{ locale: "ru" }]
      })
    ).toBe("en");
  });

  it("skips devices without a usable locale", () => {
    expect(
      resolveUserLocale({
        localeOverride: null,
        location: { countryCode: "RU" },
        pushDevices: [{ locale: null }, { locale: "zz" }, { locale: "ru" }]
      })
    ).toBe("ru");

    expect(
      resolveUserLocale({
        localeOverride: null,
        location: null,
        pushDevices: [{ locale: null }]
      })
    ).toBe("en");
  });
});
