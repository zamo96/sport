"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";

import { ConsentReviewDialog, type ConsentProfile } from "@/components/consents/consent-review-dialog";
import { useLocale } from "@/components/i18n/locale-provider";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { apiFetch } from "@/lib/client-api";
import type { WebMessageKey } from "@/lib/i18n/web";

function visibilityStatusKey(consents: ConsentProfile["consents"]): WebMessageKey {
  switch (consents.profileVisibility) {
    case "visible":
      return consents.visibleToGuests ? "consents.settings.visible.everyone" : "consents.settings.visible.registered";
    case "legacy":
      return "consents.settings.legacy";
    default:
      return "consents.settings.hidden";
  }
}

/** Настройки согласий: изменить или отозвать показ анкеты, включить или выключить аналитику. */
export function ConsentSettingsPanel({ profile: initialProfile }: { profile: ConsentProfile }) {
  const router = useRouter();
  const { t } = useLocale();
  const [profile, setProfile] = useState(initialProfile);
  const [editing, setEditing] = useState(false);
  const [savingAnalytics, setSavingAnalytics] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { consents } = profile;

  async function setAnalytics(analytics: boolean) {
    setSavingAnalytics(true);
    setError(null);
    try {
      const response = await apiFetch<{ user: ConsentProfile }>("/me/consents", {
        method: "POST",
        body: JSON.stringify({ source: "web", analytics })
      });
      setProfile((current) => ({ ...current, consents: response.user.consents }));
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : t("consents.review.error"));
    } finally {
      setSavingAnalytics(false);
    }
  }

  return (
    <Panel className="space-y-3">
      <div className="text-sm font-bold text-ink">{t("consents.settings.title")}</div>
      <div className="rounded-2xl bg-cream px-4 py-3">
        <div className="text-sm text-ink/75">{t(visibilityStatusKey(consents))}</div>
        <Button type="button" variant="ghost" className="mt-2 min-h-10 border border-line px-3" onClick={() => setEditing(true)}>
          {t("consents.settings.change")}
        </Button>
      </div>

      <label className="flex items-start justify-between gap-3 rounded-2xl bg-cream px-4 py-3">
        <span>
          <span className="block text-sm font-semibold text-ink">{t("consents.settings.analytics")}</span>
          <span className="mt-0.5 block text-xs leading-5 text-ink/60">{t("consents.settings.analyticsHint")}</span>
        </span>
        <input
          type="checkbox"
          role="switch"
          checked={consents.analytics}
          disabled={savingAnalytics}
          onChange={(event) => void setAnalytics(event.target.checked)}
          className="mt-1 h-5 w-5 shrink-0 accent-court"
        />
      </label>

      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}

      <div className="text-xs leading-5 text-ink/60">
        <div>{t("consents.settings.withdrawNote")}</div>
        <div className="mt-2 font-semibold text-ink/70">{t("consents.settings.documents")}</div>
        <ul className="mt-1 space-y-1">
          <li><Link href="/legal/profile-visibility" target="_blank" className="text-court underline underline-offset-2">{t("consents.settings.visibilityDocument")}</Link></li>
          <li><Link href="/legal/analytics" target="_blank" className="text-court underline underline-offset-2">{t("consents.settings.analyticsDocument")}</Link></li>
          <li><Link href="/legal/terms" target="_blank" className="text-court underline underline-offset-2">{t("consents.settings.termsDocument")}</Link></li>
          <li><Link href="/legal/privacy" target="_blank" className="text-court underline underline-offset-2">{t("consents.settings.privacyDocument")}</Link></li>
        </ul>
      </div>

      {editing ? (
        <ConsentReviewDialog
          profile={profile}
          onClose={() => setEditing(false)}
          onSaved={(response) => {
            setProfile((current) => ({ ...current, ...response.user }));
            setEditing(false);
            router.refresh();
          }}
        />
      ) : null}
    </Panel>
  );
}
