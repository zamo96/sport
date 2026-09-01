"use client";

import { useRef, useState } from "react";

import { useLocale } from "@/components/i18n/locale-provider";
import { apiFetch } from "@/lib/client-api";
import type { SupportedLocale } from "@/lib/locales";

const localeOptions: SupportedLocale[] = ["en", "ru"];

export function LocaleSelector() {
  const { locale, setLocale, t } = useLocale();
  const [status, setStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const requestVersion = useRef(0);

  async function selectLocale(nextLocale: SupportedLocale) {
    if (nextLocale === locale && status !== "error") return;

    setLocale(nextLocale);
    setStatus("saving");
    const version = ++requestVersion.current;

    try {
      await apiFetch("/me/locale", {
        method: "PATCH",
        body: JSON.stringify({ localeOverride: nextLocale })
      });
      if (requestVersion.current === version) setStatus("saved");
    } catch {
      if (requestVersion.current === version) setStatus("error");
    }
  }

  return (
    <section aria-labelledby="app-language-title">
      <div id="app-language-title" className="text-sm font-bold text-ink">
        {t("settings.language.title")}
      </div>
      <p className="mt-1 text-xs leading-5 text-ink/55">{t("settings.language.description")}</p>
      <div className="mt-3 grid grid-cols-2 gap-2" role="radiogroup" aria-labelledby="app-language-title">
        {localeOptions.map((option) => {
          const active = locale === option;
          const label = option === "en" ? t("settings.language.english") : t("settings.language.russian");

          return (
            <button
              key={option}
              type="button"
              role="radio"
              aria-checked={active}
              onClick={() => void selectLocale(option)}
              className={`min-h-12 rounded-2xl px-4 text-sm font-semibold transition ${
                active ? "bg-ink text-white shadow-glow" : "bg-cream text-ink"
              }`}
            >
              {label}
            </button>
          );
        })}
      </div>
      <div className="mt-2 min-h-5 text-xs text-ink/55" role="status" aria-live="polite">
        {status === "saving" ? t("settings.language.saving") : null}
        {status === "saved" ? t("settings.language.saved") : null}
        {status === "error" ? <span className="text-red-700">{t("settings.language.error")}</span> : null}
      </div>
    </section>
  );
}
