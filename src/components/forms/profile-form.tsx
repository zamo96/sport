"use client";

import { ChangeEvent, FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { PlayFormat, Surface, type Gender, type Sport, type User } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { saveGuestOnboardingDraft, type GuestOnboardingDraft } from "@/lib/guest-draft";
import {
  AVAILABLE_CITIES,
  DAY_LABELS,
  DEFAULT_CITY,
  DEFAULT_CITY_COORDINATES,
  type DistrictOption,
  DISTRICT_OPTIONS,
  getDistrictArea,
  getDistrictLabel,
  PLAY_FORMAT_LABELS,
  SPORT_OPTIONS,
  SURFACE_LABELS,
  TIME_RANGE_LABELS
} from "@/lib/constants";
import {
  getPrimarySportLevel,
  normalizeSportLevels,
  normalizeSports,
  type SportLevelValue
} from "@/lib/sport-levels";
import { AvailabilityPicker } from "@/components/forms/availability-picker";
import { AgeRibbonPicker } from "@/components/forms/age-ribbon-picker";
import { SportPicker } from "@/components/forms/sport-picker";
import { SearchAreaMap } from "@/components/maps/search-area-map";
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
  district: DistrictOption | null;
  preferredSports: SportOption[];
  sportLevels: Partial<Record<SportOption, SportLevelValue>>;
  availableDays: string[];
  availableTimeRanges: string[];
  availabilityByDay: Partial<Record<string, string[]>>;
};

type SportOption = (typeof SPORT_OPTIONS)[number];

