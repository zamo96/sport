import type { SupportedLocale } from "@/lib/locales";

export type WebTranslationValue = string | number;
export type WebTranslationValues = Readonly<Record<string, WebTranslationValue>>;

export function defineWebMessages<const English extends Record<string, string>>(
  en: English,
  ru: { [Key in keyof English]: string }
) {
  return { en, ru } as const satisfies Record<SupportedLocale, Record<keyof English, string>>;
}

export function interpolateWebMessage(message: string, values: WebTranslationValues = {}) {
  return message.replace(/\{([A-Za-z][A-Za-z0-9_]*)\}/g, (placeholder, key: string) =>
    Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : placeholder
  );
}
