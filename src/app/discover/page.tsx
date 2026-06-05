import { redirect } from "next/navigation";
import { CalendarDays, Flame, ListChecks } from "lucide-react";

import { getSessionUser } from "@/lib/auth";
import { discoverFiltersSchema } from "@/lib/validators";
import { PageShell } from "@/components/layout/page-shell";
import { FiltersBar } from "@/components/discover/filters-bar";
import { DiscoverTabs } from "@/components/discover/discover-tabs";
import { DiscoverIntroSheet } from "@/components/discover/discover-intro-sheet";
import { DiscoverPendingActionRunner } from "@/components/discover/discover-pending-action-runner";
import { NotificationCenterButton } from "@/components/discover/notification-center-button";
import { GuestDiscoverScreen } from "@/components/discover/guest-discover-screen";
import { IncomingLikesList } from "@/components/discover/incoming-likes-list";
import { SeekingPlayersList } from "@/components/discover/seeking-players-list";
import { RegularPairsList } from "@/components/discover/regular-pairs-list";
import { UpcomingGames } from "@/components/discover/upcoming-games";
import { SwipeDeck } from "@/components/discover/swipe-deck";
import { Button } from "@/components/ui/button";
import { normalizeSports } from "@/lib/sport-levels";
import {
  getActiveSearchesCount,
  getActiveRegularPairsForUser,
  getDiscoverPageData,
  getHotNotificationsCount,
  getHotPlayers,
  getIncomingLikePlayers,
  getIncomingLikesCount,
  getSeekingPlayers,
  getUpcomingGamesForUser
} from "@/server/app-data";
import { serializeUserPreview } from "@/server/serializers";

