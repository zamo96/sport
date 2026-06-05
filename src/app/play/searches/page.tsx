import Link from "next/link";
import { redirect } from "next/navigation";
import { Flame } from "lucide-react";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { PageShell } from "@/components/layout/page-shell";
import { GameSearchesList } from "@/components/forms/game-searches-list";
import { Button } from "@/components/ui/button";
import { LiveRefresh } from "@/components/ui/live-refresh";
import { SectionTitle } from "@/components/ui/section-title";
import { Panel } from "@/components/ui/panel";
import { DAY_LABELS, SPORT_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { translateGameSearchResponseStatus } from "@/lib/status-map";
import { getGameSearchesForUser, getMyGameSearchResponses } from "@/server/app-data";

export default async function GameSearchesPage() {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/play/searches"));
  }

  const [searches, myResponses] = await Promise.all([
    getGameSearchesForUser(user.id),
    getMyGameSearchResponses(user.id)
  ]);

  return (
    <PageShell>
      <LiveRefresh intervalMs={10000} />
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
          scheduledAt: search.scheduledAt?.toISOString() ?? null,
          scheduledDurationMinutes: search.scheduledDurationMinutes ?? null,
          hasCourtBooked: search.hasCourtBooked,
          sport: search.sport,
          selfLevel: search.selfLevel ?? null,
          selfLevelUnknown: search.selfLevelUnknown,
          desiredLevelMin: search.desiredLevelMin ?? 1,
          desiredLevelMax: search.desiredLevelMax ?? 10,
          playersNeeded: search.playersNeeded,
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
          regularPair: search.regularPair
            ? {
                id: search.regularPair.id,
                matchId: search.regularPair.matchId,
                partnerUser: {
                  id: search.regularPair.partnerUser.id,
                  name: search.regularPair.partnerUser.name,
                  avatarUrl: search.regularPair.partnerUser.avatarUrl
                },
                preferredCourt: search.regularPair.preferredCourt
                  ? {
                      name: search.regularPair.preferredCourt.name
                    }
                  : null
              }
            : null,
          responses: search.responses.map((response) => ({
            id: response.id,
            status: response.status,
            responderUser: {
              id: response.responderUser.id,
              name: response.responderUser.name,
              avatarUrl: response.responderUser.avatarUrl,
              age: response.responderUser.age,
              bio: response.responderUser.bio,
              tennisLevel: response.responderUser.tennisLevel,
              preferredSports: response.responderUser.preferredSports,
              sportLevels: response.responderUser.sportLevels,
              city: response.responderUser.city,
              district: response.responderUser.district,
              preferredDistricts: response.responderUser.preferredDistricts,
              availableDays: response.responderUser.availableDays,
              availableTimeRanges: response.responderUser.availableTimeRanges
            }
          }))
        }))}
      />
      <div className="mt-6 space-y-3">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Мои отклики</div>
        {myResponses.length === 0 ? (
          <Panel className="text-sm text-ink/65">Ты пока не откликался на чужие события.</Panel>
        ) : (
          myResponses.map((response) => {
            const days = Array.isArray(response.gameSearch.preferredDays)
              ? response.gameSearch.preferredDays.filter((item): item is string => typeof item === "string")
              : [];
            const ranges = Array.isArray(response.gameSearch.preferredTimeRanges)
              ? response.gameSearch.preferredTimeRanges.filter((item): item is string => typeof item === "string")
              : [];
            return (
              <Panel key={response.id} className="space-y-2">
                <div className="flex items-center justify-between gap-3">
                  <div className="text-base font-bold text-ink">
                    {response.gameSearch.createdByUser.name ?? "Организатор"} · {SPORT_LABELS[response.gameSearch.sport]}
                  </div>
                  <span className="rounded-full bg-cream px-3 py-1.5 text-xs font-semibold text-ink">
                    {translateGameSearchResponseStatus(response.status, {
                      isSearchMatched: response.gameSearch.status === "matched"
                    })}
                  </span>
                </div>
                <div className="text-sm text-ink/68">
                  {response.gameSearch.preferredCourt?.name ?? "Клуб не указан"} ·{" "}
                  {[days.map((day) => DAY_LABELS[day as keyof typeof DAY_LABELS]).join(", "), ranges.map((range) => TIME_RANGE_LABELS[range as keyof typeof TIME_RANGE_LABELS]).join(", ")]
                    .filter(Boolean)
                    .join(" · ")}
                </div>
                {response.status === "approved" ? (
                  <div className="flex flex-wrap gap-2 pt-1">
                    {response.gameSearch.searchType === "regular" &&
                    response.gameSearch.playersNeeded === 1 &&
                    response.gameSearch.regularPair ? (
                      <>
                        <Link
                          href={`/play/regular/${response.gameSearch.regularPair.id}`}
                          className="rounded-2xl bg-ink px-4 py-3 text-sm font-semibold text-white"
                        >
                          Открыть регулярную пару
                        </Link>
                        <Link
                          href={`/inbox/${response.gameSearch.regularPair.matchId}`}
                          className="rounded-2xl bg-cream px-4 py-3 text-sm font-semibold text-ink"
                        >
                          Открыть чат
                        </Link>
                      </>
                    ) : (
                      <Link
                        href={`/play/searches/${response.gameSearch.id}`}
                        className="rounded-2xl bg-ink px-4 py-3 text-sm font-semibold text-white"
                      >
                        Открыть событие
                      </Link>
                    )}
                  </div>
                ) : null}
              </Panel>
            );
          })
        )}
      </div>
    </PageShell>
  );
}
