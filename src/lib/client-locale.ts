import {
  DEFAULT_LOCALE,
  LOCALE_COOKIE_NAME,
  normalizeSupportedLocale,
  type SupportedLocale
} from "@/lib/locales";

export const LOCALE_OVERRIDE_STORAGE_KEY = "app-locale-override:v1";
const LOCALE_COOKIE_MAX_AGE_SECONDS = 365 * 24 * 60 * 60;

export function getStoredLocaleOverride(): SupportedLocale | null {
  if (typeof window === "undefined") return null;

  const cookieLocale = getLocaleCookie();
  if (cookieLocale) return cookieLocale;

  try {
    return normalizeSupportedLocale(window.localStorage.getItem(LOCALE_OVERRIDE_STORAGE_KEY));
  } catch {
    return null;
  }
}

export function getBrowserLocale(): SupportedLocale {
  if (typeof navigator === "undefined") return DEFAULT_LOCALE;

  const requestedLanguages = navigator.languages?.length ? navigator.languages : [navigator.language];

  for (const language of requestedLanguages) {
    const locale = normalizeSupportedLocale(language);
    if (locale) return locale;
  }

  return DEFAULT_LOCALE;
}

export function getEffectiveClientLocale(): SupportedLocale {
  return getStoredLocaleOverride() ?? getBrowserLocale();
}

export function storeLocaleOverride(locale: SupportedLocale) {
  if (typeof window === "undefined") return;

  document.cookie = `${LOCALE_COOKIE_NAME}=${encodeURIComponent(locale)}; Path=/; Max-Age=${LOCALE_COOKIE_MAX_AGE_SECONDS}; SameSite=Lax`;

  try {
    window.localStorage.setItem(LOCALE_OVERRIDE_STORAGE_KEY, locale);
  } catch {
    // The language still changes for this session when storage is unavailable.
  }
}

export function clearStoredLocaleOverride() {
  if (typeof window === "undefined") return;

  document.cookie = `${LOCALE_COOKIE_NAME}=; Path=/; Max-Age=0; SameSite=Lax`;
  try {
    window.localStorage.removeItem(LOCALE_OVERRIDE_STORAGE_KEY);
  } catch {
    // Automatic locale resolution still works when storage is unavailable.
  }
}

function getLocaleCookie(): SupportedLocale | null {
  const prefix = `${LOCALE_COOKIE_NAME}=`;
  const rawValue = document.cookie
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(prefix))
    ?.slice(prefix.length);

  if (!rawValue) return null;

  try {
    return normalizeSupportedLocale(decodeURIComponent(rawValue));
  } catch {
    return null;
  }
}
