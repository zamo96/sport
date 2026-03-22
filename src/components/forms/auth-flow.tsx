"use client";

import { type ReactNode, FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { PlayFormat, Surface, type Sport } from "@prisma/client";
import {
  CalendarClock,
  Flame,
  MapPin,
  MessageCircleHeart,
  ShieldCheck,
  Sparkles,
  Users
} from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import {
  DAY_LABELS,
  DEFAULT_CITY,
  type DistrictOption,
  DISTRICT_LABELS,
  DISTRICT_MAP_AREAS,
  DISTRICT_OPTIONS,
  PLAY_FORMAT_LABELS,
  SPORT_LABELS,
  SPORT_OPTIONS,
  SURFACE_LABELS,
  TIME_RANGE_LABELS
} from "@/lib/constants";
import { getPrimarySportLevel, normalizeSportLevels } from "@/lib/sport-levels";
import { AvailabilityPicker } from "@/components/forms/availability-picker";
import { SearchAreaMap } from "@/components/maps/search-area-map";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";
import { SportLevelsEditor } from "@/components/forms/sport-levels-editor";
import { SportPicker } from "@/components/forms/sport-picker";

type AuthFlowProps = {
  activePlayersCount: number;
};

type DraftProfile = {
  name: string;
  age: number;
  city: string;
  district: DistrictOption;
  preferredSports: Sport[];
  sportLevels: Partial<Record<Sport, number>>;
  preferredPlayFormat: PlayFormat;
  preferredSurface: Surface;
  searchRadiusKm: number;
  isLookingForGame: boolean;
  availableDays: string[];
  availableTimeRanges: string[];
  availabilityByDay: Partial<Record<string, string[]>>;
};

const ROTATING_SPORTS: Sport[] = ["tennis", "football", "padel", "volleyball", "boxing"];

export function AuthFlow({ activePlayersCount }: AuthFlowProps) {
  const router = useRouter();
  const [step, setStep] = useState<"intro" | "profile" | "availability" | "email" | "code">("intro");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [loading, setLoading] = useState(false);
  const [debugCode, setDebugCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [activeSportIndex, setActiveSportIndex] = useState(0);
  const [draft, setDraft] = useState<DraftProfile>({
    name: "",
    age: 28,
    city: DEFAULT_CITY,
    district: "central",
    preferredSports: ["tennis"],
    sportLevels: { tennis: 5 },
    preferredPlayFormat: PlayFormat.both,
    preferredSurface: Surface.any,
    searchRadiusKm: 20,
    isLookingForGame: true,
    availableDays: [],
    availableTimeRanges: [],
    availabilityByDay: {}
  });

  useEffect(() => {
    const interval = window.setInterval(() => {
      setActiveSportIndex((current) => (current + 1) % ROTATING_SPORTS.length);
    }, 1800);

    return () => window.clearInterval(interval);
  }, []);

  const currentSport = ROTATING_SPORTS[activeSportIndex];
  const districtCenter = DISTRICT_MAP_AREAS[draft.district].center;
  const hasProfileBasics = draft.name.trim().length >= 2 && draft.age >= 18 && draft.preferredSports.length > 0;
  const hasAvailability = Object.keys(draft.availabilityByDay).length > 0;

  const selectedSportsSummary = useMemo(
    () =>
      draft.preferredSports.map((sport) => ({
        sport,
        level: draft.sportLevels[sport] ?? 5
      })),
    [draft.preferredSports, draft.sportLevels]
  );

  function setDraftField<Key extends keyof DraftProfile>(key: Key, value: DraftProfile[Key]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  function setPreferredSports(nextSports: Sport[]) {
    const normalizedLevels = normalizeSportLevels(draft.sportLevels, nextSports, 5) as Partial<Record<Sport, number>>;

    setDraft((current) => ({
      ...current,
      preferredSports: nextSports,
      sportLevels: normalizedLevels
    }));
  }

  function setSportLevel(sport: Sport, level: number) {
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

      if (!data.user.onboardingCompleted) {
        await apiFetch("/me", {
          method: "PATCH",
          body: JSON.stringify({
            name: draft.name.trim(),
            age: draft.age,
            gender: null,
            city: draft.city,
            district: draft.district,
            tennisLevel: getPrimarySportLevel(draft.preferredSports, draft.sportLevels, draft.sportLevels[draft.preferredSports[0]] ?? 5),
            preferredSports: draft.preferredSports,
            sportLevels: draft.sportLevels,
            preferredPlayFormat: draft.preferredPlayFormat,
            preferredSurface: draft.preferredSurface,
            bio: "",
            avatarUrl: null,
            searchRadiusKm: draft.searchRadiusKm,
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

      router.push("/discover");
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось завершить вход");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="relative space-y-4 overflow-hidden">
      <div className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-48 rounded-[36px] bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.68),rgba(255,255,255,0.1)_42%,transparent_72%)] blur-2xl" />
      <div className="pointer-events-none absolute -right-10 top-20 -z-10 h-44 w-44 rounded-full bg-[rgba(201,109,66,0.18)] blur-3xl" />
      <div className="pointer-events-none absolute -left-8 top-36 -z-10 h-36 w-36 rounded-full bg-[rgba(95,165,139,0.16)] blur-3xl" />

      {step === "intro" ? (
        <>
          <section className="relative overflow-hidden rounded-[34px] border border-white/70 bg-white/38 p-4 shadow-[0_24px_70px_rgba(17,38,29,0.12)] backdrop-blur-2xl">
            <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(255,255,255,0.58),rgba(255,255,255,0.2))]" />
            <div className="relative space-y-4">
              <div className="inline-flex items-center gap-2 rounded-full border border-white/80 bg-white/65 px-3 py-1.5 text-[11px] font-semibold uppercase tracking-[0.24em] text-ink/80">
                <Sparkles className="h-3.5 w-3.5 text-clay" />
                Быстрый старт
              </div>

              <div>
                <div className="max-w-sm font-[var(--font-heading)] text-[2.3rem] font-bold leading-[0.96] text-ink">
                  Найди партнёра по{" "}
                  <span
                    key={currentSport}
                    className="inline-block rounded-[18px] bg-white/72 px-3 py-1 text-clay shadow-[0_10px_24px_rgba(17,38,29,0.08)] transition-all duration-300"
                  >
                    {SPORT_LABELS[currentSport]}
                  </span>
                </div>
                <p className="mt-3 max-w-sm text-[15px] leading-7 text-ink/72">
                  Подбор по спорту, уровню, району и времени. Срочные события, готовые поиски и быстрый выход в чат без лишних шагов.
                </p>
              </div>

              <div className="flex items-center justify-between rounded-[28px] border border-white/75 bg-[linear-gradient(180deg,rgba(255,255,255,0.76),rgba(255,255,255,0.44))] p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.62)]">
                <div className="min-w-0">
                  <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Сейчас в приложении</div>
                  <div className="mt-1 text-2xl font-bold text-ink">{activePlayersCount}</div>
                  <div className="mt-1 text-sm text-ink/62">игроков прямо сейчас ищут игру или активны в поиске</div>
                </div>
                <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-[20px] bg-white/85 shadow-[0_12px_28px_rgba(17,38,29,0.08)]">
                  <Users className="h-6 w-6 text-court" />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <GlassStat
                  icon={<MessageCircleHeart className="h-4 w-4 text-court" />}
                  title="Быстрый мэтч"
                  text="Лайк, ответный лайк и сразу общий чат."
                />
                <GlassStat
                  icon={<Flame className="h-4 w-4 text-red-500" />}
                  title="Срочно сегодня"
                  text="Если игрок сорвался, быстро находишь замену."
                />
                <GlassStat
                  icon={<MapPin className="h-4 w-4 text-blue-500" />}
                  title="Клуб и карта"
                  text="Сразу видно, где играть и что уже выбрано."
                />
                <GlassStat
                  icon={<CalendarClock className="h-4 w-4 text-emerald-600" />}
                  title="Время и район"
                  text="Подбор по доступности и близости к твоей точке."
                />
              </div>
            </div>
          </section>

          <Panel className="border-white/70 bg-white/56 p-4 backdrop-blur-2xl">
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Следующий шаг</div>
            <div className="mt-1 text-xl font-bold text-ink">Сначала соберём твой игровой профиль</div>
            <div className="mt-2 text-sm leading-6 text-ink/65">
              Ты укажешь вид спорта, уровень, район и удобное время. Email понадобится только в самом конце.
            </div>
            <Button type="button" fullWidth className="mt-4 min-h-14 rounded-[24px] text-base" onClick={() => setStep("profile")}>
              Собрать профиль игрока
            </Button>
          </Panel>
        </>
      ) : null}

      {step === "profile" ? (
        <>
          <Panel className="space-y-5 border-white/70 bg-white/56 p-4 backdrop-blur-2xl">
            <StepHeader
              step="Шаг 1 из 3"
              title="Соберём профиль игрока"
              subtitle="Эти данные нужны, чтобы сразу показать тебе релевантных людей и события."
            />

            <div className="grid grid-cols-2 gap-3">
              <Field label="Имя">
                <input
                  required
                  value={draft.name}
                  onChange={(event) => setDraftField("name", event.target.value)}
                  className="input border-white/80 bg-white/78"
                  placeholder="Анна"
                />
              </Field>
              <Field label="Возраст">
                <input
                  required
                  type="number"
                  min={18}
                  max={70}
                  value={draft.age}
                  onChange={(event) => setDraftField("age", Number(event.target.value))}
                  className="input border-white/80 bg-white/78"
                />
              </Field>
            </div>

            <Field label="Район">
              <div className="grid grid-cols-2 gap-2">
                {DISTRICT_OPTIONS.map((district) => (
                  <button
                    key={district}
                    type="button"
                    onClick={() => setDraftField("district", district)}
                    className={`rounded-[20px] border px-3 py-3 text-left text-sm font-semibold transition ${
                      draft.district === district ? "border-ink bg-ink text-white" : "border-white/60 bg-white/72 text-ink"
                    }`}
                  >
                    {DISTRICT_LABELS[district]}
                  </button>
                ))}
              </div>
            </Field>

            <Field label="Виды спорта">
              <SportPicker
                multiple
                value={draft.preferredSports}
                onChange={(value) => setPreferredSports(value as Sport[])}
              />
            </Field>

            <Field label="Уровень по каждому спорту">
              <SportLevelsEditor
                sports={draft.preferredSports}
                values={draft.sportLevels}
                onChange={(sport, level) => setSportLevel(sport, level)}
              />
            </Field>

            <Field label={`Радиус ${draft.searchRadiusKm} км`}>
              <input
                type="range"
                min={1}
                max={100}
                value={draft.searchRadiusKm}
                onChange={(event) => setDraftField("searchRadiusKm", Number(event.target.value))}
                className="mt-3 w-full accent-court"
              />
            </Field>

            <Field label="Район и радиус поиска">
              <SearchAreaMap
                centerLat={districtCenter.lat}
                centerLng={districtCenter.lng}
                radiusKm={draft.searchRadiusKm}
                city={draft.city}
                district={draft.district}
                isApproximate={false}
              />
              <div className="mt-2 text-xs leading-5 text-ink/55">
                {`Сейчас показываем радиус ${draft.searchRadiusKm} км вокруг района ${DISTRICT_LABELS[draft.district]}.`}
              </div>
            </Field>

            <div className="grid grid-cols-2 gap-3">
              <Field label="Формат игры">
                <select
                  value={draft.preferredPlayFormat}
                  onChange={(event) => setDraftField("preferredPlayFormat", event.target.value as PlayFormat)}
                  className="input border-white/80 bg-white/78"
                >
                  {Object.entries(PLAY_FORMAT_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Покрытие">
                <select
                  value={draft.preferredSurface}
                  onChange={(event) => setDraftField("preferredSurface", event.target.value as Surface)}
                  className="input border-white/80 bg-white/78"
                >
                  {Object.entries(SURFACE_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
            </div>

            <div className="rounded-[24px] bg-white/72 p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold text-ink">Ищу игру сейчас</div>
                  <div className="mt-1 text-xs leading-5 text-ink/60">
                    Ты появишься в списке игроков, которые сейчас открыты к игре.
                  </div>
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
            <Button type="button" fullWidth variant="ghost" className="min-h-12 rounded-[24px]" onClick={() => setStep("intro")}>
              Назад
            </Button>
            <Button type="button" fullWidth className="min-h-12 rounded-[24px]" onClick={() => setStep("availability")} disabled={!hasProfileBasics}>
              Дальше
            </Button>
          </div>
        </>
      ) : null}

      {step === "availability" ? (
        <>
          <Panel className="space-y-5 border-white/70 bg-white/56 p-4 backdrop-blur-2xl">
            <StepHeader
              step="Шаг 2 из 3"
              title="Когда тебе удобно играть"
              subtitle="Это можно указать сразу, чтобы подбор был точнее. Если не знаешь точно, этот шаг необязательный."
            />

            <Field label="Доступность">
              <AvailabilityPicker
                availabilityByDay={draft.availabilityByDay}
                onAvailabilityByDayChange={setAvailabilityByDay}
              />
            </Field>

            <div className="rounded-[24px] bg-white/72 p-4">
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">
                {hasAvailability ? "Выбрано" : "Можно заполнить позже"}
              </div>
              <div className="mt-3 flex flex-wrap gap-2 text-xs">
                {hasAvailability ? (
                  Object.entries(draft.availabilityByDay).map(([day, ranges]) => (
                    <span key={day} className="rounded-full bg-cream px-3 py-2 font-semibold text-ink">
                      {DAY_LABELS[day as keyof typeof DAY_LABELS]} · {(ranges ?? [])
                        .map((range) => TIME_RANGE_LABELS[range as keyof typeof TIME_RANGE_LABELS])
                        .join(", ")}
                    </span>
                  ))
                ) : (
                  <span className="rounded-full bg-cream px-3 py-2 font-semibold text-ink">Укажешь позже в профиле</span>
                )}
              </div>
            </div>

            <div className="rounded-[24px] bg-white/72 p-4">
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Твой профиль</div>
              <div className="mt-3 flex flex-wrap gap-2">
                {selectedSportsSummary.map(({ sport, level }) => (
                  <SportLevelBadge
                    key={sport}
                    sport={sport}
                    level={level}
                    badgeClassName="bg-cream text-ink"
                    levelClassName="bg-cream text-ink"
                  />
                ))}
              </div>
            </div>
          </Panel>

          <div className="flex gap-3">
            <Button type="button" fullWidth variant="ghost" className="min-h-12 rounded-[24px]" onClick={() => setStep("profile")}>
              Назад
            </Button>
            <Button type="button" fullWidth className="min-h-12 rounded-[24px]" onClick={() => setStep("email")}>
              Перейти к входу
            </Button>
          </div>
        </>
      ) : null}

      {step === "email" || step === "code" ? (
        <Panel className="border-white/70 bg-white/56 p-4 backdrop-blur-2xl">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div>
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">
                {step === "email" ? "Шаг 3 из 3" : "Подтверждение"}
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
                Профиль уже собран. После подтверждения почты мы сразу сохраним его и откроем поиск игроков.
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
                <Button type="button" fullWidth variant="ghost" className="min-h-12 rounded-[24px]" onClick={() => setStep("availability")}>
                  Назад
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

function GlassStat({
  icon,
  title,
  text
}: {
  icon: ReactNode;
  title: string;
  text: string;
}) {
  return (
    <div className="rounded-[24px] border border-white/75 bg-[linear-gradient(180deg,rgba(255,255,255,0.7),rgba(255,255,255,0.34))] p-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.55)]">
      <div className="inline-flex h-9 w-9 items-center justify-center rounded-2xl bg-white/80 shadow-[0_10px_24px_rgba(17,38,29,0.08)]">
        {icon}
      </div>
      <div className="mt-3 text-sm font-bold text-ink">{title}</div>
      <div className="mt-1 text-xs leading-5 text-ink/62">{text}</div>
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
  children
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <label className="block">
      <div className="mb-2 text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">{label}</div>
      {children}
    </label>
  );
}
