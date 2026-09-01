export const SUPPORTED_LOCALES = ["en", "ru"] as const;

export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

export const DEFAULT_LOCALE: SupportedLocale = "en";
export const LOCALE_COOKIE_NAME = "app_locale";

// This is a product-owned rollout list, rather than a geographic definition of the CIS.
// Keep it mutable so markets can be added or removed without changing locale resolution.
export const RUSSIAN_RECOMMENDED_COUNTRY_CODES = new Set([
  "AM",
  "AZ",
  "BY",
  "KZ",
  "KG",
  "MD",
  "RU",
  "TJ",
  "TM",
  "UZ"
]);

export function isSupportedLocale(value: unknown): value is SupportedLocale {
  return typeof value === "string" && SUPPORTED_LOCALES.includes(value as SupportedLocale);
}

export function normalizeSupportedLocale(value: unknown): SupportedLocale | null {
  if (typeof value !== "string") return null;
  const language = value.trim().toLowerCase().split(/[-_]/, 1)[0];
  return isSupportedLocale(language) ? language : null;
}

export function recommendLocaleForConfirmedCountry(countryCode: string | null | undefined): SupportedLocale {
  return countryCode && RUSSIAN_RECOMMENDED_COUNTRY_CODES.has(countryCode.trim().toUpperCase()) ? "ru" : DEFAULT_LOCALE;
}

export const recommendedLocaleForCountry = recommendLocaleForConfirmedCountry;

export function resolveRequestLocale(input: {
  explicitLocale?: string | null;
  acceptLanguage?: string | null;
} = {}): SupportedLocale {
  const explicitLocale = normalizeSupportedLocale(input.explicitLocale);
  if (explicitLocale) return explicitLocale;

  return parseAcceptLanguage(input.acceptLanguage) ?? DEFAULT_LOCALE;
}

function parseAcceptLanguage(header: string | null | undefined): SupportedLocale | null {
  if (!header) return null;

  const candidates = header
    .split(",")
    .map((part, position) => {
      const [tag = "", ...parameters] = part.trim().split(";");
      const qualityParameter = parameters.find((parameter) => parameter.trim().toLowerCase().startsWith("q="));
      const parsedQuality = qualityParameter ? Number(qualityParameter.trim().slice(2)) : 1;
      return {
        locale: normalizeSupportedLocale(tag),
        quality: Number.isFinite(parsedQuality) ? Math.min(Math.max(parsedQuality, 0), 1) : 0,
        position
      };
    })
    .filter(
      (candidate): candidate is { locale: SupportedLocale; quality: number; position: number } =>
        candidate.locale !== null && candidate.quality > 0
    )
    .sort((left, right) => right.quality - left.quality || left.position - right.position);

  return candidates[0]?.locale ?? null;
}
