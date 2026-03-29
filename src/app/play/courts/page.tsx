import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";
import { CourtsBrowser } from "@/components/courts/courts-browser";
import { DEFAULT_CITY } from "@/lib/constants";
import { normalizeSports } from "@/lib/sport-levels";
import { courtsQuerySchema } from "@/lib/validators";
import { getCourtsForUser } from "@/server/app-data";
import { serializeCourt } from "@/server/serializers";

export default async function CourtsPage({
  searchParams
}: {
  searchParams: Record<string, string | string[] | undefined>;
}) {
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
        eyebrow="Спортивные центры"
        title="Выбери место до начала переписки."
        subtitle="Показываем свою базу спортивных центров Санкт-Петербурга. Поиск подсказывает клубы и районы сразу при вводе."
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
