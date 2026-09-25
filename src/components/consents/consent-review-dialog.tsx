"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { ChevronDown, Lock } from "lucide-react";

import { useLocale } from "@/components/i18n/locale-provider";
import { Button } from "@/components/ui/button";
import { useLockBodyScroll } from "@/components/ui/use-lock-body-scroll";
import { apiFetch } from "@/lib/client-api";
import { getDistrictLabel } from "@/lib/constants";
import type { WebMessageKey } from "@/lib/i18n/web";
import { USER_AGREEMENT_VERSION } from "@/lib/legal-contract";
import { CONSENT_FULL_NAME_PATTERN, type ConsentState } from "@/lib/profile-visibility";

/** Поля профиля, из которых собирается превью карточки на экране согласия. */
export type ConsentProfile = {
  name?: string | null;
  age?: number | null;
  city?: string | null;
  district?: string | null;
  preferredSports?: unknown;
  showOnMap?: boolean;
  consents: ConsentState;
};

type Scope = {
  visibleToGuests: boolean;
  showsBio: boolean;
  showsPhotos: boolean;
  showsVideos: boolean;
  showsSearches: boolean;
  showOnMap: boolean;
};

const SCOPE_TOGGLES: Array<{ key: keyof Scope; label: WebMessageKey }> = [
  { key: "showsBio", label: "consents.customize.bio" },
  { key: "showsPhotos", label: "consents.customize.photos" },
  { key: "showsVideos", label: "consents.customize.videos" },
  { key: "showOnMap", label: "consents.customize.map" },
  { key: "showsSearches", label: "consents.customize.searches" },
  { key: "visibleToGuests", label: "consents.customize.guests" }
];

/**
 * До ответа «Настроить» предлагает показывать всё — человек соглашается кнопкой
 * на то, что видит в превью, а настройка позволяет только сузить показ. После
 * ответа экран открывается с тем, что человек выбрал.
 */
function initialScope(profile: ConsentProfile): Scope {
  const { consents } = profile;
  if (consents.profileVisibility === "visible") {
    return {
      visibleToGuests: consents.visibleToGuests,
      showsBio: consents.showsBio,
      showsPhotos: consents.showsPhotos,
      showsVideos: consents.showsVideos,
      showsSearches: consents.showsSearches,
      showOnMap: profile.showOnMap === true
    };
  }
  return { visibleToGuests: true, showsBio: true, showsPhotos: true, showsVideos: true, showsSearches: true, showOnMap: profile.showOnMap !== false };
}

export type ConsentUpdateResponse = { user: ConsentProfile & Record<string, unknown> };

/**
 * Экран согласия на показ анкеты. Кнопка «Показывать анкету» — само согласие
 * (ст. 10.1 152-ФЗ); принятие новой редакции соглашения и аналитика — отдельные
 * отметки, в запросе они тоже уходят отдельными полями.
 */
