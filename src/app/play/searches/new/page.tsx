import { redirect } from "next/navigation";
import { type GameSearchType, type Sport } from "@prisma/client";

import { getSessionUser } from "@/lib/auth";
import { SPORT_OPTIONS } from "@/lib/constants";
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
  const initialMode = searchParams?.mode === "hot" ? "hot" : "regular";

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Поиск игры"
        title={initialMode === "hot" ? "Найди игрока срочно." : "Создай свой поиск игры."}
        subtitle={
          initialMode === "hot"
            ? "Сценарий для сегодня или завтра: если игрок сорвался, но место или бронь уже есть и нужно быстро найти замену."
            : "Выбери вид спорта, дни и интервал времени, когда тебе удобно играть. Другие игроки увидят это в активном списке."
        }
      />
      <GameSearchForm
        initialMode={initialMode as GameSearchType}
        availableSports={[...SPORT_OPTIONS] as Sport[]}
        profileSports={
          Array.isArray(user.preferredSports)
            ? user.preferredSports.filter((sport): sport is Sport => typeof sport === "string")
            : []
        }
        sportLevels={user.sportLevels}
        courts={courts.map((court) => ({
          id: court.id,
          name: court.name,
          address: court.address,
          supportedSports: Array.isArray(court.supportedSports)
            ? court.supportedSports.filter((sport): sport is Sport => typeof sport === "string")
            : []
        }))}
      />
    </PageShell>
  );
}