export function ProfileForm({
  user,
  mode = "profile",
  authRequiredHref
}: {
  user: Partial<User> & {
    availableDays?: unknown;
    availableTimeRanges?: unknown;
    availabilityByDay?: unknown;
    preferredSports?: unknown;
    sportLevels?: unknown;
  };
  mode?: "onboarding" | "profile" | "guest";
  authRequiredHref?: string;
}) {
  const router = useRouter();
  const isOnboarding = mode === "onboarding";
  const isGuest = mode === "guest";
  const initialPreferredSports = normalizeSports(user.preferredSports) as SportOption[];
  const initialSportLevels = normalizeSportLevels(user.sportLevels, initialPreferredSports, user.tennisLevel ?? 5) as Partial<
    Record<SportOption, SportLevelValue>
  >;
  const initialAvailabilityByDay = normalizeAvailabilityByDay(user.availabilityByDay, user.availableDays, user.availableTimeRanges);
  const [form, setForm] = useState<ProfilePayload>({
    name: user.name ?? "",
    age: user.age ?? 28,
    gender: (user.gender as Gender | null | undefined) ?? null,
    city: DEFAULT_CITY,
    district: (user.district as ProfilePayload["district"]) ?? null,
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
    availabilityByDay: initialAvailabilityByDay,
    isLookingForGame: user.isLookingForGame ?? true,
    notificationGames: user.notificationGames ?? true,
    notificationMatches: user.notificationMatches ?? true,
    notificationMessages: user.notificationMessages ?? true
  });
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const selectedDistrictCenter = getDistrictArea(form.district)?.center ?? DEFAULT_CITY_COORDINATES;
  const searchCenterLat = selectedDistrictCenter.lat;
  const searchCenterLng = selectedDistrictCenter.lng;
  const isApproximateSearchArea = !form.district;

  function setField<Key extends keyof ProfilePayload>(key: Key, value: ProfilePayload[Key]) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  useEffect(() => {
    if (!isGuest) {
      return;
    }

    saveGuestOnboardingDraft(toGuestDraft(form));
  }, [form, isGuest]);

  function setAvailabilityByDay(nextAvailabilityByDay: ProfilePayload["availabilityByDay"]) {
    const normalized = Object.fromEntries(
      Object.entries(nextAvailabilityByDay).filter((entry): entry is [string, string[]] => Array.isArray(entry[1]) && entry[1].length > 0)
    );

    setForm((current) => ({
      ...current,
      availabilityByDay: normalized,
      availableDays: Object.keys(normalized),
      availableTimeRanges: Array.from(new Set(Object.values(normalized).flat()))
    }));
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

    const nextSportLevels = Object.fromEntries(
      nextSports.map((sport) => {
        if (Object.prototype.hasOwnProperty.call(form.sportLevels, sport)) {
          return [sport, form.sportLevels[sport] ?? null];
        }

        return [sport, null];
      })
    ) as Partial<Record<SportOption, SportLevelValue>>;

    setForm((current) => ({
      ...current,
      preferredSports: nextSports,
      sportLevels: nextSportLevels,
      tennisLevel: getPrimarySportLevel(nextSports, nextSportLevels, current.tennisLevel ?? 5)
    }));
  }

  function setSportLevel(sport: SportOption, level: SportLevelValue) {
    setForm((current) => {
      const nextSportLevels = {
        ...current.sportLevels,
        [sport]: level
      };

      return {
        ...current,
        sportLevels: nextSportLevels,
        tennisLevel: getPrimarySportLevel(
          current.preferredSports,
          nextSportLevels,
          typeof level === "number" ? level : current.tennisLevel ?? 5
        )
      };
    });
  }

  const hasAvailability = Object.keys(form.availabilityByDay).length > 0;
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
          availableTimeRanges: skipAvailability ? [] : form.availableTimeRanges,
          availabilityByDay: skipAvailability ? {} : form.availabilityByDay
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

    if (isGuest) {
      saveGuestOnboardingDraft(toGuestDraft(form));
      router.push(authRequiredHref ?? "/auth?step=email&continue=/profile");
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
                <Field label="Пол">
                  <select
                    value={form.gender ?? ""}
                    onChange={(event) => setField("gender", (event.target.value || null) as ProfilePayload["gender"])}
                    className="input"
                  >
                    <option value="">Не указывать</option>
                    <option value="male">Мужской</option>
                    <option value="female">Женский</option>
                  </select>
                </Field>
                <Field label="Возраст">
                  <AgeRibbonPicker value={form.age ?? 18} onChange={(age) => setField("age", age)} />
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
                <Field label="Район" className="col-span-2">
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      type="button"
                      onClick={() => setField("district", null)}
                      className={`rounded-[20px] border px-3 py-3 text-left text-sm font-semibold transition ${
                        !form.district ? "border-ink bg-ink text-white" : "border-white/60 bg-cream text-ink"
                      }`}
                    >
                      Не выбран
                    </button>
                    {DISTRICT_OPTIONS.map((district) => (
                      <button
                        key={district}
                        type="button"
                        onClick={() => setField("district", district)}
                        className={`rounded-[20px] border px-3 py-3 text-left text-sm font-semibold transition ${
                          form.district === district ? "border-ink bg-ink text-white" : "border-white/60 bg-cream text-ink"
                        }`}
                      >
                        {getDistrictLabel(district) ?? district}
                      </button>
                    ))}
                  </div>
                  <div className="mt-2 text-xs leading-5 text-ink/55">Необязательно. Если район не выбран, будем искать шире по Санкт-Петербургу.</div>
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
                  <Field label="Виды спорта">
                    <SportPicker
                      multiple
                      value={form.preferredSports}
                      onChange={(value) => setPreferredSports(value as ProfilePayload["preferredSports"])}
                      levels={form.sportLevels}
                      onLevelChange={(sport, level) => setSportLevel(sport as SportOption, level)}
                      layout="grid"
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

                <Field label="Район и радиус поиска">
                  {form.district ? (
                    <>
                      <SearchAreaMap
                        centerLat={searchCenterLat}
                        centerLng={searchCenterLng}
                        radiusKm={form.searchRadiusKm}
                        city={form.city ?? DEFAULT_CITY}
                        district={form.district}
                        isApproximate={isApproximateSearchArea}
                      />
                      <div className="mt-2 text-xs leading-5 text-ink/55">
                        {`Текущий круг поиска: ${form.searchRadiusKm} км вокруг района ${getDistrictLabel(form.district) ?? DEFAULT_CITY}.`}
                      </div>
                    </>
                  ) : (
                    <div className="rounded-[20px] bg-cream p-4 text-sm leading-6 text-ink/65">
                      Район пока не выбран. Это нормально: подбор будет шире по Санкт-Петербургу. Если хочешь видеть круг поиска на карте, выбери район.
                    </div>
                  )}
                </Field>

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
                    availabilityByDay={form.availabilityByDay}
                    onAvailabilityByDayChange={setAvailabilityByDay}
                  />
                </Field>
                <div className="rounded-[24px] bg-mint/60 p-4">
                  <div className="text-xs font-semibold uppercase tracking-[0.2em] text-court">
                    {hasAvailability ? "Выбрано" : "Пока не указано"}
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2 text-xs">
                    {hasAvailability ? (
                      <>
                        {Object.entries(form.availabilityByDay).map(([day, ranges]) => (
                          <span key={day} className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                            {DAY_LABELS[day as keyof typeof DAY_LABELS]} · {(ranges ?? []).map((range) => TIME_RANGE_LABELS[range as keyof typeof TIME_RANGE_LABELS]).join(", ")}
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
          {isGuest ? (
            <Panel className="bg-cream text-sm leading-6 text-ink/68">
              Профиль уже заполнен как черновик. Можно спокойно поправить данные, а когда захочешь сохранить его в аккаунт и получать отклики, просто подтверди email.
            </Panel>
          ) : null}
          <Panel>
            <div className="mb-5 flex items-center gap-4">
              <Avatar src={form.avatarUrl} alt={form.name || "Игрок"} size="xl" />
              <div className="flex-1">
                <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">Фото</div>
                <div className="mt-1 text-lg font-bold text-ink">
                  {isGuest ? "Черновик карточки игрока" : "Редактирование карточки игрока"}
                </div>
                {!isGuest ? (
                  <label className="mt-3 inline-flex cursor-pointer rounded-2xl bg-mint px-4 py-3 text-sm font-semibold text-ink">
                    {uploading ? "Загрузка..." : "Загрузить фото"}
                    <input type="file" accept="image/*" className="hidden" onChange={handleAvatarUpload} />
                  </label>
                ) : (
                  <div className="mt-3 text-xs leading-5 text-ink/55">
                    Фото можно будет добавить сразу после подтверждения email.
                  </div>
                )}
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
                <AgeRibbonPicker
                  value={form.age ?? 18}
                  onChange={(age) => setField("age", age)}
                />
              </Field>
            </div>

            <div className="mt-3 grid grid-cols-2 gap-3">
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
                </select>
              </Field>
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
              <Field label="Район">
                <select
                  value={form.district ?? ""}
                  onChange={(event) => setField("district", (event.target.value || null) as ProfilePayload["district"])}
                  className="input"
                >
                  <option value="">Не выбран</option>
                  {DISTRICT_OPTIONS.map((district) => (
                    <option key={district} value={district}>
                      {getDistrictLabel(district) ?? district}
                    </option>
                  ))}
                </select>
              </Field>
            </div>

            <div className="mt-3 grid grid-cols-2 gap-3">
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

            <Field label="Виды спорта" className="mt-3">
              <SportPicker
                multiple
                value={form.preferredSports}
                onChange={(value) => setPreferredSports(value as ProfilePayload["preferredSports"])}
                levels={form.sportLevels}
                onLevelChange={(sport, level) => setSportLevel(sport as SportOption, level)}
                layout="grid"
              />
            </Field>

            <Field label="Район и радиус поиска" className="mt-3">
              {form.district ? (
                <>
                  <SearchAreaMap
                    centerLat={searchCenterLat}
                    centerLng={searchCenterLng}
                    radiusKm={form.searchRadiusKm}
                    city={form.city ?? DEFAULT_CITY}
                    district={form.district}
                    isApproximate={isApproximateSearchArea}
                  />
                  <div className="mt-2 text-xs leading-5 text-ink/55">
                    {`Сейчас показываем радиус ${form.searchRadiusKm} км вокруг района ${getDistrictLabel(form.district) ?? DEFAULT_CITY}.`}
                  </div>
                </>
              ) : (
                <div className="rounded-[20px] bg-cream p-4 text-sm leading-6 text-ink/65">
                  Район не выбран. Это нормально: поиск будет шире по Санкт-Петербургу. Выбери район, если хочешь точнее настроить локацию и увидеть круг на карте.
                </div>
              )}
            </Field>

            <Field label="Доступность" className="mt-3">
              <AvailabilityPicker
                availabilityByDay={form.availabilityByDay}
                onAvailabilityByDayChange={setAvailabilityByDay}
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
                    level={form.sportLevels[sport] ?? null}
                    badgeClassName="bg-white text-ink"
                    levelClassName="bg-white text-ink"
                  />
                ))}
                {hasAvailability ? (
                  <>
                    {Object.entries(form.availabilityByDay).map(([day, ranges]) => (
                      <span key={day} className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                        {DAY_LABELS[day as keyof typeof DAY_LABELS]} · {(ranges ?? []).map((range) => TIME_RANGE_LABELS[range as keyof typeof TIME_RANGE_LABELS]).join(", ")}
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
            {loading ? "Сохраняем..." : isGuest ? "Подтвердить email и сохранить" : "Сохранить профиль"}
          </Button>
        </>
      )}

      {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
    </form>
  );
}

function toGuestDraft(form: ProfilePayload): GuestOnboardingDraft {
  return {
    name: form.name ?? "",
    age: form.age ?? 28,
    gender: form.gender ?? null,
    city: form.city ?? DEFAULT_CITY,
    district: form.district,
    preferredSports: form.preferredSports,
    sportLevels: form.sportLevels,
    preferredPlayFormat: form.preferredPlayFormat,
    preferredSurface: form.preferredSurface,
    searchRadiusKm: form.searchRadiusKm,
    isLookingForGame: form.isLookingForGame,
    availableDays: form.availableDays,
    availableTimeRanges: form.availableTimeRanges,
    availabilityByDay: form.availabilityByDay
  };
}

function normalizeAvailabilityByDay(availabilityByDay: unknown, availableDays: unknown, availableTimeRanges: unknown) {
  if (availabilityByDay && typeof availabilityByDay === "object" && !Array.isArray(availabilityByDay)) {
    return Object.fromEntries(
      Object.entries(availabilityByDay).filter(
        (entry): entry is [string, string[]] => Array.isArray(entry[1]) && entry[1].length > 0
      )
    );
  }

  const days = Array.isArray(availableDays) ? availableDays.filter((value): value is string => typeof value === "string") : [];
  const ranges = Array.isArray(availableTimeRanges)
    ? availableTimeRanges.filter((value): value is string => typeof value === "string")
    : [];

  return Object.fromEntries(days.map((day) => [day, ranges]));
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