export function ConsentReviewDialog({
  profile,
  onSaved,
  onClose
}: {
  profile: ConsentProfile;
  onSaved: (response: ConsentUpdateResponse) => void;
  /** Только из настроек: при обязательном ответе закрыть экран без выбора нельзя. */
  onClose?: () => void;
}) {
  const { t } = useLocale();
  const { consents } = profile;
  const isLegacy = consents.profileVisibility === "legacy";
  const [scope, setScope] = useState<Scope>(() => initialScope(profile));
  const [customizing, setCustomizing] = useState(false);
  const [fullName, setFullName] = useState(consents.fullName ?? "");
  const [analytics, setAnalytics] = useState(consents.analytics);
  const [termsAccepted, setTermsAccepted] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  useLockBodyScroll(true);

  async function submit(decision: "visible" | "hidden") {
    if (consents.termsUpdateRequired && !termsAccepted) {
      setError(t("consents.review.terms.error"));
      return;
    }
    const trimmedName = fullName.trim().replace(/\s+/g, " ");
    if (decision === "visible" && !CONSENT_FULL_NAME_PATTERN.test(trimmedName)) {
      setError(t("consents.review.fullName.error"));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const response = await apiFetch<ConsentUpdateResponse>("/me/consents", {
        method: "POST",
        body: JSON.stringify({
          source: "web",
          ...(consents.termsUpdateRequired ? { acceptAgreementVersion: USER_AGREEMENT_VERSION } : {}),
          profile: decision === "visible" ? { decision, fullName: trimmedName, ...scope } : { decision },
          analytics
        })
      });
      onSaved(response);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : t("consents.review.error"));
    } finally {
      setSaving(false);
    }
  }

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    void submit("visible");
  }

  const sports = Array.isArray(profile.preferredSports) ? profile.preferredSports.filter((sport): sport is string => typeof sport === "string") : [];
  const placeLine = [profile.city, getDistrictLabel(profile.district)].filter(Boolean).join(" · ");
  const initials = (profile.name ?? "").trim().slice(0, 1).toUpperCase() || "•";
  // Имя подставлено из анкеты — остаётся дописать фамилию.
  const needsSurname = fullName.trim().split(/\s+/).filter(Boolean).length === 1;

  return (
    <div className="fixed inset-0 z-[60] flex items-end justify-center bg-ink/40 p-3 sm:items-center" role="dialog" aria-modal="true" aria-labelledby="consent-review-title">
      <form onSubmit={onSubmit} className="max-h-[calc(100svh-1.5rem)] w-full max-w-md space-y-3 overflow-y-auto rounded-[28px] border border-white/70 bg-white p-5 shadow-card">
        <div>
          <h2 id="consent-review-title" className="text-xl font-bold text-ink">
            {isLegacy ? t("consents.review.update.title") : t("consents.review.new.title")}
          </h2>
          {isLegacy ? <p className="mt-1 text-sm leading-6 text-ink/65">{t("consents.review.update.text")}</p> : null}
        </div>

        <div className="flex items-center gap-3 rounded-2xl bg-cream px-3 py-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-court/10 text-sm font-bold text-court">{initials}</div>
          <div className="min-w-0">
            <div className="truncate text-sm font-bold text-ink">{[profile.name, profile.age].filter(Boolean).join(", ")}</div>
            <div className="truncate text-xs text-ink/60">
              {[sports.map((sport) => t(`sport.${sport}` as WebMessageKey)).join(", "), placeLine].filter(Boolean).join(" · ")}
            </div>
          </div>
        </div>

        <p className="text-xs leading-5 text-ink/60">
          {scope.visibleToGuests ? t("consents.review.caption.everyone") : t("consents.review.caption.registered")}
        </p>

        <button
          type="button"
          onClick={() => setCustomizing((current) => !current)}
          aria-expanded={customizing}
          className="inline-flex items-center gap-1 text-sm font-semibold text-court underline underline-offset-2"
        >
          {t("consents.review.customize")}
          <ChevronDown className={`h-4 w-4 transition ${customizing ? "rotate-180" : ""}`} aria-hidden="true" />
        </button>

        {customizing ? (
          <div className="space-y-2 rounded-2xl border border-line px-3 py-3">
            <div className="text-xs text-ink/60">{t("consents.customize.subtitle")}</div>
            <div className="flex items-start justify-between gap-3 py-1">
              <div>
                <div className="text-sm font-semibold text-ink">{t("consents.customize.profile")}</div>
                <div className="text-xs text-ink/55">{t("consents.customize.profileHint")}</div>
              </div>
              <span className="inline-flex shrink-0 items-center gap-1 text-xs text-ink/55">
                <Lock className="h-3.5 w-3.5" aria-hidden="true" />
                {t("consents.customize.profileAlways")}
              </span>
            </div>
            {SCOPE_TOGGLES.map((toggle) => (
              <label key={toggle.key} className="flex items-center justify-between gap-3 py-1 text-sm text-ink">
                <span>{t(toggle.label)}</span>
                <input
                  type="checkbox"
                  role="switch"
                  checked={scope[toggle.key]}
                  onChange={(event) => setScope((current) => ({ ...current, [toggle.key]: event.target.checked }))}
                  className="h-5 w-5 accent-court"
                />
              </label>
            ))}
          </div>
        ) : null}

        {consents.termsUpdateRequired ? (
          <label className="flex items-start gap-3 text-sm leading-5 text-ink/75">
            <input type="checkbox" checked={termsAccepted} onChange={(event) => setTermsAccepted(event.target.checked)} className="mt-0.5 h-4 w-4 shrink-0 accent-court" />
            <span>
              {t("consents.review.terms.prefix")}{" "}
              <Link href="/legal/terms" target="_blank" className="font-semibold text-court underline underline-offset-2">
                {t("consents.review.terms.link")}
              </Link>
            </span>
          </label>
        ) : null}

        <label className="block">
          <input
            value={fullName}
            onChange={(event) => setFullName(event.target.value)}
            autoComplete="name"
            maxLength={150}
            placeholder={t("consents.review.fullName.placeholder")}
            className="input border-line bg-white text-ink placeholder:text-ink/35"
          />
          <span className="mt-1 block text-xs text-ink/55">
            {needsSurname ? t("consents.review.fullName.addSurname") : t("consents.review.fullName.hint")}
          </span>
        </label>

        <label className="flex items-start gap-3 text-sm leading-5 text-ink/75">
          <input type="checkbox" checked={analytics} onChange={(event) => setAnalytics(event.target.checked)} className="mt-0.5 h-4 w-4 shrink-0 accent-court" />
          <span>
            {t("consents.review.analytics.label")}{" "}
            <Link href="/legal/analytics" target="_blank" className="text-court underline underline-offset-2">
              {t("consents.review.analytics.more")}
            </Link>
          </span>
        </label>

        {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}

        <div className="space-y-2 pt-1">
          <Button type="submit" fullWidth disabled={saving}>
            {saving ? t("consents.review.saving") : isLegacy ? t("consents.review.keepVisible") : t("consents.review.show")}
          </Button>
          <Button type="button" fullWidth variant="ghost" className="border border-line" disabled={saving} onClick={() => void submit("hidden")}>
            {isLegacy || consents.profileVisibility === "visible" ? t("consents.review.hide") : t("consents.review.notNow")}
          </Button>
          {onClose ? (
            <Button type="button" fullWidth variant="ghost" disabled={saving} onClick={onClose}>
              {t("consents.review.cancel")}
            </Button>
          ) : null}
          <p className="text-center text-xs text-ink/55">
            {t("consents.review.buttonNote.prefix")}{" "}
            <Link href="/legal/profile-visibility" target="_blank" className="text-court underline underline-offset-2">
              {t("consents.review.buttonNote.link")}
            </Link>
          </p>
        </div>
      </form>
    </div>
  );
}
