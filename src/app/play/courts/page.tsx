import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";
import { CourtsBrowser } from "@/components/courts/courts-browser";
import { DEFAULT_CITY } from "@/lib/constants";
import { translateCourts } from "@/lib/i18n/web/courts";
import { getWebRequestLocale } from "@/lib/i18n/web/request-locale";
import { normalizeSports } from "@/lib/sport-levels";
import { courtsQuerySchema } from "@/lib/validators";
import { getCourtsForUser } from "@/server/app-data";
import { serializeCourt } from "@/server/serializers";

export default async function CourtsPage({
  searchParams
}: {
  searchParams: Record<string, string | string[] | undefined>;
}) {
  const locale = getWebRequestLocale();
  const t = (key: Parameters<typeof translateCourts>[1]) => translateCourts(locale, key);
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/play/courts"));
  }

  const query = courtsQuerySchema.parse(
    Object.fromEntries(
      Object.entries(searchParams).map(([key, value]) => [key, Array.isArray(value) ? value[0] : value ?? ""])
    )
  );
  const courts = await getCourtsForUser(user.id, {
    city: DEFAULT_CITY
  });

  return (
    <PageShell>
      <SectionTitle
        eyebrow={t("courts.page.eyebrow")}
        title={t("courts.page.title")}
        subtitle={t("courts.page.subtitle")}
      />
      <CourtsBrowser
        courts={courts.map(serializeCourt)}
        userDistrict={user.district}
        searchRadiusKm={user.searchRadiusKm}
        profileSports={normalizeSports(user.preferredSports)}
        initialQuery={query.q ?? ""}
        initialSport={query.sport ?? null}
      />
    </PageShell>
  );
}
