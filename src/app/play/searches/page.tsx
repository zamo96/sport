import Link from "next/link";
import { redirect } from "next/navigation";
import { Flame } from "lucide-react";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { GameSearchesList } from "@/components/forms/game-searches-list";
import { Button } from "@/components/ui/button";
import { SectionTitle } from "@/components/ui/section-title";
import { getGameSearchesForUser } from "@/server/app-data";

export default async function GameSearchesPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  const searches = await getGameSearchesForUser(user.id);

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Мои поиски"
        title="Смотри статус и подтверждай отклики."
        subtitle="Каждый поиск показывает статус, список откликнувшихся игроков и того, кого ты выбрал."
      />
      <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Link href="/play/searches/new">
          <Button fullWidth variant="secondary">Создать новый поиск</Button>
        </Link>
        <Link href="/play/searches/new?mode=hot">
          <Button fullWidth variant="danger">
            <span className="inline-flex items-center gap-2">
              <Flame className="h-4 w-4" />
              Срочно найти игрока
            </span>
          </Button>
        </Link>
      </div>
      <GameSearchesList
        searches={searches.map((search) => ({
          id: search.id,
          status: search.status,
          searchType: search.searchType,
          hotWindow: search.hotWindow,
          hotStartsAt: search.hotStartsAt?.toISOString() ?? null,
          durationMinutes: search.durationMinutes,
          hasCourtBooked: search.hasCourtBooked,
          sport: search.sport,
          preferredDays: search.preferredDays,
          preferredTimeRanges: search.preferredTimeRanges,
          format: search.format,
          comment: search.comment,
          isActive: search.isActive,
          preferredCourt: search.preferredCourt
            ? {
                name: search.preferredCourt.name
              }
            : null,
          responses: search.responses.map((response) => ({
            id: response.id,
            status: response.status,
            responderUser: {
              id: response.responderUser.id,
              name: response.responderUser.name,
              avatarUrl: response.responderUser.avatarUrl,
              tennisLevel: response.responderUser.tennisLevel,
              sportLevels: response.responderUser.sportLevels,
              city: response.responderUser.city
            }
          }))
        }))}
      />
    </PageShell>
  );
}
