import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { ProfileForm } from "@/components/forms/profile-form";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";

export default async function ProfilePage() {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Профиль"
        title="Настрой свою карточку, уровень и время."
        subtitle="Эти данные влияют на ранжирование в поиске, качество мэтчей и релевантность кортов."
      />
      <ProfileForm user={user} />
    </PageShell>
  );
}
