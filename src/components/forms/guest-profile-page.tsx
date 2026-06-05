"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import {
  buildGuestAuthHref,
  guestDraftHasProfileBasics,
  loadGuestOnboardingDraft,
  type GuestOnboardingDraft
} from "@/lib/guest-draft";
import { ProfileForm } from "@/components/forms/profile-form";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";

export function GuestProfilePage() {
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
    return (
      <Panel className="py-8 text-center text-sm text-ink/60">
        Подготавливаем твой профиль…
      </Panel>
    );
  }

  return (
    <div className="space-y-4">
      <SectionTitle
        eyebrow="Профиль"
        title="Черновик профиля уже заполнен."
        subtitle="Можно изменить спорт, районы и доступность. Когда захочешь сохранить всё в аккаунт и получать отклики, подтверди email."
      />
      <ProfileForm user={draft} mode="guest" authRequiredHref={buildGuestAuthHref("/profile")} />
    </div>
  );
}
