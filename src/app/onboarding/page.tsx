import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { ProfileForm } from "@/components/forms/profile-form";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";

export default async function OnboardingPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  if (user.onboardingCompleted) {
    redirect("/discover");
  }

  return (
    <PageShell withNav={false}>
      <SectionTitle
        eyebrow="Онбординг"
        title="Заполни профиль за 30 секунд."
        subtitle="Короткий пошаговый сценарий: кто ты, как играешь и, при желании, когда тебе удобно."
      />
      <ProfileForm user={user} mode="onboarding" />
    </PageShell>
  );
}
