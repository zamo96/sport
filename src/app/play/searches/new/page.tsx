import { redirect } from "next/navigation";
import { type GameSearchType, type Sport } from "@prisma/client";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { GameSearchForm } from "@/components/forms/game-search-form";
import { SectionTitle } from "@/components/ui/section-title";
import { getCourtsForUser } from "@/server/app-data";

export default async function NewGameSearchPage({
  searchParams
}: {
  searchParams?: { mode?: string };
}) {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  const courts = await getCourtsForUser(user.id);
  const availableSports = Array.isArray(user.preferredSports)
    ? user.preferredSports.filter((sport): sport is string => typeof sport === "string")
    : ["tennis"];
  const initialMode = searchParams?.mode === "hot" ? "hot" : "regular";

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Поиск игры"
        title={initialMode === "hot" ? "Найди игрока срочно." : "Создай свой поиск игры."}
        subtitle={
          initialMode === "hot"
            ? "Сценарий для сегодня или завтра: если игрок сорвался, но корт уже есть и нужно быстро найти замену."
            : "Выбери вид спорта, дни и интервал времени, когда тебе удобно играть. Другие игроки увидят это в активном списке."
        }
      />
      <GameSearchForm
        initialMode={initialMode as GameSearchType}
        availableSports={availableSports as Sport[]}
        courts={courts.map((court) => ({
          id: court.id,
          name: court.name,
          address: court.address
        }))}
      />
    </PageShell>
  );
}
