import {
  LOCALE_COOKIE_NAME,
  normalizeSupportedLocale,
  resolveRequestLocale,
  type SupportedLocale
} from "@/lib/locales";

export function resolveServerLocaleInput(input: {
  cookieLocale?: string | null;
  appLocale?: string | null;
  acceptLanguage?: string | null;
}): SupportedLocale {
  return (
    normalizeSupportedLocale(input.cookieLocale) ??
    normalizeSupportedLocale(input.appLocale) ??
    resolveRequestLocale({ acceptLanguage: input.acceptLanguage })
  );
}

export function getServerRequestLocale(request: Request): SupportedLocale {
  return resolveServerLocaleInput({
    cookieLocale: readCookie(request.headers.get("cookie"), LOCALE_COOKIE_NAME),
    appLocale: request.headers.get("x-app-locale"),
    acceptLanguage: request.headers.get("accept-language")
  });
}

function readCookie(cookieHeader: string | null, name: string) {
  const prefix = `${name}=`;
  const rawValue = cookieHeader
    ?.split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(prefix))
    ?.slice(prefix.length);

  if (!rawValue) return null;
  try {
    return decodeURIComponent(rawValue);
  } catch {
    return null;
  }
}
