import { getSessionUser } from "@/lib/auth";
import { GuestProfilePage } from "@/components/forms/guest-profile-page";
import { ProfileForm } from "@/components/forms/profile-form";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";

export default async function ProfilePage() {
  const user = await getSessionUser();

  if (!user) {
    return (
      <PageShell>
        <GuestProfilePage />
      </PageShell>
    );
  }

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Профиль"
        title="Настрой свою карточку, уровень и время."
        subtitle="Эти данные влияют на ранжирование в поиске, качество мэтчей и релевантность спортивных центров."
      />
      <ProfileForm user={user} />
    </PageShell>
  );
}
