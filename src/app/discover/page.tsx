import { redirect } from "next/navigation";
import { Flame } from "lucide-react";

import { getSessionUser } from "@/lib/auth";
import { discoverFiltersSchema } from "@/lib/validators";
import { PageShell } from "@/components/layout/page-shell";
import { FiltersBar } from "@/components/discover/filters-bar";
import { DiscoverTabs } from "@/components/discover/discover-tabs";
import { IncomingLikesList } from "@/components/discover/incoming-likes-list";
import { SeekingPlayersList } from "@/components/discover/seeking-players-list";
import { UpcomingGames } from "@/components/discover/upcoming-games";
import { SwipeDeck } from "@/components/discover/swipe-deck";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";
import { PLAY_FORMAT_LABELS } from "@/lib/constants";
import { getSportLevelEntries, normalizeSports } from "@/lib/sport-levels";
import { SportBadge } from "@/components/ui/sport-badge";
import {
  getActiveSearchesCount,
  getDiscoverPageData,
  getHotNotificationsCount,
  getHotPlayers,
  getIncomingLikePlayers,
  getIncomingLikesCount,
  getNotificationsForUser,
  getSeekingPlayers,
  getUpcomingGamesForUser
} from "@/server/app-data";
import { serializeUserPreview } from "@/server/serializers";

