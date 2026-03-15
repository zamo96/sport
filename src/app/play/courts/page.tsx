import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";
import { CourtsBrowser } from "@/components/courts/courts-browser";
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
    redirect("/auth");
  }

  const query = courtsQuerySchema.parse(
    Object.fromEntries(
      Object.entries(searchParams).map(([key, value]) => [key, Array.isArray(value) ? value[0] : value ?? ""])
    )
  );
  const courts = await getCourtsForUser(user.id, query);

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Корты"
        title="Выбери место до начала переписки."
        subtitle="Список и карта работают через geo-абстракцию. Для MVP подключены Яндекс Карты через отдельный провайдер."
      />
      <CourtsBrowser courts={courts.map(serializeCourt)} />
    </PageShell>
  );
}
