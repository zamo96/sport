"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";

import { ConsentReviewDialog, type ConsentProfile } from "@/components/consents/consent-review-dialog";

type MeResponse = { user: ConsentProfile & { onboardingCompleted?: boolean } };

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
  const [profile, setProfile] = useState<ConsentProfile | null>(null);
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
        if (data.user.onboardingCompleted && data.user.consents?.reviewRequired) {
          setProfile(data.user);
        } else if (data.user.onboardingCompleted) {
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

  if (!profile || skipped) return null;

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
