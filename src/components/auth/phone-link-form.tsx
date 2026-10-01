"use client";

import { useState, type FormEvent } from "react";

import { useLocale } from "@/components/i18n/locale-provider";
import { Button } from "@/components/ui/button";
import { RussianPhoneInput } from "@/components/auth/russian-phone-input";
import { apiFetch } from "@/lib/client-api";
import { formatRussianPhone } from "@/lib/phone";

/**
 * Привязка номера к уже открытому аккаунту: номер → код из SMS → готово.
 * После этого человек из России входит в тот же аккаунт по телефону.
 */
export function PhoneLinkForm({ onLinked }: { onLinked: (phone: string) => void }) {
  const { t } = useLocale();
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [debugCode, setDebugCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function requestCode(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<{ debugCode?: string }>("/me/phone/request", { method: "POST", body: JSON.stringify({ phone: `+7${phone}` }) });
      setDebugCode(data.debugCode ?? null);
      setCode("");
      setStep("code");
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : t("auth.error.requestCode"));
    } finally {
      setLoading(false);
    }
  }

  async function verify(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<{ user: { phone: string } }>("/me/phone/verify", { method: "POST", body: JSON.stringify({ phone: `+7${phone}`, code }) });
      onLinked(data.user.phone);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : t("auth.error.verify"));
    } finally {
      setLoading(false);
    }
  }

  return step === "phone" ? (
    <form className="space-y-3" onSubmit={requestCode}>
      <RussianPhoneInput value={phone} onChange={setPhone} ariaLabel={t("auth.phone.label")} className="border-line" />
      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
      <Button type="submit" fullWidth disabled={loading}>
        {loading ? t("auth.phone.sending") : t("auth.phone.getCode")}
      </Button>
    </form>
  ) : (
    <form className="space-y-3" onSubmit={verify}>
      <div className="text-sm text-ink/70">
        {t("auth.code.sentPhone", { phone: formatRussianPhone(`+7${phone}`) })}
        {debugCode ? <div className="mt-1 font-semibold text-clay">{t("auth.code.demo", { code: debugCode })}</div> : null}
      </div>
      <input
        required
        inputMode="numeric"
        autoComplete="one-time-code"
        maxLength={6}
        value={code}
        onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
        className="input border-line bg-white text-center text-xl tracking-[0.4em] text-ink placeholder:text-ink/25"
        placeholder="000000"
        aria-label={t("auth.code.label")}
      />
      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
      <div className="flex gap-3">
        <Button type="button" fullWidth variant="ghost" className="border border-line" onClick={() => setStep("phone")}>
          {t("auth.code.changePhone")}
        </Button>
        <Button type="submit" fullWidth disabled={loading || code.length !== 6}>
          {loading ? t("auth.code.saving") : t("phoneLink.confirm")}
        </Button>
      </div>
    </form>
  );
}
