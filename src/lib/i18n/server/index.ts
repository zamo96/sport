import type { SupportedLocale } from "@/lib/locales";
import {
  interpolateServerMessage,
  type ServerTranslationValues
} from "@/lib/i18n/server/define";
import { serverAuthMessages } from "@/lib/i18n/server/auth";

export const serverMessages = {
  en: { ...serverAuthMessages.en },
  ru: { ...serverAuthMessages.ru }
} as const satisfies Record<SupportedLocale, Record<string, string>>;

export type ServerMessageKey = keyof (typeof serverMessages)["en"];

export function translateServer(
  locale: SupportedLocale,
  key: ServerMessageKey,
  values?: ServerTranslationValues
) {
  return interpolateServerMessage(serverMessages[locale][key], values);
}

export type { ServerTranslationValue, ServerTranslationValues } from "@/lib/i18n/server/define";
