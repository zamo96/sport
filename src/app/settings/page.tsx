import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { SettingsForm } from "@/components/forms/settings-form";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";

export default async function SettingsPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/settings"));
  }

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Настройки"
        title="Уведомления и управление сессией."
        subtitle="Позже сюда можно будет добавить установку PWA и push-уведомления без изменения базовой модели."
      />
      <SettingsForm user={user} />
    </PageShell>
  );
}
