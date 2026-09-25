"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { DAY_OPTIONS, DEFAULT_CITY, TIME_RANGE_OPTIONS } from "@/lib/constants";
import { buildConsentState } from "@/lib/profile-visibility";
import { normalizeSports, normalizeSportLevels } from "@/lib/sport-levels";
import { ConsentSettingsPanel } from "@/components/consents/consent-settings-panel";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { LocaleSelector } from "@/components/i18n/locale-selector";
import { useLocale } from "@/components/i18n/locale-provider";

export function SettingsForm({ user }: { user: User }) {
  const router = useRouter();
  const { t } = useLocale();
  const [loading, setLoading] = useState(false);
  const [values, setValues] = useState({
    notificationMatches: user.notificationMatches,
    notificationMessages: user.notificationMessages,
    notificationGames: user.notificationGames,
    notificationDigest: user.notificationDigest ?? true,
    notificationSound: user.notificationSound ?? true
  });

  async function saveSettings() {
    setLoading(true);
    const preferredSports = normalizeSports(user.preferredSports);
    const sportLevels = normalizeSportLevels(user.sportLevels, preferredSports, user.tennisLevel ?? 5);
    await apiFetch("/me", {
      method: "PATCH",
      body: JSON.stringify({
        name: user.name,
        age: user.age,
        gender: user.gender,
        city: user.city ?? DEFAULT_CITY,
        locationPlaceId: user.locationPlaceId,
        locationSource: user.locationSource === "legacy" ? undefined : user.locationSource,
        district: user.district ?? null,
        preferredDistricts: Array.isArray((user as User & { preferredDistricts?: unknown }).preferredDistricts)
          ? (user as User & { preferredDistricts?: string[] }).preferredDistricts
          : user.district
            ? [user.district]
            : [],
        tennisLevel: user.tennisLevel,
        preferredSports,
        sportLevels,
        preferredPlayFormat: user.preferredPlayFormat,
        preferredSurface: user.preferredSurface,
        bio: user.bio ?? "",
        avatarUrl: user.avatarUrl,
        availableDays: Array.isArray(user.availableDays) && user.availableDays.length > 0 ? user.availableDays : [DAY_OPTIONS[0]],
        availableTimeRanges:
          Array.isArray(user.availableTimeRanges) && user.availableTimeRanges.length > 0
            ? user.availableTimeRanges
            : [TIME_RANGE_OPTIONS[2]],
        availabilityByDay:
          user.availabilityByDay && typeof user.availabilityByDay === "object" && !Array.isArray(user.availabilityByDay)
            ? user.availabilityByDay
            : {
                [DAY_OPTIONS[0]]: [TIME_RANGE_OPTIONS[2]]
              },
        isLookingForGame: user.isLookingForGame,
        ...values
      })
    });
    setLoading(false);
    router.refresh();
  }

  async function logout() {
    await apiFetch("/auth/logout", { method: "POST" });
    router.push("/auth");
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <Panel>
        <LocaleSelector />
      </Panel>
      <Panel className="space-y-3">
        <Switch
          title={t("settings.notifications.matches")}
          checked={values.notificationMatches}
          onChange={(checked) => setValues((current) => ({ ...current, notificationMatches: checked }))}
        />
        <Switch
          title={t("settings.notifications.messages")}
          checked={values.notificationMessages}
          onChange={(checked) => setValues((current) => ({ ...current, notificationMessages: checked }))}
        />
        <Switch
          title={t("settings.notifications.games")}
          checked={values.notificationGames}
          onChange={(checked) => setValues((current) => ({ ...current, notificationGames: checked }))}
        />
        <Switch
          title={t("settings.notifications.digest")}
          checked={values.notificationDigest}
          onChange={(checked) => setValues((current) => ({ ...current, notificationDigest: checked }))}
        />
        <Switch
          title={t("settings.notifications.sound")}
          checked={values.notificationSound}
          onChange={(checked) => setValues((current) => ({ ...current, notificationSound: checked }))}
        />
      </Panel>

      <ConsentSettingsPanel
        profile={{
          name: user.name,
          age: user.age,
          city: user.city,
          district: user.district,
          preferredSports: user.preferredSports,
          showOnMap: user.showOnMap,
          consents: buildConsentState(user)
        }}
      />

      <Button fullWidth onClick={saveSettings} disabled={loading}>
        {loading ? t("settings.saving") : t("settings.save")}
      </Button>
      <Button fullWidth variant="ghost" onClick={logout}>
        {t("settings.logout")}
      </Button>
    </div>
  );
}

function Switch({
  title,
  checked,
  onChange
}: {
  title: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-2xl bg-cream px-4 py-3">
      <div className="text-sm font-semibold text-ink">{title}</div>
      <button
        type="button"
        onClick={() => onChange(!checked)}
        className={`flex h-8 w-14 items-center rounded-full p-1 transition ${checked ? "bg-court" : "bg-line"}`}
      >
        <span
          className={`h-6 w-6 rounded-full bg-white shadow transition ${checked ? "translate-x-6" : "translate-x-0"}`}
        />
      </button>
    </div>
  );
}
