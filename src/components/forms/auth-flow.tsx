"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

export function AuthFlow() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"email" | "code">("email");
  const [loading, setLoading] = useState(false);
  const [debugCode, setDebugCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function requestLink(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const data = await apiFetch<{ debugCode?: string }>("/auth/request-link", {
        method: "POST",
        body: JSON.stringify({ email })
      });
      setDebugCode(data.debugCode ?? null);
      setStep("code");
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось отправить код");
    } finally {
      setLoading(false);
    }
  }

  async function verify(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const data = await apiFetch<{ user: { onboardingCompleted: boolean } }>("/auth/verify", {
        method: "POST",
        body: JSON.stringify({ email, code })
      });
      router.push(data.user.onboardingCompleted ? "/discover" : "/onboarding");
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось подтвердить код");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-4">
      <Panel className="overflow-hidden p-0">
        <div className="bg-court px-5 py-6 text-white">
          <div className="mb-2 inline-flex rounded-full border border-white/20 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em]">
            MVP-доступ
          </div>
          <h1 className="font-[var(--font-heading)] text-4xl font-bold leading-none">
            Найди следующую игру свайпом.
          </h1>
          <p className="mt-3 max-w-xs text-sm leading-6 text-white/80">
            Вход по email, быстрые мэтчи, выбор площадки и договоренность об игре в одном потоке.
          </p>
        </div>
        <div className="space-y-4 p-5">
          {step === "email" ? (
            <form className="space-y-4" onSubmit={requestLink}>
              <label className="block">
                <div className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-ink/60">
                  Почта
                </div>
                <input
                  required
                  type="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  className="h-12 w-full rounded-2xl border border-line bg-cream px-4 outline-none ring-0"
                  placeholder="player@email.com"
                />
              </label>
              <Button type="submit" fullWidth disabled={loading}>
                {loading ? "Отправляем..." : "Получить код"}
              </Button>
            </form>
          ) : (
            <form className="space-y-4" onSubmit={verify}>
              <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-ink/70">
                Код отправлен на <span className="font-semibold text-ink">{email}</span>
                {debugCode ? (
                  <div className="mt-2 font-semibold text-clay">Демо-код: {debugCode}</div>
                ) : null}
              </div>
              <label className="block">
                <div className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-ink/60">
                  Код подтверждения
                </div>
                <input
                  required
                  inputMode="numeric"
                  maxLength={6}
                  value={code}
                  onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
                  className="h-12 w-full rounded-2xl border border-line bg-cream px-4 text-center text-xl tracking-[0.4em] outline-none"
                  placeholder="000000"
                />
              </label>
              <Button type="submit" fullWidth disabled={loading || code.length !== 6}>
                {loading ? "Проверяем..." : "Войти"}
              </Button>
              <Button type="button" variant="ghost" fullWidth onClick={() => setStep("email")}>
                Изменить почту
              </Button>
            </form>
          )}

          {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
        </div>
      </Panel>
    </div>
  );
}
