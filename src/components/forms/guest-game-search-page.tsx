"use client";

import { useEffect, useState } from "react";
import { type GameSearchType, type Sport } from "@prisma/client";
import { useRouter } from "next/navigation";

import {
  buildGuestAuthHref,
  guestDraftHasProfileBasics,
  loadGuestOnboardingDraft,
  type GuestOnboardingDraft
} from "@/lib/guest-draft";
import { GameSearchForm } from "@/components/forms/game-search-form";
import { Panel } from "@/components/ui/panel";

type CourtOption = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  locationLat: number;
  locationLng: number;
  supportedSports?: Sport[];
};

export function GuestGameSearchPage({
  initialMode,
  courts,
  availableSports
}: {
  initialMode: GameSearchType;
  courts: CourtOption[];
  availableSports: Sport[];
}) {
  const router = useRouter();
  const [draft, setDraft] = useState<GuestOnboardingDraft | null>(null);

  useEffect(() => {
    const savedDraft = loadGuestOnboardingDraft();

    if (!savedDraft || !guestDraftHasProfileBasics(savedDraft)) {
      router.replace("/auth");
      return;
    }

    setDraft(savedDraft);
  }, [router]);

  if (!draft) {
    return <Panel className="py-8 text-center text-sm text-ink/60">Подготавливаем твой профиль…</Panel>;
  }

  return (
    <div className="space-y-4">
      <Panel className="bg-cream text-sm leading-6 text-ink/68">
        Поиск можно заполнить уже сейчас. Когда решишь опубликовать его для других игроков, попросим только email и код, а введённые данные сохраним.
      </Panel>
      <GameSearchForm
        initialMode={initialMode}
        availableSports={availableSports}
        profileSports={draft.preferredSports}
        sportLevels={draft.sportLevels}
        courts={courts}
        authRequiredHref={buildGuestAuthHref(`/play/searches/new${initialMode === "hot" ? "?mode=hot" : ""}`)}
      />
    </div>
  );
}
