"use client";

import { ChangeEvent, FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { PlayFormat, Surface, type Gender, type Sport, type User } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import {
  AVAILABLE_CITIES,
  DAY_LABELS,
  DEFAULT_CITY,
  PLAY_FORMAT_LABELS,
  SPORT_OPTIONS,
  SURFACE_LABELS,
  TIME_RANGE_LABELS
} from "@/lib/constants";
import { getPrimarySportLevel, normalizeSportLevels, normalizeSports, syncSportLevels } from "@/lib/sport-levels";
import { AvailabilityPicker } from "@/components/forms/availability-picker";
import { SportPicker } from "@/components/forms/sport-picker";
import { SportLevelsEditor } from "@/components/forms/sport-levels-editor";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";

type ProfilePayload = Pick<
  User,
  | "name"
  | "age"
  | "gender"
  | "city"
  | "tennisLevel"
  | "preferredPlayFormat"
  | "preferredSurface"
  | "bio"
  | "avatarUrl"
  | "searchRadiusKm"
  | "isLookingForGame"
  | "notificationGames"
  | "notificationMatches"
  | "notificationMessages"
> & {
  preferredSports: SportOption[];
  sportLevels: Partial<Record<SportOption, number>>;
  availableDays: string[];
  availableTimeRanges: string[];
};

type SportOption = (typeof SPORT_OPTIONS)[number];

export function ProfileForm({
  user,
  mode = "profile"
}: {
  user: Partial<User> & {
    availableDays?: unknown;
    availableTimeRanges?: unknown;
    preferredSports?: unknown;
    sportLevels?: unknown;
  };
  mode?: "onboarding" | "profile";
}) {
  const router = useRouter();
  const isOnboarding = mode === "onboarding";
  const initialPreferredSports = normalizeSports(user.preferredSports) as SportOption[];
  const initialSportLevels = normalizeSportLevels(user.sportLevels, initialPreferredSports, user.tennisLevel ?? 5) as Partial<
    Record<SportOption, number>
  >;
  const [form, setForm] = useState<ProfilePayload>({
    name: user.name ?? "",
    age: user.age ?? 28,
    gender: (user.gender as Gender | null | undefined) ?? null,
    city: DEFAULT_CITY,
    tennisLevel: getPrimarySportLevel(initialPreferredSports, initialSportLevels, user.tennisLevel ?? 5),
    preferredSports: initialPreferredSports,
    sportLevels: initialSportLevels,
    preferredPlayFormat: user.preferredPlayFormat ?? PlayFormat.both,
    preferredSurface: user.preferredSurface ?? Surface.any,
    bio: user.bio ?? "",
    avatarUrl: user.avatarUrl ?? null,
    searchRadiusKm: user.searchRadiusKm ?? 20,
    availableDays: Array.isArray(user.availableDays)
      ? user.availableDays.filter((slot): slot is string => typeof slot === "string")
      : [],
    availableTimeRanges: Array.isArray(user.availableTimeRanges)
      ? user.availableTimeRanges.filter((slot): slot is string => typeof slot === "string")
      : [],
    isLookingForGame: user.isLookingForGame ?? true,
    notificationGames: user.notificationGames ?? true,
    notificationMatches: user.notificationMatches ?? true,
    notificationMessages: user.notificationMessages ?? true
  });
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function setField<Key extends keyof ProfilePayload>(key: Key, value: ProfilePayload[Key]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  function setPreferredSports(nextSports: SportOption[]) {
    if (nextSports.length === 0) {
      setForm((current) => ({
        ...current,
        preferredSports: [],
        sportLevels: {}
      }));
      return;
    }

    const nextSportLevels = syncSportLevels(nextSports as Sport[], form.sportLevels, form.tennisLevel ?? 5) as Partial<
      Record<SportOption, number>
    >;

    setForm((current) => ({
      ...current,
      preferredSports: nextSports,
      sportLevels: nextSportLevels,
      tennisLevel: getPrimarySportLevel(nextSports, nextSportLevels, current.tennisLevel ?? 5)
    }));
  }

  function setSportLevel(sport: SportOption, level: number) {
    setForm((current) => {
      const nextSportLevels = {
        ...current.sportLevels,
        [sport]: level
      };

      return {
        ...current,
        sportLevels: nextSportLevels,
        tennisLevel: getPrimarySportLevel(current.preferredSports, nextSportLevels, level)
      };
    });
  }

  const hasAvailability = form.availableDays.length > 0 && form.availableTimeRanges.length > 0;
  const canContinueBasics = (form.name ?? "").trim().length >= 2 && (form.city ?? "").trim().length >= 2 && (form.age ?? 0) >= 18;
  const hasSports = Array.isArray(form.preferredSports) && form.preferredSports.length > 0;

  function nextStep() {
    setStep((current) => (current < 3 ? ((current + 1) as 1 | 2 | 3) : current));
  }

  function prevStep() {
    setStep((current) => (current > 1 ? ((current - 1) as 1 | 2 | 3) : current));
  }

  async function handleAvatarUpload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setError(null);
    try {
      const payload = new FormData();
      payload.append("file", file);
      const response = await fetch("/uploads/avatar", {
        method: "POST",
        body: payload
      });
      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error ?? "Не удалось загрузить фото");
      }
      setField("avatarUrl", data.avatarUrl);
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "Не удалось загрузить фото");
    } finally {
      setUploading(false);
    }
  }

  async function finishOnboarding(skipAvailability = false) {
    setLoading(true);
    setError(null);

    try {
      await apiFetch("/me", {
        method: "PATCH",
        body: JSON.stringify({
          ...form,
          tennisLevel: getPrimarySportLevel(form.preferredSports, form.sportLevels, form.tennisLevel ?? 5),
          availableDays: skipAvailability ? [] : form.availableDays,
          availableTimeRanges: skipAvailability ? [] : form.availableTimeRanges
        })
      });
      router.push("/discover");
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось сохранить профиль");
    } finally {
      setLoading(false);
    }
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();

    if (isOnboarding) {
      event.preventDefault();
      await finishOnboarding(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await apiFetch("/me", {
        method: "PATCH",
        body: JSON.stringify({
          ...form,
          tennisLevel: getPrimarySportLevel(form.preferredSports, form.sportLevels, form.tennisLevel ?? 5)
        })
      });
      router.push("/profile");
      router.refresh();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось сохранить профиль");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="space-y-4" onSubmit={handleSubmit}>
      {isOnboarding ? (
        <>
          <Panel className="space-y-5">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">Шаг {step} из 3</div>
                <div className="mt-1 text-lg font-bold text-ink">
                  {step === 1
                    ? "Расскажи о себе"
                    : step === 2
                      ? "Какой спорт и как тебе удобно играть"
                      : "Когда тебе удобно"}
                </div>
                <div className="mt-1 text-sm text-ink/65">
                  {step === 1
                    ? "Только базовая информация, чтобы сразу начать."
                    : step === 2
                      ? "Эти параметры влияют на подбор игроков."
                      : "Этот шаг необязательный. Можно указать позже в профиле."}
                </div>
              </div>
              <div className="flex gap-2">
                {[1, 2, 3].map((index) => (
                  <span
                    key={index}
                    className={`h-2.5 w-8 rounded-full ${step >= index ? "bg-court" : "bg-line"}`}
                  />
                ))}
              </div>
            </div>

            {step === 1 ? (
              <div className="grid grid-cols-2 gap-3">
                <Field label="Имя">
                  <input
                    required
                    value={form.name ?? ""}
                    onChange={(event) => setField("name", event.target.value)}
                    className="input"
                    placeholder="Анна"
                  />
                </Field>
                <Field label="Возраст">
                  <input
                    required
                    type="number"
                    min={18}
                    max={70}
                    value={form.age ?? 18}
                    onChange={(event) => setField("age", Number(event.target.value))}
                    className="input"
                  />
                </Field>
                <Field label="Город" className="col-span-2">
                  <select
                    required
                    value={form.city ?? DEFAULT_CITY}
                    onChange={(event) => setField("city", event.target.value)}
                    className="input cursor-not-allowed bg-line/50 text-ink/70"
                    disabled
                  >
                    {AVAILABLE_CITIES.map((city) => (
                      <option key={city} value={city}>
                        {city}
                      </option>
                    ))}
                  </select>
                  <div className="mt-2 text-xs leading-5 text-ink/55">Пока запускаемся только в Санкт-Петербурге.</div>
                </Field>
              </div>
            ) : null}

            {step === 2 ? (
              <div className="space-y-4">
                  <Field label="Виды спорта">
                    <SportPicker
                      multiple
                      value={form.preferredSports}
                      onChange={(value) => setPreferredSports(value as ProfilePayload["preferredSports"])}
                    />
                  </Field>

                <div className="grid grid-cols-1 gap-3">
                  <Field label="Уровень по каждому спорту">
                    <SportLevelsEditor
                      sports={form.preferredSports as Sport[]}
                      values={form.sportLevels as Partial<Record<Sport, number>>}
                      onChange={(sport, level) => setSportLevel(sport as SportOption, level)}
                    />
                  </Field>
                </div>

                <div className="grid grid-cols-1 gap-3">
                  <Field label={`Радиус ${form.searchRadiusKm} км`}>
                    <input
                      type="range"
                      min={1}
                      max={100}
                      value={form.searchRadiusKm}
                      onChange={(event) => setField("searchRadiusKm", Number(event.target.value))}
                      className="mt-3 w-full accent-court"
                    />
                  </Field>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <Field label="Формат игры">
                    <select
                      value={form.preferredPlayFormat}
                      onChange={(event) =>
                        setField("preferredPlayFormat", event.target.value as ProfilePayload["preferredPlayFormat"])
                      }
                      className="input"
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
                      value={form.preferredSurface}
                      onChange={(event) =>
                        setField("preferredSurface", event.target.value as ProfilePayload["preferredSurface"])
                      }
                      className="input"
                    >
                      {Object.entries(SURFACE_LABELS).map(([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ))}
                    </select>
                  </Field>
                </div>

                <div className="rounded-[24px] bg-cream p-4">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <div className="text-sm font-semibold text-ink">Ищу игру сейчас</div>
                      <div className="mt-1 text-xs leading-5 text-ink/60">
                        Ты появишься во вкладке игроков, которые активно ищут партнера.
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={() => setField("isLookingForGame", !form.isLookingForGame)}
                      className={`flex h-8 w-14 items-center rounded-full p-1 transition ${form.isLookingForGame ? "bg-court" : "bg-line"}`}
                    >
                      <span
                        className={`h-6 w-6 rounded-full bg-white shadow transition ${form.isLookingForGame ? "translate-x-6" : "translate-x-0"}`}
                      />
                    </button>
                  </div>
                </div>
              </div>
            ) : null}

            {step === 3 ? (
              <div className="space-y-4">
                <div className="rounded-[24px] bg-cream p-4 text-sm leading-6 text-ink/70">
                  Укажи дни и интервалы времени, если уже знаешь их. Если нет, просто заверши онбординг и вернись к
                  этому позже в профиле.
                </div>
                <Field label="Доступность">
                  <AvailabilityPicker
                    days={form.availableDays}
                    timeRanges={form.availableTimeRanges}
                    onDaysChange={(value) => setField("availableDays", value)}
                    onTimeRangesChange={(value) => setField("availableTimeRanges", value)}
                  />
                </Field>
                <div className="rounded-[24px] bg-mint/60 p-4">
                  <div className="text-xs font-semibold uppercase tracking-[0.2em] text-court">
                    {hasAvailability ? "Выбрано" : "Пока не указано"}
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2 text-xs">
                    {hasAvailability ? (
                      <>
                        {form.availableDays.map((day) => (
                          <span key={day} className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                            {DAY_LABELS[day as keyof typeof DAY_LABELS]}
                          </span>
                        ))}
                        {form.availableTimeRanges.map((timeRange) => (
                          <span key={timeRange} className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                            {TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]}
                          </span>
                        ))}
                      </>
                    ) : (
                      <span className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                        Заполни позже в профиле
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ) : null}
          </Panel>

          <div className="flex gap-3">
            {step > 1 ? (
              <Button type="button" fullWidth variant="ghost" onClick={prevStep} disabled={loading}>
                Назад
              </Button>
            ) : null}

            {step < 3 ? (
              <Button
                type="button"
                fullWidth
                onClick={nextStep}
                disabled={(step === 1 && !canContinueBasics) || (step === 2 && !hasSports)}
              >
                Далее
              </Button>
            ) : (
              <>
                <Button
                  type="button"
                  fullWidth
                  variant="ghost"
                  onClick={() => finishOnboarding(true)}
                  disabled={loading}
                >
                  Пропустить пока
                </Button>
                <Button type="submit" fullWidth disabled={loading}>
                  {loading ? "Сохраняем..." : "Начать поиск"}
                </Button>
              </>
            )}
          </div>
        </>
      ) : (
        <>
          <Panel>
            <div className="mb-5 flex items-center gap-4">
              <Avatar src={form.avatarUrl} alt={form.name || "Игрок"} size="xl" />
              <div className="flex-1">
                <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">Фото</div>
                <div className="mt-1 text-lg font-bold text-ink">Редактирование карточки игрока</div>
                <label className="mt-3 inline-flex cursor-pointer rounded-2xl bg-mint px-4 py-3 text-sm font-semibold text-ink">
                  {uploading ? "Загрузка..." : "Загрузить фото"}
                  <input type="file" accept="image/*" className="hidden" onChange={handleAvatarUpload} />
                </label>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <Field label="Имя">
                <input
                  required
                  value={form.name ?? ""}
                  onChange={(event) => setField("name", event.target.value)}
                  className="input"
                  placeholder="Анна"
                />
              </Field>
              <Field label="Возраст">
                <input
                  required
                  type="number"
                  min={18}
                  max={70}
                  value={form.age ?? 18}
                  onChange={(event) => setField("age", Number(event.target.value))}
                  className="input"
                />
              </Field>
            </div>

            <div className="mt-3 grid grid-cols-2 gap-3">
              <Field label="Город">
                <select
                  required
                  value={form.city ?? DEFAULT_CITY}
                  onChange={(event) => setField("city", event.target.value)}
                  className="input cursor-not-allowed bg-line/50 text-ink/70"
                  disabled
                >
                  {AVAILABLE_CITIES.map((city) => (
                    <option key={city} value={city}>
                      {city}
                    </option>
                  ))}
                </select>
                <div className="mt-2 text-xs leading-5 text-ink/55">Пока только Санкт-Петербург.</div>
              </Field>
              <Field label="Пол">
                <select
                  value={form.gender ?? ""}
                  onChange={(event) =>
                    setField("gender", (event.target.value || null) as ProfilePayload["gender"])
                  }
                  className="input"
                >
                  <option value="">Не указывать</option>
                  <option value="male">Мужской</option>
                  <option value="female">Женский</option>
                  <option value="other">Другой</option>
                </select>
              </Field>
            </div>

            <div className="mt-3 grid grid-cols-2 gap-3">
                <Field label="Виды спорта" className="col-span-2">
                <SportPicker
                  multiple
                  value={form.preferredSports}
                  onChange={(value) => setPreferredSports(value as ProfilePayload["preferredSports"])}
                />
              </Field>
              <Field label={`Радиус ${form.searchRadiusKm} км`}>
                <input
                  type="range"
                  min={1}
                  max={100}
                  value={form.searchRadiusKm}
                  onChange={(event) => setField("searchRadiusKm", Number(event.target.value))}
                  className="mt-3 w-full accent-court"
                />
              </Field>
            </div>

            <Field label="Уровни по видам спорта" className="mt-3">
              <SportLevelsEditor
                sports={form.preferredSports as Sport[]}
                values={form.sportLevels as Partial<Record<Sport, number>>}
                onChange={(sport, level) => setSportLevel(sport as SportOption, level)}
              />
            </Field>

            <div className="mt-3 grid grid-cols-2 gap-3">
              <Field label="Формат игры">
                <select
                  value={form.preferredPlayFormat}
                  onChange={(event) =>
                    setField("preferredPlayFormat", event.target.value as ProfilePayload["preferredPlayFormat"])
                  }
                  className="input"
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
                  value={form.preferredSurface}
                  onChange={(event) =>
                    setField("preferredSurface", event.target.value as ProfilePayload["preferredSurface"])
                  }
                  className="input"
                >
                  {Object.entries(SURFACE_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
            </div>

            <Field label="Доступность" className="mt-3">
              <AvailabilityPicker
                days={form.availableDays}
                timeRanges={form.availableTimeRanges}
                onDaysChange={(value) => setField("availableDays", value)}
                onTimeRangesChange={(value) => setField("availableTimeRanges", value)}
              />
            </Field>

            <div className="mt-3 rounded-[24px] bg-cream p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold text-ink">Ищу игру сейчас</div>
                  <div className="mt-1 text-xs leading-5 text-ink/60">
                    Показывает тебя в отдельной вкладке с активными игроками.
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setField("isLookingForGame", !form.isLookingForGame)}
                  className={`flex h-8 w-14 items-center rounded-full p-1 transition ${form.isLookingForGame ? "bg-court" : "bg-line"}`}
                >
                  <span
                    className={`h-6 w-6 rounded-full bg-white shadow transition ${form.isLookingForGame ? "translate-x-6" : "translate-x-0"}`}
                  />
                </button>
              </div>
              <div className="mt-3 flex flex-wrap gap-2 text-xs">
                {form.preferredSports.map((sport) => (
                  <SportLevelBadge
                    key={sport}
                    sport={sport as Sport}
                    level={form.sportLevels[sport] ?? form.tennisLevel ?? 5}
                    badgeClassName="bg-white text-ink"
                    levelClassName="bg-white text-ink"
                  />
                ))}
                {hasAvailability ? (
                  <>
                    {form.availableDays.map((day) => (
                      <span key={day} className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                        {DAY_LABELS[day as keyof typeof DAY_LABELS]}
                      </span>
                    ))}
                    {form.availableTimeRanges.map((timeRange) => (
                      <span key={timeRange} className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                        {TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]}
                      </span>
                    ))}
                  </>
                ) : (
                  <span className="rounded-full bg-white px-3 py-2 font-semibold text-ink">Не указано</span>
                )}
              </div>
            </div>

            <Field label="Коротко о себе" className="mt-3">
              <textarea
                rows={4}
                value={form.bio ?? ""}
                onChange={(event) => setField("bio", event.target.value)}
                className="input min-h-[112px] resize-none py-3"
                placeholder="Люблю интенсивные розыгрыши и вечерние тренировки, ищу постоянных партнеров."
              />
            </Field>
          </Panel>

          <Button type="submit" fullWidth disabled={loading || uploading}>
            {loading ? "Сохраняем..." : "Сохранить профиль"}
          </Button>
        </>
      )}

      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
    </form>
  );
}

function Field({
  label,
  children,
  className
}: {
  label: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <label className={className}>
      <div className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-ink/55">{label}</div>
      {children}
    </label>
  );
}
