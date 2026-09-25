import type { SupportedLocale } from "@/lib/locales";
import {
  interpolateWebMessage,
  type WebTranslationValues
} from "@/lib/i18n/web/define";
import { authMessages } from "@/lib/i18n/web/auth";
import { consentMessages } from "@/lib/i18n/web/consents";
import { courtsMessages } from "@/lib/i18n/web/courts";
import { discoverMessages } from "@/lib/i18n/web/discover";
import { localeRecommendationMessages } from "@/lib/i18n/web/locale-recommendation";
import { locationMessages } from "@/lib/i18n/web/location";
import { navigationMessages } from "@/lib/i18n/web/navigation";
import { profileMessages } from "@/lib/i18n/web/profile";
import { settingsMessages } from "@/lib/i18n/web/settings";

export const webMessages = {
  en: {
    ...authMessages.en,
    ...consentMessages.en,
    ...courtsMessages.en,
    ...discoverMessages.en,
    ...navigationMessages.en,
    ...profileMessages.en,
    ...settingsMessages.en,
    ...localeRecommendationMessages.en,
    ...locationMessages.en
  },
  ru: {
    ...authMessages.ru,
    ...consentMessages.ru,
    ...courtsMessages.ru,
    ...discoverMessages.ru,
    ...navigationMessages.ru,
    ...profileMessages.ru,
    ...settingsMessages.ru,
    ...localeRecommendationMessages.ru,
    ...locationMessages.ru
  }
} as const satisfies Record<SupportedLocale, Record<string, string>>;

export type WebMessageKey = keyof (typeof webMessages)["en"];

export function translateWeb(
  locale: SupportedLocale,
  key: WebMessageKey,
  values?: WebTranslationValues
) {
  return interpolateWebMessage(webMessages[locale][key], values);
}

export { interpolateWebMessage } from "@/lib/i18n/web/define";
export type { WebTranslationValue, WebTranslationValues } from "@/lib/i18n/web/define";