function buildUpcomingOpponentLabel(
  game: Awaited<ReturnType<typeof getUpcomingGamesForUser>>[number],
  currentUserId: string
) {
  const participants =
    "participants" in game && Array.isArray(game.participants)
      ? game.participants.filter((participant) => participant.id !== currentUserId)
      : [];

  if (participants.length >= 3) {
    return `${participants[0]?.name ?? "Игрок"} и еще ${participants.length - 1}`;
  }

  if (participants.length === 2) {
    return participants.map((participant) => participant.name ?? "Игрок").join(" и ");
  }

  if (participants.length === 1) {
    return participants[0]?.name ?? "Игрок";
  }

  return game.createdByUserId === currentUserId ? game.matchedUser.name : game.createdByUser.name;
}

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
  const isUpcomingView = effectiveFilters.view === "upcoming";
  const isSeekingView = effectiveFilters.view === "seeking";
  const isHotView = effectiveFilters.view === "hot";
  const highlightSearchId = typeof searchParams.highlight === "string" ? searchParams.highlight : undefined;
  const [{ candidates }, incomingLikePlayers, seekingPlayers, hotPlayers, upcomingGames, activeSearchesCount, incomingLikesCount, hotCount, activeRegularPairs] = await Promise.all([
    getDiscoverPageData(user.id, effectiveFilters),
    getIncomingLikePlayers(user.id, effectiveFilters),
    getSeekingPlayers(user.id, effectiveFilters),
    getHotPlayers(user.id, effectiveFilters),
    getUpcomingGamesForUser(user.id),
    getActiveSearchesCount(user.id),
    getIncomingLikesCount(user.id),
    getHotNotificationsCount(user.id),
    getActiveRegularPairsForUser(user.id)
  ]);
  const upcomingGameCards = upcomingGames.map((game) => ({
    id: game.id,
    opponentName: buildUpcomingOpponentLabel(game, user.id),
    matchId: game.matchId,
    searchLobbyId: "searchLobbyId" in game ? game.searchLobbyId ?? null : null,
    sourceType:
      "sourceType" in game && game.sourceType === "regular_occurrence"
        ? ("regular_occurrence" as const)
        : ("game_request" as const),
    regularPairId: "regularPairId" in game ? game.regularPairId ?? null : null,
    status: game.status,
    outcome: game.outcome,
    outcomeUpdatedAt: game.outcomeUpdatedAt?.toISOString() ?? null,
    proposedDatetime: game.proposedDatetime.toISOString(),
    comment: game.comment,
    sport: game.sport,
    format: game.format,
    createdByUserId: game.createdByUserId,
    matchedUserId: game.matchedUserId,
    participants:
      "participants" in game && Array.isArray(game.participants)
        ? game.participants
            .filter(
              (
                participant
              ): participant is typeof participant & {
                id: string;
                name: string | null;
              } => typeof participant.id === "string"
            )
            .map((participant) => ({
              id: participant.id,
              name: participant.name ?? null
            }))
        : [],
    proposedCourt: {
      name: game.proposedCourt.name,
      address: game.proposedCourt.address
    }
  }));
  const urgentCount = incomingLikesCount + hotCount;
  const regularSearchCount = seekingPlayers.filter(
    (candidate) =>
      Array.isArray(candidate.gameSearches) &&
      candidate.gameSearches[0] &&
      candidate.gameSearches[0].searchType === "regular"
  ).length;

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
            <NotificationCenterButton count={urgentCount} />
          </div>
        </div>

        <DiscoverTabs
          upcomingCount={upcomingGameCards.length}
          incomingLikesCount={incomingLikesCount}
          regularCount={regularSearchCount}
        />
        <DiscoverIntroSheet incomingLikesCount={incomingLikesCount} />
        <DiscoverPendingActionRunner />

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

        {isUpcomingView ? (
          upcomingGameCards.length > 0 ? (
            <UpcomingGames currentUserId={user.id} games={upcomingGameCards} />
          ) : (
            <div className="rounded-[28px] border border-white/70 bg-white/84 px-5 py-10 text-center shadow-card">
              <div className="text-xl font-bold text-ink">Ближайших игр пока нет</div>
              <div className="mt-2 text-sm leading-6 text-ink/62">
                Как только кто-то подтвердит игру или ты договоришься в чате, она появится здесь.
              </div>
            </div>
          )
        ) : isLikesView ? (
          <>
            <IncomingLikesList
              users={incomingLikePlayers.map((candidate) => {
                const preview = serializeUserPreview(candidate);
                return {
                  id: candidate.id,
                  name: candidate.name,
                  age: candidate.age,
                  city: candidate.city,
                  district: candidate.district,
                  districtLabel: preview.districtLabel,
                  bio: candidate.bio,
                  avatarUrl: candidate.avatarUrl,
                  tennisLevel: candidate.tennisLevel,
                  preferredSports: candidate.preferredSports,
                  sportLevels: candidate.sportLevels,
                  preferredPlayFormat: candidate.preferredPlayFormat,
                  preferredSurface: candidate.preferredSurface,
                  availableDays: candidate.availableDays,
                  availableTimeRanges: candidate.availableTimeRanges,
                  distanceLabel: preview.distanceLabel,
                  score: candidate.score,
                  explainabilityReasons: preview.explainabilityReasons
                };
              })}
            />
            <FiltersBar profileSports={profileSports} />
          </>
        ) : isSeekingView || isHotView ? (
          <>
            {isSeekingView ? (
              <RegularPairsList
                pairs={activeRegularPairs.map((pair) => ({
                  id: pair.id,
                  sport: pair.sport,
                  format: pair.format,
                  preferredDays: pair.preferredDays,
                  preferredTimeRanges: pair.preferredTimeRanges,
                  preferredCourt: pair.preferredCourt
                    ? {
                        name: pair.preferredCourt.name
                      }
                    : null,
                  partner: {
                    name: pair.createdByUserId === user.id ? pair.partnerUser.name : pair.createdByUser.name,
                    avatarUrl: pair.createdByUserId === user.id ? pair.partnerUser.avatarUrl : pair.createdByUser.avatarUrl
                  },
                  nextOccurrence: pair.occurrences[0]
                    ? {
                        id: pair.occurrences[0].id,
                        scheduledAt: pair.occurrences[0].scheduledAt.toISOString(),
                        status: pair.occurrences[0].status,
                        gameRequest: pair.occurrences[0].gameRequest
                          ? {
                              id: pair.occurrences[0].gameRequest.id
                            }
                          : null
                      }
                    : null
                }))}
              />
            ) : null}
            <SeekingPlayersList
              currentUserId={user.id}
              variant={isHotView ? "hot" : "seeking"}
              highlightSearchId={highlightSearchId}
              users={(isHotView ? hotPlayers : seekingPlayers).map((candidate) => {
                const preview = serializeUserPreview(candidate);
                return {
                  id: candidate.id,
                  name: candidate.name,
                  age: candidate.age,
                  city: candidate.city,
                  district: candidate.district,
                  districtLabel: preview.districtLabel,
                  bio: candidate.bio,
                  avatarUrl: candidate.avatarUrl,
                  tennisLevel: candidate.tennisLevel,
                  preferredSports: candidate.preferredSports,
                  sportLevels: candidate.sportLevels,
                  preferredPlayFormat: candidate.preferredPlayFormat,
                  distanceLabel: preview.distanceLabel,
                  score: candidate.score,
                  availableDays: candidate.availableDays,
                  availableTimeRanges: candidate.availableTimeRanges,
                  explainabilityReasons: preview.explainabilityReasons,
                  gameSearches: Array.isArray(candidate.gameSearches)
                    ? candidate.gameSearches.map((gameSearch) => ({
                        id: gameSearch.id,
                        status: gameSearch.status,
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
                              responderUserId: response.responderUserId,
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
                };
              })}
            />
            <FiltersBar profileSports={profileSports} />
          </>
        ) : (
          <>
            <SwipeDeck
              key={swipeDeckKey}
              profileSports={profileSports}
              initialUsers={candidates.map((candidate) => {
                const preview = serializeUserPreview(candidate);
                return {
                  id: candidate.id,
                  name: candidate.name,
                  age: candidate.age,
                  city: candidate.city,
                  district: candidate.district,
                  districtLabel: preview.districtLabel,
                  bio: candidate.bio,
                  avatarUrl: candidate.avatarUrl,
                  tennisLevel: candidate.tennisLevel,
                  preferredSports: candidate.preferredSports,
                  sportLevels: candidate.sportLevels,
                  preferredPlayFormat: candidate.preferredPlayFormat,
                  preferredSurface: candidate.preferredSurface,
                  availableDays: candidate.availableDays,
                  availableTimeRanges: candidate.availableTimeRanges,
                  distanceLabel: preview.distanceLabel,
                  score: candidate.score,
                  explainabilityReasons: preview.explainabilityReasons
                };
              })}
            />
            <FiltersBar profileSports={profileSports} />
          </>
        )}

      </div>
    </PageShell>
  );
}
