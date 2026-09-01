"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";

import { getStoredLocaleOverride, storeLocaleOverride } from "@/lib/client-locale";
import { apiFetch } from "@/lib/client-api";
import { normalizeSupportedLocale, type SupportedLocale } from "@/lib/locales";
import {
  translateWeb,
  type WebMessageKey,
  type WebTranslationValues
} from "@/lib/web-i18n";

type LocaleContextValue = {
  locale: SupportedLocale;
  hasLocaleOverride: boolean;
  setLocale: (locale: SupportedLocale) => void;
  t: (key: WebMessageKey, values?: WebTranslationValues) => string;
};

const LocaleContext = createContext<LocaleContextValue | null>(null);

export function LocaleProvider({
  children,
  initialLocale
}: {
  children: React.ReactNode;
  initialLocale: SupportedLocale;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [locale, setEffectiveLocale] = useState<SupportedLocale>(initialLocale);
  const [localeOverride, setLocaleOverride] = useState<SupportedLocale | null>(null);
  const explicitSelectionVersion = useRef(0);
  const pendingLocaleOverride = useRef<SupportedLocale | null>(null);

  const applyLocale = useCallback((nextLocale: SupportedLocale) => {
    setEffectiveLocale(nextLocale);
    document.documentElement.lang = nextLocale;
  }, []);

  const setLocale = useCallback(
    (nextLocale: SupportedLocale) => {
      explicitSelectionVersion.current += 1;
      pendingLocaleOverride.current = nextLocale;
      storeLocaleOverride(nextLocale);
      setLocaleOverride(nextLocale);
      applyLocale(nextLocale);
      router.refresh();
    },
    [applyLocale, router]
  );

  useEffect(() => {
    const storedLocale = getStoredLocaleOverride();
    setLocaleOverride(storedLocale);
    applyLocale(storedLocale ?? initialLocale);

    // The selecting component owns account persistence and its visible save state.
    // Do not let a concurrent /me read replace the newer local choice with stale account data.
    if (pendingLocaleOverride.current) return;

    const selectionVersion = explicitSelectionVersion.current;
    const controller = new AbortController();

    void apiFetch<{ user?: { localeOverride?: unknown } }>("/me", { signal: controller.signal })
      .then((data) => {
        const accountLocale = normalizeSupportedLocale(data?.user?.localeOverride);
        if (accountLocale && explicitSelectionVersion.current === selectionVersion) {
          storeLocaleOverride(accountLocale);
          setLocaleOverride(accountLocale);
          applyLocale(accountLocale);
          if (accountLocale !== initialLocale) router.refresh();
          return;
        }

        if (!accountLocale && storedLocale && explicitSelectionVersion.current === selectionVersion) {
          void apiFetch("/me/locale", {
            method: "PATCH",
            body: JSON.stringify({ localeOverride: storedLocale })
          }).catch(() => undefined);
        }
      })
      .catch(() => undefined);

    return () => controller.abort();
  }, [applyLocale, initialLocale, pathname, router]);

  const value = useMemo<LocaleContextValue>(
    () => ({
      locale,
      hasLocaleOverride: localeOverride !== null,
      setLocale,
      t: (key, values) => translateWeb(locale, key, values)
    }),
    [locale, localeOverride, setLocale]
  );

  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}

export function useLocale() {
  const context = useContext(LocaleContext);

  if (!context) {
    throw new Error("useLocale must be used inside LocaleProvider");
  }

  return context;
}
