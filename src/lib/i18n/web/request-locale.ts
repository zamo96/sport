import { cookies, headers } from "next/headers";

import {
  LOCALE_COOKIE_NAME,
  normalizeSupportedLocale,
  resolveRequestLocale,
  type SupportedLocale
} from "@/lib/locales";

export function resolveServerRequestLocale(input: {
  cookieLocale?: string | null;
  acceptLanguage?: string | null;
}): SupportedLocale {
  return normalizeSupportedLocale(input.cookieLocale) ?? resolveRequestLocale({
    acceptLanguage: input.acceptLanguage
  });
}

export function getWebRequestLocale(): SupportedLocale {
  return resolveServerRequestLocale({
    cookieLocale: cookies().get(LOCALE_COOKIE_NAME)?.value,
    acceptLanguage: headers().get("accept-language")
  });
}
