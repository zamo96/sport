import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { translateWeb } from "@/lib/i18n/web";
import { getWebRequestLocale } from "@/lib/i18n/web/request-locale";
import { ProfileForm } from "@/components/forms/profile-form";
import { PageShell } from "@/components/layout/page-shell";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";

export default async function OnboardingPage() {
  const locale = getWebRequestLocale();
  const t = (key: Parameters<typeof translateWeb>[1]) => translateWeb(locale, key);
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
        eyebrow={t("onboarding.eyebrow")}
        title={t("onboarding.title")}
        subtitle={t("onboarding.subtitle")}
      />
      <Panel className="space-y-3 bg-cream text-sm leading-6 text-ink/70">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">{t("onboarding.required")}</div>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            <li>{t("onboarding.required.basics")}</li>
            <li>{t("onboarding.required.sport")}</li>
          </ul>
        </div>
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/55">{t("onboarding.later")}</div>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            <li>{t("onboarding.later.availability")}</li>
            <li>{t("onboarding.later.details")}</li>
          </ul>
        </div>
      </Panel>
      <ProfileForm user={user} mode="onboarding" />
    </PageShell>
  );
}
