"use client";

import { useMemo, useState } from "react";

import { useLocale } from "@/components/i18n/locale-provider";
import { apiFetch } from "@/lib/client-api";
import { recommendedLocaleForCountry, type SupportedLocale } from "@/lib/locales";
import { cn } from "@/lib/utils";

export function useLocaleRecommendation(confirmedCountryCode: string | null | undefined) {
  const { locale, hasLocaleOverride } = useLocale();
  const recommendedLocale = useMemo(
    () => (confirmedCountryCode ? recommendedLocaleForCountry(confirmedCountryCode) : null),
    [confirmedCountryCode]
  );

  return {
    recommendedLocale,
    shouldRecommend: Boolean(
      !hasLocaleOverride && confirmedCountryCode && recommendedLocale && recommendedLocale !== locale
    )
  };
}

export function LocaleRecommendation({
  confirmedCountryCode,
  className
}: {
  confirmedCountryCode: string | null | undefined;
  className?: string;
}) {
  const { setLocale, t } = useLocale();
  const { recommendedLocale, shouldRecommend } = useLocaleRecommendation(confirmedCountryCode);
  const [dismissedForCountry, setDismissedForCountry] = useState<string | null>(null);

  if (!shouldRecommend || !recommendedLocale || dismissedForCountry === confirmedCountryCode) return null;

  function acceptRecommendation(locale: SupportedLocale) {
    setLocale(locale);
    setDismissedForCountry(confirmedCountryCode ?? null);
    void apiFetch("/me/locale", {
      method: "PATCH",
      body: JSON.stringify({ localeOverride: locale })
    }).catch(() => undefined);
  }

  return (
    <aside className={cn("rounded-3xl border border-court/15 bg-mint p-4", className)} aria-live="polite">
      <div className="text-sm font-bold text-ink">{t("locale.recommendation.title")}</div>
      <p className="mt-1 text-sm leading-6 text-ink/70">
        {t(recommendedLocale === "ru" ? "locale.recommendation.body.ru" : "locale.recommendation.body.en")}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => acceptRecommendation(recommendedLocale)}
          className="min-h-10 rounded-xl bg-ink px-3 text-xs font-semibold text-white"
        >
          {t(recommendedLocale === "ru" ? "locale.recommendation.action.ru" : "locale.recommendation.action.en")}
        </button>
        <button
          type="button"
          onClick={() => setDismissedForCountry(confirmedCountryCode ?? null)}
          className="min-h-10 rounded-xl px-3 text-xs font-semibold text-ink/65"
        >
          {t("locale.recommendation.dismiss")}
        </button>
      </div>
    </aside>
  );
}
