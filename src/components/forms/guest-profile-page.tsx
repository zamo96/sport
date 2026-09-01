"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { useLocale } from "@/components/i18n/locale-provider";
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
  const { t } = useLocale();
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
        {t("profile.guest.loading")}
      </Panel>
    );
  }

  return (
    <div className="space-y-4">
      <SectionTitle
        eyebrow={t("profile.guest.eyebrow")}
        title={t("profile.guest.title")}
        subtitle={t("profile.guest.subtitle")}
      />
      <ProfileForm user={draft} mode="guest" authRequiredHref={buildGuestAuthHref("/profile")} />
    </div>
  );
}
