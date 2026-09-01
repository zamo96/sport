import type { SupportedLocale } from "@/lib/locales";

export type ServerTranslationValue = string | number;
export type ServerTranslationValues = Readonly<Record<string, ServerTranslationValue>>;

export function defineServerMessages<const English extends Record<string, string>>(
  en: English,
  ru: { [Key in keyof English]: string }
) {
  return { en, ru } as const satisfies Record<SupportedLocale, Record<keyof English, string>>;
}

export function interpolateServerMessage(message: string, values: ServerTranslationValues = {}) {
  return message.replace(/\{([A-Za-z][A-Za-z0-9_]*)\}/g, (placeholder, key: string) =>
    Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : placeholder
  );
}
