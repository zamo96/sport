import { redirect } from "next/navigation";
import { Bell, CalendarDays, Flame, HeartHandshake, ListChecks, Plus, Search } from "lucide-react";

import { getSessionUser } from "@/lib/auth";
import { discoverFiltersSchema } from "@/lib/validators";
import { PageShell } from "@/components/layout/page-shell";
import { FiltersBar } from "@/components/discover/filters-bar";
import { DiscoverTabs } from "@/components/discover/discover-tabs";
import { GuestDiscoverScreen } from "@/components/discover/guest-discover-screen";
import { IncomingLikesList } from "@/components/discover/incoming-likes-list";
import { SeekingPlayersList } from "@/components/discover/seeking-players-list";
import { UpcomingGames } from "@/components/discover/upcoming-games";
import { SwipeDeck } from "@/components/discover/swipe-deck";
import { Button } from "@/components/ui/button";
import { normalizeSports } from "@/lib/sport-levels";
import {
  getActiveSearchesCount,
  getDiscoverPageData,
  getHotNotificationsCount,
  getHotPlayers,
  getIncomingLikePlayers,
  getIncomingLikesCount,
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
    return <GuestDiscoverScreen />;
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
  const [{ candidates }, incomingLikePlayers, seekingPlayers, hotPlayers, upcomingGames, activeSearchesCount, incomingLikesCount, hotCount] = await Promise.all([
    getDiscoverPageData(user.id, effectiveFilters),
    getIncomingLikePlayers(user.id, effectiveFilters),
    getSeekingPlayers(user.id, effectiveFilters),
    getHotPlayers(user.id, effectiveFilters),
    getUpcomingGamesForUser(user.id),
    getActiveSearchesCount(user.id),
    getIncomingLikesCount(user.id),
    getHotNotificationsCount(user.id)
  ]);
  const upcomingGameCards = upcomingGames.map((game) => ({
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
  }));
  const urgentCount = incomingLikesCount + hotCount;

  return (
    <PageShell>
      <div className="space-y-3">
        <div className="flex items-center justify-between gap-3 px-1">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.24em] text-court">Поиск</div>
            <h1 className="mt-1 text-[1.65rem] font-bold leading-none text-ink">Игроки рядом</h1>
          </div>
          <div className="flex items-center gap-2">
            <a href="/play/searches" className="shrink-0">
              <div className="inline-flex min-h-11 items-center gap-2 rounded-[20px] bg-white/85 px-3 text-sm font-semibold text-ink shadow-card">
                <ListChecks className="h-4 w-4 text-court" />
                <span>Мои</span>
                <span
                  className={`rounded-full px-2 py-1 text-[11px] font-bold leading-none ${
                    activeSearchesCount > 0 ? "bg-red-500 text-white" : "bg-line text-ink/60"
                  }`}
                >
                  {activeSearchesCount}
                </span>
              </div>
            </a>
            <a href="/notifications" className="shrink-0">
              <div className="relative flex min-h-12 min-w-12 items-center justify-center rounded-[22px] bg-white/85 shadow-card">
                <Bell className="h-5 w-5 text-ink" />
                {urgentCount > 0 ? (
                  <span className="absolute -right-1 -top-1 flex min-h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white">
                    {urgentCount > 99 ? "99+" : urgentCount}
                  </span>
                ) : null}
              </div>
            </a>
          </div>
        </div>

        <DiscoverTabs incomingLikesCount={incomingLikesCount} />

        <DiscoverViewHint
          view={isLikesView ? "likes" : isHotView ? "hot" : isSeekingView ? "seeking" : "swipe"}
          hotCount={hotCount}
          incomingLikesCount={incomingLikesCount}
        />

        {isSeekingView || isHotView ? (
          <a href={isHotView ? "/play/searches/new?mode=hot" : "/play/searches/new"} className="block">
            <div
              className={`flex min-h-12 items-center justify-center gap-2 rounded-[22px] px-4 text-sm font-semibold shadow-card ${
                isHotView ? "bg-red-500 text-white" : "bg-white/85 text-ink"
              }`}
            >
              {isHotView ? <Flame className="h-4 w-4 text-orange-200" /> : <CalendarDays className="h-4 w-4 text-court" />}
              {isHotView ? `Создать быструю игру · сейчас ищут ${hotCount}` : "Создать регулярный поиск"}
            </div>
          </a>
        ) : null}

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
            <UpcomingGames currentUserId={user.id} games={upcomingGameCards} />
            <FiltersBar profileSports={profileSports} />
          </>
        ) : isSeekingView || isHotView ? (
          <>
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
                      selfLevel: gameSearch.selfLevel ?? null,
                      selfLevelUnknown: gameSearch.selfLevelUnknown,
                      desiredLevelMin: gameSearch.desiredLevelMin ?? 1,
                      desiredLevelMax: gameSearch.desiredLevelMax ?? 10,
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
            <FiltersBar profileSports={profileSports} />
            <UpcomingGames currentUserId={user.id} games={upcomingGameCards} />
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
            <UpcomingGames currentUserId={user.id} games={upcomingGameCards} />
          </>
        )}

      </div>
    </PageShell>
  );
}

function DiscoverViewHint({
  view,
  hotCount,
  incomingLikesCount
}: {
  view: "swipe" | "likes" | "seeking" | "hot";
  hotCount: number;
  incomingLikesCount: number;
}) {
  const config =
    view === "likes"
      ? {
          icon: HeartHandshake,
          title: "Те, кто уже проявил интерес",
          text:
            incomingLikesCount > 0
              ? "Здесь игроки, которые уже хотят сыграть с тобой. Ответный лайк сразу откроет чат."
              : "Пока входящих лайков нет."
        }
      : view === "hot"
        ? {
            icon: Flame,
            title: "Быстрые игры на ближайшие часы",
            text: `Сюда попадают события на сегодня и завтра. Сейчас активных быстрых поисков: ${hotCount}.`
          }
        : view === "seeking"
          ? {
              icon: CalendarDays,
              title: "Регулярный поиск партнёра",
              text:
                "Это игроки, которые заранее ищут партнёра по дням и интервалам времени. Здесь удобно договариваться без спешки."
            }
          : {
              icon: Search,
              title: "Похожие игроки по профилю",
              text:
                "Карточки уже отсортированы по спорту, уровню, доступности и расстоянию. Можно сразу пропустить или договориться."
            };

  const Icon = config.icon;

  return (
    <div className="rounded-[24px] bg-white/72 px-4 py-3 shadow-card">
      <div className="flex items-start gap-3">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-cream text-court">
          <Icon className="h-4.5 w-4.5" />
        </div>
        <div className="min-w-0">
          <div className="text-sm font-semibold text-ink">{config.title}</div>
          <div className="mt-1 text-xs leading-5 text-ink/62">{config.text}</div>
        </div>
      </div>
    </div>
  );
}
