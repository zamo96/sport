"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { DAY_OPTIONS, DEFAULT_CITY, TIME_RANGE_OPTIONS } from "@/lib/constants";
import { normalizeSports, normalizeSportLevels } from "@/lib/sport-levels";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";

export function SettingsForm({ user }: { user: User }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [values, setValues] = useState({
    notificationMatches: user.notificationMatches,
    notificationMessages: user.notificationMessages,
    notificationGames: user.notificationGames
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
        city: DEFAULT_CITY,
        tennisLevel: user.tennisLevel,
        preferredSports,
        sportLevels,
        preferredPlayFormat: user.preferredPlayFormat,
        preferredSurface: user.preferredSurface,
        bio: user.bio ?? "",
        avatarUrl: user.avatarUrl,
        searchRadiusKm: user.searchRadiusKm,
        availableDays: Array.isArray(user.availableDays) && user.availableDays.length > 0 ? user.availableDays : [DAY_OPTIONS[0]],
        availableTimeRanges:
          Array.isArray(user.availableTimeRanges) && user.availableTimeRanges.length > 0
            ? user.availableTimeRanges
            : [TIME_RANGE_OPTIONS[2]],
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
      <Panel className="space-y-3">
        <Switch
          title="Уведомления о мэтчах"
          checked={values.notificationMatches}
          onChange={(checked) => setValues((current) => ({ ...current, notificationMatches: checked }))}
        />
        <Switch
          title="Уведомления о сообщениях"
          checked={values.notificationMessages}
          onChange={(checked) => setValues((current) => ({ ...current, notificationMessages: checked }))}
        />
        <Switch
          title="Уведомления о предложениях"
          checked={values.notificationGames}
          onChange={(checked) => setValues((current) => ({ ...current, notificationGames: checked }))}
        />
      </Panel>

      <Button fullWidth onClick={saveSettings} disabled={loading}>
        {loading ? "Сохраняем..." : "Сохранить настройки"}
      </Button>
      <Button fullWidth variant="ghost" onClick={logout}>
        Выйти
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
