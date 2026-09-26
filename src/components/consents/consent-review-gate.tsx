"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";

import { PhoneLinkForm } from "@/components/auth/phone-link-form";
import { ConsentReviewDialog, type ConsentProfile } from "@/components/consents/consent-review-dialog";
import { useLocale } from "@/components/i18n/locale-provider";
import { Button } from "@/components/ui/button";

type MeResponse = { user: ConsentProfile & { onboardingCompleted?: boolean; phoneLinkSuggested?: boolean } };

/** «Позже» на предложении привязать номер действует до конца вкладки. */
const PHONE_LINK_DISMISSED_KEY = "natrenyu.phoneLink.dismissed";

function phoneLinkDismissed() {
  try {
    return sessionStorage.getItem(PHONE_LINK_DISMISSED_KEY) === "1";
  } catch {
    return false;
  }
}

/** Здесь экран согласия не нужен: сами документы, вход, анкета и админка. */
const SKIPPED_PREFIXES = ["/legal", "/auth", "/onboarding", "/admin", "/support", "/offline"];

/**
 * Показывает экран согласия после анкеты, пока человек не ответил, — и
 * действующим аккаунтам, созданным до раздельных согласий. Пока ответа нет,
 * такие аккаунты видны как раньше; решение применяется на сервере сразу.
 */
export function ConsentReviewGate() {
  const pathname = usePathname();
  const router = useRouter();
  const { t } = useLocale();
  const [profile, setProfile] = useState<ConsentProfile | null>(null);
  const [suggestPhoneLink, setSuggestPhoneLink] = useState(false);
  const [resolved, setResolved] = useState(false);
  const skipped = SKIPPED_PREFIXES.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));

  useEffect(() => {
    if (skipped || resolved) return;
    let cancelled = false;
    (async () => {
      try {
        const response = await fetch("/me", { credentials: "same-origin", headers: { Accept: "application/json" } });
        // Гость: проверим снова после следующей навигации — он мог войти.
        if (!response.ok) return;
        const data = (await response.json()) as MeResponse;
        if (cancelled) return;
        if (!data.user.onboardingCompleted) return;
        // Сначала согласие, потом номер телефона — по одному окну за раз.
        setSuggestPhoneLink(data.user.phoneLinkSuggested === true && !phoneLinkDismissed());
        if (data.user.consents?.reviewRequired) {
          setProfile(data.user);
        } else {
          setResolved(true);
        }
      } catch {
        // Сеть недоступна — спросим на следующей навигации.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [pathname, skipped, resolved]);

  if (skipped) return null;

  if (!profile) {
    if (!suggestPhoneLink) return null;
    const close = () => {
      try {
        sessionStorage.setItem(PHONE_LINK_DISMISSED_KEY, "1");
      } catch {
        // Без хранилища окно просто покажется снова на следующей загрузке.
      }
      setSuggestPhoneLink(false);
    };
    return (
      <div className="fixed inset-0 z-[60] flex items-end justify-center bg-ink/40 p-3 sm:items-center" role="dialog" aria-modal="true" aria-labelledby="phone-link-title">
        <div className="w-full max-w-md space-y-3 rounded-[28px] border border-white/70 bg-white p-5 shadow-card">
          <h2 id="phone-link-title" className="text-xl font-bold text-ink">{t("phoneLink.title")}</h2>
          <p className="text-sm leading-6 text-ink/65">{t("phoneLink.text")}</p>
          <PhoneLinkForm
            onLinked={() => {
              setSuggestPhoneLink(false);
              router.refresh();
            }}
          />
          <Button type="button" fullWidth variant="ghost" onClick={close}>
            {t("phoneLink.later")}
          </Button>
        </div>
      </div>
    );
  }

  return (
    <ConsentReviewDialog
      profile={profile}
      onSaved={() => {
        setProfile(null);
        setResolved(true);
        router.refresh();
      }}
    />
  );
}
