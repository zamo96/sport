import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { SettingsForm } from "@/components/forms/settings-form";
import { LocalizedSettingsTitle } from "@/components/i18n/localized-settings-title";
import { LocaleRecommendation } from "@/components/i18n/locale-recommendation";
import { PageShell } from "@/components/layout/page-shell";
import { getLocationPlace } from "@/server/locations";

export default async function SettingsPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/settings"));
  }

  const confirmedLocation = user.locationPlaceId ? await getLocationPlace(user.locationPlaceId) : null;

  return (
    <PageShell>
      <LocalizedSettingsTitle />
      {user.localeOverride ? null : (
        <LocaleRecommendation confirmedCountryCode={confirmedLocation?.countryCode} />
      )}
      <SettingsForm user={user} />
    </PageShell>
  );
}