export default async function DiscoverPage({
  searchParams
}: {
  searchParams: Record<string, string | string[] | undefined>;
}) {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  if (!user.onboardingCompleted) {
    redirect("/onboarding");
  }

  const parsedFilters = discoverFiltersSchema.parse(
    Object.fromEntries(
      Object.entries(searchParams).map(([key, value]) => [key, Array.isArray(value) ? value[0] : value ?? ""])
    )
  );
  const profileSports = normalizeSports(user.preferredSports);
  const effectiveFilters = {
    ...parsedFilters,
    sport: parsedFilters.sport.length > 0 ? parsedFilters.sport : profileSports
  };
  const swipeDeckKey = JSON.stringify({
    view: effectiveFilters.view ?? "swipe",
    city: effectiveFilters.city ?? null,
    gender: effectiveFilters.gender ?? [],
    sport: effectiveFilters.sport ?? [],
    format: effectiveFilters.format ?? [],
    surface: effectiveFilters.surface ?? [],
    day: effectiveFilters.day ?? [],
    timeRange: effectiveFilters.timeRange ?? [],
    distanceKm: effectiveFilters.distanceKm ?? null,
    levelMin: effectiveFilters.levelMin ?? null,
    levelMax: effectiveFilters.levelMax ?? null
  });
  const isLikesView = effectiveFilters.view === "likes";
  const isSeekingView = effectiveFilters.view === "seeking";
  const isHotView = effectiveFilters.view === "hot";
  const userSportLevels = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
  const [{ candidates }, incomingLikePlayers, seekingPlayers, hotPlayers, upcomingGames, activeSearchesCount, incomingLikesCount, hotCount, notifications] = await Promise.all([
    getDiscoverPageData(user.id, effectiveFilters),
    getIncomingLikePlayers(user.id, effectiveFilters),
    getSeekingPlayers(user.id, effectiveFilters),
    getHotPlayers(user.id, effectiveFilters),
    getUpcomingGamesForUser(user.id),
    getActiveSearchesCount(user.id),
    getIncomingLikesCount(user.id),
    getHotNotificationsCount(user.id),
    getNotificationsForUser(user.id)
  ]);

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Поиск"
        title="Найди партнера за одну минуту."
        subtitle="Свайпай карточки, смотри активных игроков или открывай срочные запросы на сегодня и завтра."
      />
      <div className="space-y-4">
        <Panel className="flex items-center justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Твой профиль поиска</div>
            <div className="mt-1 text-lg font-bold text-ink">
              {PLAY_FORMAT_LABELS[user.preferredPlayFormat]}
            </div>
            <div className="mt-2 flex flex-wrap gap-2">
              {userSportLevels.slice(0, 3).map(({ sport, level }) => (
                <span key={sport} className="inline-flex items-center gap-2">
                  <SportBadge sport={sport} className="bg-cream text-ink" />
                  <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">Уровень {level}</span>
                </span>
              ))}
            </div>
            <div className="mt-1 text-sm text-ink/60">
              {user.isLookingForGame ? "Ты виден в списке активных игроков" : "Ты скрыт из списка активных игроков"}
            </div>
          </div>
          <div className="rounded-[22px] bg-mint px-3 py-2 text-right">
            <div className="text-[11px] uppercase tracking-[0.18em] text-court">Радиус</div>
            <div className="mt-1 font-bold text-ink">{user.searchRadiusKm} км</div>
          </div>
        </Panel>
        <div className="grid grid-cols-3 gap-2">
          <a href="/play/searches" className="block">
            <Button fullWidth variant="ghost">
              <span className="relative inline-flex items-center gap-2">
                Мои поиски
                {activeSearchesCount > 0 ? (
                  <span className="absolute -right-4 -top-3 flex min-h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white">
                    {activeSearchesCount}
                  </span>
                ) : null}
              </span>
            </Button>
          </a>
          <a href="/play/searches/new?mode=hot" className="block">
            <Button fullWidth variant="danger">
              <span className="inline-flex items-center gap-2">
                <Flame className="h-4 w-4 text-orange-200" />
                Срочно найти
              </span>
            </Button>
          </a>
          <a href="/play/searches/new" className="block">
            <Button fullWidth variant="secondary">Создать поиск</Button>
          </a>
        </div>
        <a href="/notifications" className="block">
          <Panel className="flex items-center justify-between gap-3">
            <div>
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Уведомления</div>
              <div className="mt-1 text-sm text-ink/70">
                {notifications[0]?.title ?? "Здесь будут входящие лайки, срочные события и решения по заявкам."}
              </div>
            </div>
            <span className="rounded-full bg-red-500 px-3 py-2 text-xs font-semibold text-white">
              {notifications.length}
            </span>
          </Panel>
        </a>
        <DiscoverTabs incomingLikesCount={incomingLikesCount} hotCount={hotCount} />
        {isLikesView ? (
          <>
            <IncomingLikesList
              users={incomingLikePlayers.map((candidate) => ({
                id: candidate.id,
                name: candidate.name,
                age: candidate.age,
                city: candidate.city,
                bio: candidate.bio,
                avatarUrl: candidate.avatarUrl,
                tennisLevel: candidate.tennisLevel,
                preferredSports: candidate.preferredSports,
                sportLevels: candidate.sportLevels,
                preferredPlayFormat: candidate.preferredPlayFormat,
                preferredSurface: candidate.preferredSurface,
                availableDays: candidate.availableDays,
                availableTimeRanges: candidate.availableTimeRanges,
                distanceLabel: serializeUserPreview(candidate).distanceLabel,
                score: candidate.score
              }))}
            />
            <FiltersBar profileSports={profileSports} />
            <UpcomingGames
              currentUserId={user.id}
              games={upcomingGames.map((game) => ({
                id: game.id,
                opponentName: game.createdByUserId === user.id ? game.matchedUser.name : game.createdByUser.name,
                matchId: game.matchId,
                status: game.status,
                outcome: game.outcome,
                outcomeUpdatedAt: game.outcomeUpdatedAt?.toISOString() ?? null,
                proposedDatetime: game.proposedDatetime.toISOString(),
                comment: game.comment,
                sport: game.sport,
                format: game.format,
                createdByUserId: game.createdByUserId,
                matchedUserId: game.matchedUserId,
                proposedCourt: {
                  name: game.proposedCourt.name,
                  address: game.proposedCourt.address
                }
              }))}
            />
          </>
        ) : isSeekingView || isHotView ? (
          <>
            <FiltersBar profileSports={profileSports} />
            <UpcomingGames
              currentUserId={user.id}
              games={upcomingGames.map((game) => ({
                id: game.id,
                opponentName: game.createdByUserId === user.id ? game.matchedUser.name : game.createdByUser.name,
                matchId: game.matchId,
                status: game.status,
                outcome: game.outcome,
                outcomeUpdatedAt: game.outcomeUpdatedAt?.toISOString() ?? null,
                proposedDatetime: game.proposedDatetime.toISOString(),
                comment: game.comment,
                sport: game.sport,
                format: game.format,
                createdByUserId: game.createdByUserId,
                matchedUserId: game.matchedUserId,
                proposedCourt: {
                  name: game.proposedCourt.name,
                  address: game.proposedCourt.address
                }
              }))}
            />
            <SeekingPlayersList
              variant={isHotView ? "hot" : "seeking"}
              users={(isHotView ? hotPlayers : seekingPlayers).map((candidate) => ({
                id: candidate.id,
                name: candidate.name,
                age: candidate.age,
                city: candidate.city,
                bio: candidate.bio,
                avatarUrl: candidate.avatarUrl,
                tennisLevel: candidate.tennisLevel,
                preferredSports: candidate.preferredSports,
                sportLevels: candidate.sportLevels,
                preferredPlayFormat: candidate.preferredPlayFormat,
                distanceLabel: serializeUserPreview(candidate).distanceLabel,
                score: candidate.score,
                availableDays: candidate.availableDays,
                availableTimeRanges: candidate.availableTimeRanges,
                gameSearches: Array.isArray(candidate.gameSearches)
                  ? candidate.gameSearches.map((gameSearch) => ({
                      id: gameSearch.id,
                      preferredDays: gameSearch.preferredDays,
                      preferredTimeRanges: gameSearch.preferredTimeRanges,
                      searchType: gameSearch.searchType,
                      hotWindow: gameSearch.hotWindow,
                      hotStartsAt: gameSearch.hotStartsAt?.toISOString() ?? null,
                      durationMinutes: gameSearch.durationMinutes ?? null,
                      hasCourtBooked: gameSearch.hasCourtBooked,
                      sport: gameSearch.sport,
                      format: gameSearch.format,
                      playersNeeded: gameSearch.playersNeeded ?? 1,
                      comment: gameSearch.comment,
                      responses: Array.isArray(gameSearch.responses)
                        ? gameSearch.responses.map((response) => ({
                            id: response.id,
                            status: response.status
                          }))
                        : [],
                      preferredCourt: gameSearch.preferredCourt
                        ? {
                            name: gameSearch.preferredCourt.name
                          }
                        : null
                    }))
                  : []
              }))}
            />
          </>
        ) : (
          <>
            <SwipeDeck
              key={swipeDeckKey}
              profileSports={profileSports}
              initialUsers={candidates.map((candidate) => ({
                id: candidate.id,
                name: candidate.name,
                age: candidate.age,
                city: candidate.city,
                bio: candidate.bio,
                avatarUrl: candidate.avatarUrl,
                tennisLevel: candidate.tennisLevel,
                preferredSports: candidate.preferredSports,
                sportLevels: candidate.sportLevels,
                preferredPlayFormat: candidate.preferredPlayFormat,
                preferredSurface: candidate.preferredSurface,
                availableDays: candidate.availableDays,
                availableTimeRanges: candidate.availableTimeRanges,
                distanceLabel: serializeUserPreview(candidate).distanceLabel,
                score: candidate.score
              }))}
            />
            <FiltersBar profileSports={profileSports} />
            <UpcomingGames
              currentUserId={user.id}
              games={upcomingGames.map((game) => ({
                id: game.id,
                opponentName: game.createdByUserId === user.id ? game.matchedUser.name : game.createdByUser.name,
                matchId: game.matchId,
                status: game.status,
                outcome: game.outcome,
                outcomeUpdatedAt: game.outcomeUpdatedAt?.toISOString() ?? null,
                proposedDatetime: game.proposedDatetime.toISOString(),
                comment: game.comment,
                sport: game.sport,
                format: game.format,
                createdByUserId: game.createdByUserId,
                matchedUserId: game.matchedUserId,
                proposedCourt: {
                  name: game.proposedCourt.name,
                  address: game.proposedCourt.address
                }
              }))}
            />
          </>
        )}
      </div>
    </PageShell>
  );
}
