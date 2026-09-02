"use client";

import { ChangeEvent, FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { PlayFormat, Surface, type Gender, type Sport, type User } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { saveGuestOnboardingDraft, type GuestOnboardingDraft } from "@/lib/guest-draft";
import {
  AVAILABLE_CITIES,
  DEFAULT_CITY,
  DEFAULT_CITY_COORDINATES,
  type DistrictOption,
  DISTRICT_OPTIONS,
  getDistrictArea,
  getDistrictLabel,
  SPORT_OPTIONS,
} from "@/lib/constants";
import { useLocale } from "@/components/i18n/locale-provider";
import type { WebMessageKey } from "@/lib/i18n/web";
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
  | "isLookingForGame"
  | "notificationGames"
  | "notificationMatches"
  | "notificationMessages"
> & {
  district: DistrictOption | null;
  preferredDistricts: DistrictOption[];
  preferredSports: SportOption[];
  sportLevels: Partial<Record<SportOption, SportLevelValue>>;
  availableDays: string[];
  availableTimeRanges: string[];
  availabilityByDay: Partial<Record<string, string[]>>;
};

type SportOption = (typeof SPORT_OPTIONS)[number];

const DAY_MESSAGE_KEYS: Record<string, WebMessageKey> = {
  monday: "availability.day.monday",
  tuesday: "availability.day.tuesday",
  wednesday: "availability.day.wednesday",
  thursday: "availability.day.thursday",
  friday: "availability.day.friday",
  saturday: "availability.day.saturday",
  sunday: "availability.day.sunday"
};

const TIME_RANGE_MESSAGE_KEYS: Record<string, WebMessageKey> = {
  morning: "availability.time.morning",
  day: "availability.time.day",
  evening: "availability.time.evening"
};

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
    preferredDistricts?: unknown;
  };
  mode?: "onboarding" | "profile" | "guest";
  authRequiredHref?: string;
}) {
  const router = useRouter();
  const { t } = useLocale();
  const isOnboarding = mode === "onboarding";
  const isGuest = mode === "guest";
  const initialPreferredSports = normalizeSports(user.preferredSports) as SportOption[];
  const initialSportLevels = normalizeSportLevels(user.sportLevels, initialPreferredSports, user.tennisLevel ?? 5) as Partial<
    Record<SportOption, SportLevelValue>
  >;
  const initialPreferredDistricts = normalizeDistricts(user.preferredDistricts, user.district);
  const initialAvailabilityByDay = normalizeAvailabilityByDay(user.availabilityByDay, user.availableDays, user.availableTimeRanges);
  const [form, setForm] = useState<ProfilePayload>({
    name: user.name ?? "",
    age: user.age ?? 28,
    gender: (user.gender as Gender | null | undefined) ?? null,
    city: DEFAULT_CITY,
    district: initialPreferredDistricts[0] ?? (user.district as ProfilePayload["district"]) ?? null,
    preferredDistricts: initialPreferredDistricts,
    tennisLevel: getPrimarySportLevel(initialPreferredSports, initialSportLevels, user.tennisLevel ?? 5),
    preferredSports: initialPreferredSports,
    sportLevels: initialSportLevels,
    preferredPlayFormat: user.preferredPlayFormat ?? PlayFormat.both,
    preferredSurface: user.preferredSurface ?? Surface.any,
    bio: user.bio ?? "",
    avatarUrl: user.avatarUrl ?? null,
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
  const primaryDistrict = form.preferredDistricts[0] ?? form.district ?? null;
  const selectedDistrictCenter = getDistrictArea(primaryDistrict)?.center ?? DEFAULT_CITY_COORDINATES;
  const searchCenterLat = selectedDistrictCenter.lat;
  const searchCenterLng = selectedDistrictCenter.lng;
  const isApproximateSearchArea = form.preferredDistricts.length === 0;

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

  function toggleDistrict(district: DistrictOption) {
    setForm((current) => {
      const nextDistricts = current.preferredDistricts.includes(district)
        ? current.preferredDistricts.filter((item) => item !== district)
        : [...current.preferredDistricts, district];

      return {
        ...current,
        preferredDistricts: nextDistricts,
        district: nextDistricts[0] ?? null
      };
    });
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
  const canContinueBasics =
    (form.name ?? "").trim().length >= 2 &&
    (form.city ?? "").trim().length >= 2 &&
    (form.age ?? 0) >= 18 &&
    (form.age ?? 0) <= 100;
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
        throw new Error(data.error ?? t("profile.error.avatarUpload"));
      }
      setField("avatarUrl", data.avatarUrl);
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : t("profile.error.avatarUpload"));
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
      setError(requestError instanceof Error ? requestError.message : t("profile.error.save"));
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
      setError(requestError instanceof Error ? requestError.message : t("profile.error.save"));
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
                <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">
                  {t("profile.step.progress", { step })}
                </div>
                <div className="mt-1 text-lg font-bold text-ink">
                  {step === 1
                    ? t("profile.step.basics.title")
                    : step === 2
                      ? t("profile.step.preferences.title")
                      : t("profile.step.availability.title")}
                </div>
                <div className="mt-1 text-sm text-ink/65">
                  {step === 1
                    ? t("profile.step.basics.subtitle")
                    : step === 2
                      ? t("profile.step.preferences.subtitle")
                      : t("profile.step.availability.subtitle")}
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
                <Field label={t("profile.field.name")}>
                  <input
                    required
                    value={form.name ?? ""}
                    onChange={(event) => setField("name", event.target.value)}
                    className="input"
                    placeholder={t("profile.namePlaceholder")}
                  />
                </Field>
                <Field label={t("profile.field.gender")}>
                  <select
                    value={form.gender ?? ""}
                    onChange={(event) => setField("gender", (event.target.value || null) as ProfilePayload["gender"])}
                    className="input"
                  >
                    <option value="">{t("profile.gender.unspecified")}</option>
                    <option value="male">{t("profile.gender.male")}</option>
                    <option value="female">{t("profile.gender.female")}</option>
                  </select>
                </Field>
                <Field label={t("profile.field.age")}>
                  <AgeRibbonPicker value={form.age ?? 18} onChange={(age) => setField("age", age)} />
                </Field>
                <Field label={t("profile.field.city")} className="col-span-2">
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
                  <div className="mt-2 text-xs leading-5 text-ink/55">{t("profile.city.onboardingHint")}</div>
                </Field>
              </div>
            ) : null}

            {step === 2 ? (
              <div className="space-y-4">
                <div className="grid grid-cols-1 gap-3">
                  <Field label={t("profile.field.sports")}>
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

                <Field label={t("profile.field.districts")}>
                  <div className="flex flex-wrap gap-2">
                    {DISTRICT_OPTIONS.map((district) => {
                      const active = form.preferredDistricts.includes(district);
                      return (
                        <button
                          key={district}
                          type="button"
                          onClick={() => toggleDistrict(district)}
                          className={`rounded-[18px] border px-3 py-2 text-left text-sm font-semibold transition ${
                            active ? "border-ink bg-ink text-white" : "border-white/60 bg-cream text-ink"
                          }`}
                        >
                          {getDistrictLabel(district) ?? district}
                        </button>
                      );
                    })}
                  </div>
                  <div className="mt-2 text-xs leading-5 text-ink/55">{t("profile.districts.onboardingHint")}</div>
                </Field>

                <div className="rounded-[24px] bg-cream p-4">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <div className="text-sm font-semibold text-ink">{t("profile.lookingNow.title")}</div>
                      <div className="mt-1 text-xs leading-5 text-ink/60">{t("profile.lookingNow.onboardingHint")}</div>
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
                  {t("profile.availability.intro")}
                </div>
                <Field label={t("profile.field.availability")}>
                  <AvailabilityPicker
                    availabilityByDay={form.availabilityByDay}
                    onAvailabilityByDayChange={setAvailabilityByDay}
                  />
                </Field>
                <div className="rounded-[24px] bg-mint/60 p-4">
                  <div className="text-xs font-semibold uppercase tracking-[0.2em] text-court">
                    {hasAvailability ? t("profile.availability.selected") : t("profile.availability.empty")}
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2 text-xs">
                    {hasAvailability ? (
                      <>
                        {Object.entries(form.availabilityByDay).map(([day, ranges]) => (
                          <span key={day} className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                            {translateAvailabilityValue(day, DAY_MESSAGE_KEYS, t)} · {(ranges ?? []).map((range) => translateAvailabilityValue(range, TIME_RANGE_MESSAGE_KEYS, t)).join(", ")}
                          </span>
                        ))}
                      </>
                    ) : (
                      <span className="rounded-full bg-white px-3 py-2 font-semibold text-ink">
                        {t("profile.availability.later")}
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
                {t("profile.action.back")}
              </Button>
            ) : null}

            {step < 3 ? (
              <Button
                type="button"
                fullWidth
                onClick={nextStep}
                disabled={(step === 1 && !canContinueBasics) || (step === 2 && !hasSports)}
              >
                {t("profile.action.next")}
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
                  {t("profile.action.skip")}
                </Button>
                <Button type="submit" fullWidth disabled={loading}>
                  {loading ? t("profile.action.saving") : t("profile.action.start")}
                </Button>
              </>
            )}
          </div>
        </>
      ) : (
        <>
          {isGuest ? (
            <Panel className="bg-cream text-sm leading-6 text-ink/68">
              {t("profile.guest.banner")}
            </Panel>
          ) : null}
          <Panel>
            <div className="mb-5 flex items-center gap-4">
              <Avatar src={form.avatarUrl} alt={form.name || t("profile.playerFallback")} size="xl" />
              <div className="flex-1">
                <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">{t("profile.photo.label")}</div>
                <div className="mt-1 text-lg font-bold text-ink">
                  {isGuest ? t("profile.photo.guestTitle") : t("profile.photo.editTitle")}
                </div>
                {!isGuest ? (
                  <label className="mt-3 inline-flex cursor-pointer rounded-2xl bg-mint px-4 py-3 text-sm font-semibold text-ink">
                    {uploading ? t("profile.photo.uploading") : t("profile.photo.upload")}
                    <input type="file" accept="image/*" className="hidden" onChange={handleAvatarUpload} />
                  </label>
                ) : (
                  <div className="mt-3 text-xs leading-5 text-ink/55">{t("profile.photo.guestHint")}</div>
                )}
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <Field label={t("profile.field.name")}>
                <input
                  required
                  value={form.name ?? ""}
                  onChange={(event) => setField("name", event.target.value)}
                  className="input"
                  placeholder={t("profile.namePlaceholder")}
                />
              </Field>
              <Field label={t("profile.field.age")}>
                <AgeRibbonPicker
                  value={form.age ?? 18}
                  onChange={(age) => setField("age", age)}
                />
              </Field>
            </div>

            <div className="mt-3 grid grid-cols-2 gap-3">
              <Field label={t("profile.field.gender")}>
                <select
                  value={form.gender ?? ""}
                  onChange={(event) =>
                    setField("gender", (event.target.value || null) as ProfilePayload["gender"])
                  }
                  className="input"
                >
                  <option value="">{t("profile.gender.unspecified")}</option>
                  <option value="male">{t("profile.gender.male")}</option>
                  <option value="female">{t("profile.gender.female")}</option>
                </select>
              </Field>
              <Field label={t("profile.field.city")}>
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
              <div className="mt-2 text-xs leading-5 text-ink/55">{t("profile.city.hint")}</div>
              </Field>
            </div>

            <Field label={t("profile.field.sports")} className="mt-3">
              <SportPicker
                multiple
                value={form.preferredSports}
                onChange={(value) => setPreferredSports(value as ProfilePayload["preferredSports"])}
                levels={form.sportLevels}
                onLevelChange={(sport, level) => setSportLevel(sport as SportOption, level)}
                layout="grid"
              />
            </Field>

            <Field label={t("profile.field.districts")} className="mt-3">
              <div className="flex flex-wrap gap-2">
                {DISTRICT_OPTIONS.map((district) => {
                  const active = form.preferredDistricts.includes(district);
                  return (
                    <button
                      key={district}
                      type="button"
                      onClick={() => toggleDistrict(district)}
                      className={`rounded-[18px] border px-3 py-2 text-left text-sm font-semibold transition ${
                        active ? "border-ink bg-ink text-white" : "border-white/60 bg-cream text-ink"
                      }`}
                    >
                      {getDistrictLabel(district) ?? district}
                    </button>
                  );
                })}
              </div>
              <div className="mt-2 text-xs leading-5 text-ink/55">{t("profile.districts.hint")}</div>
            </Field>

            <Field label={t("profile.field.districtMap")} className="mt-3">
              {form.preferredDistricts.length > 0 ? (
                <>
                  <SearchAreaMap
                    centerLat={searchCenterLat}
                    centerLng={searchCenterLng}
                    city={form.city ?? DEFAULT_CITY}
                    districts={form.preferredDistricts}
                    isApproximate={isApproximateSearchArea}
                  />
                  <div className="mt-2 text-xs leading-5 text-ink/55">{t("profile.map.selectedHint")}</div>
                </>
              ) : (
                <div className="rounded-[20px] bg-cream p-4 text-sm leading-6 text-ink/65">
                  {t("profile.map.emptyHint")}
                </div>
              )}
            </Field>

            <Field label={t("profile.field.availability")} className="mt-3">
              <AvailabilityPicker
                availabilityByDay={form.availabilityByDay}
                onAvailabilityByDayChange={setAvailabilityByDay}
              />
            </Field>

            <div className="mt-3 rounded-[24px] bg-cream p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold text-ink">{t("profile.lookingNow.title")}</div>
                  <div className="mt-1 text-xs leading-5 text-ink/60">{t("profile.lookingNow.hint")}</div>
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
                        {translateAvailabilityValue(day, DAY_MESSAGE_KEYS, t)} · {(ranges ?? []).map((range) => translateAvailabilityValue(range, TIME_RANGE_MESSAGE_KEYS, t)).join(", ")}
                      </span>
                    ))}
                  </>
                ) : (
                  <span className="rounded-full bg-white px-3 py-2 font-semibold text-ink">{t("profile.value.unspecified")}</span>
                )}
              </div>
            </div>

            <Field label={t("profile.field.bio")} className="mt-3">
              <textarea
                rows={4}
                value={form.bio ?? ""}
                onChange={(event) => setField("bio", event.target.value)}
                className="input min-h-[112px] resize-none py-3"
                placeholder={t("profile.bioPlaceholder")}
              />
            </Field>
          </Panel>

          <Button type="submit" fullWidth disabled={loading || uploading}>
            {loading
              ? t("profile.action.saving")
              : isGuest
                ? t("profile.action.confirmEmail")
                : t("profile.action.save")}
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
    district: form.preferredDistricts[0] ?? form.district,
    preferredDistricts: form.preferredDistricts,
    preferredSports: form.preferredSports,
    sportLevels: form.sportLevels,
    preferredPlayFormat: form.preferredPlayFormat,
    preferredSurface: form.preferredSurface,
    isLookingForGame: form.isLookingForGame,
    availableDays: form.availableDays,
    availableTimeRanges: form.availableTimeRanges,
    availabilityByDay: form.availabilityByDay
  };
}

function normalizeDistricts(value: unknown, fallbackDistrict?: string | null) {
  const districts = Array.isArray(value)
    ? value.filter((district): district is DistrictOption => typeof district === "string" && DISTRICT_OPTIONS.includes(district as DistrictOption))
    : [];

  if (districts.length > 0) {
    return districts;
  }

  if (fallbackDistrict && DISTRICT_OPTIONS.includes(fallbackDistrict as DistrictOption)) {
    return [fallbackDistrict as DistrictOption];
  }

  return [];
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

function translateAvailabilityValue(
  value: string,
  keys: Record<string, WebMessageKey>,
  t: (key: WebMessageKey) => string
) {
  const key = keys[value];
  return key ? t(key) : value;
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
