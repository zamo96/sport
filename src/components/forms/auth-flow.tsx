"use client";

import { type ReactNode, FormEvent, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { type Gender, type Sport } from "@prisma/client";
import { ShieldCheck, Sparkles, Users } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { DAY_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import {
  clearGuestOnboardingDraft,
  createDefaultGuestOnboardingDraft,
  guestDraftHasProfileBasics,
  loadGuestOnboardingDraft,
  saveGuestOnboardingDraft,
  type GuestOnboardingDraft
} from "@/lib/guest-draft";
import { getPrimarySportLevel, type SportLevelValue } from "@/lib/sport-levels";
import { AvailabilityPicker } from "@/components/forms/availability-picker";
import { AgeRibbonPicker } from "@/components/forms/age-ribbon-picker";
import { SportLevelGuideSheet } from "@/components/forms/sport-level-guide-sheet";
import { YandexAuthDemoMap } from "@/components/maps/yandex-auth-demo-map";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportPicker } from "@/components/forms/sport-picker";

type AuthFlowProps = {
  activePlayersCount: number;
  initialStep?: "intro" | "email";
};

type DraftProfile = GuestOnboardingDraft;

const ROTATING_SPORT_TEXTS = ["теннису", "футболу", "паделу", "волейболу", "боксу"] as const;

export function AuthFlow({ activePlayersCount, initialStep = "intro" }: AuthFlowProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [step, setStep] = useState<"intro" | "profile" | "availability" | "email" | "code">(initialStep);
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [loading, setLoading] = useState(false);
  const [debugCode, setDebugCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [activeSportIndex, setActiveSportIndex] = useState(0);
  const [typedSport, setTypedSport] = useState("");
  const [isDeletingSport, setIsDeletingSport] = useState(false);
  const [draft, setDraft] = useState<DraftProfile>(createDefaultGuestOnboardingDraft());
  const [draftHydrated, setDraftHydrated] = useState(false);
  const [levelGuideOpen, setLevelGuideOpen] = useState(false);

  const continueHref = searchParams.get("continue") || "/discover";

  useEffect(() => {
    const currentText = ROTATING_SPORT_TEXTS[activeSportIndex];
    const finishedTyping = typedSport === currentText;
    const finishedDeleting = typedSport.length === 0;
    const delay = isDeletingSport ? 45 : finishedTyping ? 1200 : 90;

    const timeout = window.setTimeout(() => {
      if (!isDeletingSport) {
        if (finishedTyping) {
          setIsDeletingSport(true);
          return;
        }

        setTypedSport(currentText.slice(0, typedSport.length + 1));
        return;
      }

      if (!finishedDeleting) {
        setTypedSport(currentText.slice(0, typedSport.length - 1));
        return;
      }

      setIsDeletingSport(false);
      setActiveSportIndex((current) => (current + 1) % ROTATING_SPORT_TEXTS.length);
    }, delay);

    return () => window.clearTimeout(timeout);
  }, [activeSportIndex, isDeletingSport, typedSport]);

  useEffect(() => {
    const savedDraft = loadGuestOnboardingDraft();

    if (savedDraft) {
      setDraft(savedDraft);
    }

    setDraftHydrated(true);
  }, []);

  useEffect(() => {
    if (!draftHydrated) {
      return;
    }

    saveGuestOnboardingDraft(draft);
  }, [draft, draftHydrated]);

  useEffect(() => {
    if (!draftHydrated) {
      return;
    }

    if (searchParams.get("step") === "email") {
      setStep("email");
    }
  }, [draftHydrated, searchParams]);

  const hasProfileBasics = guestDraftHasProfileBasics(draft);
  const hasAvailability = Object.keys(draft.availabilityByDay).length > 0;

  function setDraftField<Key extends keyof DraftProfile>(key: Key, value: DraftProfile[Key]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  function setPreferredSports(nextSports: Sport[]) {
    const currentLevels = draft.sportLevels;
    const normalizedLevels = Object.fromEntries(
      nextSports.map((sport) => {
        if (Object.prototype.hasOwnProperty.call(currentLevels, sport)) {
          return [sport, currentLevels[sport] ?? null];
        }

        return [sport, 5];
      })
    ) as Partial<Record<Sport, SportLevelValue>>;

    setDraft((current) => ({
      ...current,
      preferredSports: nextSports,
      sportLevels: normalizedLevels
    }));
  }

  function setSportLevel(sport: Sport, level: SportLevelValue) {
    setDraft((current) => ({
      ...current,
      sportLevels: {
        ...current.sportLevels,
        [sport]: level
      }
    }));
  }

  function setAvailabilityByDay(nextAvailabilityByDay: Partial<Record<string, string[]>>) {
    const normalized = Object.fromEntries(
      Object.entries(nextAvailabilityByDay).filter(
        (entry): entry is [string, string[]] => Array.isArray(entry[1]) && entry[1].length > 0
      )
    );

    setDraft((current) => ({
      ...current,
      availabilityByDay: normalized,
      availableDays: Object.keys(normalized),
      availableTimeRanges: Array.from(
        new Set(
          Object.values(normalized)
            .flat()
            .filter((value): value is string => typeof value === "string")
        )
      )
    }));
  }

  async function requestCode(event: FormEvent) {
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

      if (!data.user.onboardingCompleted && guestDraftHasProfileBasics(draft)) {
        await apiFetch("/me", {
          method: "PATCH",
          body: JSON.stringify({
            name: draft.name.trim(),
            age: draft.age,
            gender: draft.gender ?? null,
            city: draft.city,
            district: draft.preferredDistricts[0] ?? draft.district ?? null,
            preferredDistricts: draft.preferredDistricts,
            tennisLevel: getPrimarySportLevel(draft.preferredSports, draft.sportLevels, draft.sportLevels[draft.preferredSports[0]] ?? 5),
            preferredSports: draft.preferredSports,
            sportLevels: draft.sportLevels,
            preferredPlayFormat: draft.preferredPlayFormat,
            preferredSurface: draft.preferredSurface,
            bio: "",
            avatarUrl: null,
            searchRadiusKm: draft.searchRadiusKm ?? 20,
            availableDays: draft.availableDays,
            availableTimeRanges: draft.availableTimeRanges,
            availabilityByDay: draft.availabilityByDay,
            isLookingForGame: draft.isLookingForGame,
            notificationGames: true,
            notificationMatches: true,
            notificationMessages: true,
            notificationSound: true
          })
        });
      }

      clearGuestOnboardingDraft();
      router.push(continueHref);
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось завершить вход");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="relative max-w-full space-y-2 overflow-x-clip overflow-y-visible">
      <div className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-48 rounded-[36px] bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.68),rgba(255,255,255,0.1)_42%,transparent_72%)] blur-2xl" />
      <div className="pointer-events-none absolute -right-10 top-20 -z-10 h-44 w-44 rounded-full bg-[rgba(201,109,66,0.18)] blur-3xl" />
      <div className="pointer-events-none absolute -left-8 top-36 -z-10 h-36 w-36 rounded-full bg-[rgba(95,165,139,0.16)] blur-3xl" />

      {step === "intro" ? (
        <div className="flex min-h-[calc(100svh-4.75rem)] flex-col gap-2">
          <section className="relative overflow-hidden rounded-[32px] border border-white/70 bg-white/38 p-3 shadow-[0_24px_70px_rgba(17,38,29,0.12)] backdrop-blur-2xl">
            <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(255,255,255,0.58),rgba(255,255,255,0.2))]" />
            <div className="relative space-y-2">
              <div className="inline-flex items-center gap-1.5 rounded-full border border-white/80 bg-white/65 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-ink/80">
                <Sparkles className="h-3 w-3 text-clay" />
                Быстрый старт
              </div>

              <div>
                <div className="max-w-[15rem] font-[var(--font-heading)] text-[1.72rem] font-bold leading-[0.98] text-ink">
                  <span className="block">Найди партнёра</span>
                  <span className="mt-1 block">
                    по{" "}
                    <span className="inline-flex min-h-[1.2em] w-[11ch] max-w-full items-center rounded-[16px] bg-white/72 px-2.5 py-0.5 text-clay shadow-[0_10px_24px_rgba(17,38,29,0.08)]">
                      <span className="inline-flex max-w-full items-center overflow-hidden whitespace-nowrap">
                        <span className="text-left">{typedSport || "\u00A0"}</span>
                        <span className="ml-0.5 inline-block h-6 w-[2px] animate-pulse rounded-full bg-clay/80" />
                      </span>
                    </span>
                  </span>
                </div>
                <p className="mt-1.5 max-w-sm text-[12px] leading-5 text-ink/70">
                  Подбор по спорту, уровню, району и времени. Срочные события, готовые поиски и быстрый выход в чат без лишних шагов.
                </p>
              </div>

              <div className="flex items-center justify-between rounded-[20px] border border-white/75 bg-[linear-gradient(180deg,rgba(255,255,255,0.78),rgba(255,255,255,0.5))] px-3 py-2 shadow-[inset_0_1px_0_rgba(255,255,255,0.62)]">
                <div className="min-w-0">
                  <div className="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-court">
                    <span className="relative flex h-2 w-2">
                      <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400/70" />
                      <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
                    </span>
                    Сейчас в приложении
                  </div>
                  <div className="mt-0.5 flex items-baseline gap-1.5">
                    <span className="text-[1.05rem] font-bold text-ink">{activePlayersCount}</span>
                    <span className="text-[11px] text-ink/60">игроков ищут игру</span>
                  </div>
                </div>
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[14px] bg-white/90 shadow-[0_10px_22px_rgba(17,38,29,0.08)]">
                  <Users className="h-3.5 w-3.5 text-court" />
                </div>
              </div>

              <DemoDiscoveryMap />
            </div>
          </section>

          <Panel className="border-white/70 bg-white/56 p-2.5 backdrop-blur-2xl">
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Следующий шаг</div>
              <div className="mt-0.5 text-[15px] font-bold text-ink">Сначала соберём твой игровой профиль</div>
              <div className="mt-1 text-[12px] leading-[1.15rem] text-ink/65">
              Ты укажешь вид спорта, уровень и удобное время. Email понадобится только когда захочешь реально связаться с другим игроком.
              </div>
              <Button type="button" fullWidth className="mt-2 min-h-10 rounded-[22px] text-[14px]" onClick={() => setStep("profile")}>
              Собрать профиль игрока
            </Button>
          </Panel>
        </div>
      ) : null}

      {step === "profile" ? (
        <>
          <Panel className="space-y-3 border-white/70 bg-white/56 p-3 backdrop-blur-2xl">
            <StepHeader
              step="Шаг 1 из 2"
              title="Соберём профиль игрока"
              subtitle="Начнём с базового профиля. Район и игровые детали можно спокойно настроить позже."
            />

            <div className="grid grid-cols-2 gap-2">
              <Field label="Имя">
                <input
                  required
                  value={draft.name}
                  onChange={(event) => setDraftField("name", event.target.value)}
                  className="input border-white/80 bg-white/78"
                  placeholder="Анна"
                />
              </Field>
              <Field label="Пол">
                <select
                  value={draft.gender ?? ""}
                  onChange={(event) => setDraftField("gender", (event.target.value || null) as Gender | null)}
                  className="input border-white/80 bg-white/78"
                >
                  <option value="">Не указывать</option>
                  <option value="male">Мужской</option>
                  <option value="female">Женский</option>
                </select>
              </Field>
              <Field label="Возраст" className="col-span-2">
                <AgeRibbonPicker
                  value={draft.age}
                  onChange={(age) => setDraftField("age", age)}
                />
              </Field>
            </div>

            <Field
              label="Виды спорта"
              action={
                <button
                  type="button"
                  onClick={() => setLevelGuideOpen(true)}
                  className="rounded-full bg-white/80 px-3 py-1 text-[11px] font-semibold text-court shadow-[0_8px_20px_rgba(17,38,29,0.06)] transition hover:bg-white"
                >
                  Как понять уровень?
                </button>
              }
            >
              <SportPicker
                multiple
                layout="carousel"
                value={draft.preferredSports}
                onChange={(value) => setPreferredSports(value as Sport[])}
                levels={draft.sportLevels}
                onLevelChange={(sport, level) => setSportLevel(sport, level)}
                showLevelHint
                showCarouselHint
              />
            </Field>

            <div className="rounded-[20px] bg-white/72 p-2.5">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold text-ink">Ищу игру сейчас</div>
                  <div className="mt-1 text-[11px] leading-[1.1rem] text-ink/60">Показывать меня в активном поиске.</div>
                </div>
                <button
                  type="button"
                  onClick={() => setDraftField("isLookingForGame", !draft.isLookingForGame)}
                  className={`flex h-8 w-14 items-center rounded-full p-1 transition ${draft.isLookingForGame ? "bg-court" : "bg-line"}`}
                >
                  <span
                    className={`h-6 w-6 rounded-full bg-white shadow transition ${draft.isLookingForGame ? "translate-x-6" : "translate-x-0"}`}
                  />
                </button>
              </div>
            </div>
          </Panel>

          <div className="flex gap-3">
            <Button type="button" fullWidth variant="ghost" className="min-h-10 rounded-[20px]" onClick={() => setStep("intro")}>
              Назад
            </Button>
            <Button type="button" fullWidth className="min-h-10 rounded-[20px]" onClick={() => setStep("availability")} disabled={!hasProfileBasics}>
              Дальше
            </Button>
          </div>
        </>
      ) : null}

      <SportLevelGuideSheet
        open={levelGuideOpen}
        onClose={() => setLevelGuideOpen(false)}
        sports={draft.preferredSports}
      />

      {step === "availability" ? (
        <>
          <Panel className="space-y-3 border-white/70 bg-white/56 p-3 backdrop-blur-2xl">
            <StepHeader
              step="Шаг 2 из 2"
              title="Когда тебе удобно играть"
              subtitle="Это можно указать сразу, чтобы подбор был точнее. Если не знаешь точно, этот шаг необязательный."
            />

            <Field label="Доступность">
              <AvailabilityPicker
                availabilityByDay={draft.availabilityByDay}
                onAvailabilityByDayChange={setAvailabilityByDay}
              />
            </Field>

            <div className="rounded-[20px] bg-white/72 p-2.5">
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">
                {hasAvailability ? "Выбрано" : "Можно заполнить позже"}
              </div>
              <div className="mt-1.5 flex flex-wrap gap-2 text-[11px]">
                {hasAvailability ? (
                  Object.entries(draft.availabilityByDay).map(([day, ranges]) => (
                    <span key={day} className="rounded-full bg-cream px-2.5 py-1.5 font-semibold text-ink">
                      {DAY_LABELS[day as keyof typeof DAY_LABELS]} · {(ranges ?? [])
                        .map((range) => TIME_RANGE_LABELS[range as keyof typeof TIME_RANGE_LABELS])
                        .join(", ")}
                    </span>
                  ))
                ) : (
                  <span className="rounded-full bg-cream px-2.5 py-1.5 font-semibold text-ink">Укажешь позже в профиле</span>
                )}
              </div>
            </div>
          </Panel>

          <div className="flex gap-3">
            <Button type="button" fullWidth variant="ghost" className="min-h-10 rounded-[20px]" onClick={() => setStep("profile")}>
              Назад
            </Button>
            <Button
              type="button"
              fullWidth
              className="min-h-10 rounded-[20px]"
              onClick={() => {
                saveGuestOnboardingDraft(draft);
                router.push("/discover");
              }}
            >
              Смотреть игроков
            </Button>
          </div>
          <Button type="button" fullWidth variant="ghost" className="min-h-10 rounded-[20px]" onClick={() => setStep("email")}>
            Подтвердить email сейчас
          </Button>
        </>
      ) : null}

      {step === "email" || step === "code" ? (
        <Panel className="border-white/70 bg-white/56 p-4 backdrop-blur-2xl">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div>
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">
                {step === "email" ? "Подтверждение почты" : "Подтверждение"}
              </div>
              <div className="mt-1 text-xl font-bold text-ink">
                {step === "email" ? "Осталось только подтвердить email" : "Введи код из письма"}
              </div>
            </div>
            <div className="inline-flex items-center gap-2 rounded-full bg-white/75 px-3 py-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-ink/60">
              <ShieldCheck className="h-3.5 w-3.5 text-court" />
              Без пароля
            </div>
          </div>

          {step === "email" ? (
            <form className="space-y-4" onSubmit={requestCode}>
              <div className="rounded-[24px] bg-white/72 p-4 text-sm leading-6 text-ink/68">
                Профиль уже собран. После подтверждения почты мы сразу сохраним его и вернём тебя к действию без повторного онбординга.
              </div>
              <label className="block">
                <div className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-ink/60">Почта</div>
                <input
                  required
                  type="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  className="input border-white/80 bg-white/78 text-ink placeholder:text-ink/35"
                  placeholder="player@email.com"
                />
              </label>
              <div className="flex gap-3">
                <Button type="button" fullWidth variant="ghost" className="min-h-12 rounded-[24px]" onClick={() => router.push("/discover")}>
                  Позже
                </Button>
                <Button type="submit" fullWidth className="min-h-12 rounded-[24px]" disabled={loading}>
                  {loading ? "Отправляем..." : "Получить код"}
                </Button>
              </div>
            </form>
          ) : (
            <form className="space-y-4" onSubmit={verify}>
              <div className="rounded-[24px] border border-white/80 bg-white/72 px-4 py-3 text-sm text-ink/72">
                Код отправлен на <span className="font-semibold text-ink">{email}</span>
                {debugCode ? <div className="mt-2 font-semibold text-clay">Демо-код: {debugCode}</div> : null}
              </div>
              <label className="block">
                <div className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-ink/60">Код подтверждения</div>
                <input
                  required
                  inputMode="numeric"
                  maxLength={6}
                  value={code}
                  onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
                  className="input border-white/80 bg-white/78 text-center text-xl tracking-[0.4em] text-ink placeholder:text-ink/25"
                  placeholder="000000"
                />
              </label>
              <div className="flex gap-3">
                <Button type="button" fullWidth variant="ghost" className="min-h-12 rounded-[24px]" onClick={() => setStep("email")}>
                  Изменить почту
                </Button>
                <Button type="submit" fullWidth className="min-h-12 rounded-[24px]" disabled={loading || code.length !== 6}>
                  {loading ? "Сохраняем..." : "Войти и открыть поиск"}
                </Button>
              </div>
            </form>
          )}

          {error ? <div className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
        </Panel>
      ) : null}
    </div>
  );
}

function DemoDiscoveryMap() {
  return (
    <div className="rounded-[28px] border border-white/75 bg-[linear-gradient(180deg,rgba(255,255,255,0.78),rgba(255,255,255,0.44))] p-2 shadow-[inset_0_1px_0_rgba(255,255,255,0.62)]">
      <YandexAuthDemoMap />
    </div>
  );
}

function StepHeader({
  step,
  title,
  subtitle
}: {
  step: string;
  title: string;
  subtitle: string;
}) {
  return (
    <div>
      <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">{step}</div>
      <div className="mt-1 text-xl font-bold text-ink">{title}</div>
      <div className="mt-1 text-sm leading-6 text-ink/65">{subtitle}</div>
    </div>
  );
}

function Field({
  label,
  action,
  children,
  className
}: {
  label: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={className ?? "block"}>
      <div className="mb-2 flex items-center justify-between gap-3">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">{label}</div>
        {action}
      </div>
      {children}
    </div>
  );
}
