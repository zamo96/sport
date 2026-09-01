import { getSessionUser } from "@/lib/auth";
import { translateWeb } from "@/lib/i18n/web";
import { getWebRequestLocale } from "@/lib/i18n/web/request-locale";
import { GuestProfilePage } from "@/components/forms/guest-profile-page";
import { ProfileForm } from "@/components/forms/profile-form";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";

export default async function ProfilePage() {
  const locale = getWebRequestLocale();
  const t = (key: Parameters<typeof translateWeb>[1]) => translateWeb(locale, key);
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
        eyebrow={t("profile.page.eyebrow")}
        title={t("profile.page.title")}
        subtitle={t("profile.page.subtitle")}
      />
      <ProfileForm user={user} />
    </PageShell>
  );
}
