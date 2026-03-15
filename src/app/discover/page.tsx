import { redirect } from "next/navigation";
import { Flame } from "lucide-react";

import { getSessionUser } from "@/lib/auth";
import { discoverFiltersSchema } from "@/lib/validators";
import { PageShell } from "@/components/layout/page-shell";
import { FiltersBar } from "@/components/discover/filters-bar";
import { DiscoverTabs } from "@/components/discover/discover-tabs";
import { SeekingPlayersList } from "@/components/discover/seeking-players-list";
import { SwipeDeck } from "@/components/discover/swipe-deck";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SectionTitle } from "@/components/ui/section-title";
import { PLAY_FORMAT_LABELS } from "@/lib/constants";
import { getSportLevelEntries } from "@/lib/sport-levels";
import { SportBadge } from "@/components/ui/sport-badge";
import { getDiscoverPageData, getHotPlayers, getSeekingPlayers } from "@/server/app-data";
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
  const swipeDeckKey = JSON.stringify({
    view: parsedFilters.view ?? "swipe",
    city: parsedFilters.city ?? null,
    gender: parsedFilters.gender ?? [],
    sport: parsedFilters.sport ?? [],
    format: parsedFilters.format ?? [],
    surface: parsedFilters.surface ?? [],
    day: parsedFilters.day ?? [],
    timeRange: parsedFilters.timeRange ?? [],
    distanceKm: parsedFilters.distanceKm ?? null,
    levelMin: parsedFilters.levelMin ?? null,
    levelMax: parsedFilters.levelMax ?? null
  });
  const isSeekingView = parsedFilters.view === "seeking";
  const isHotView = parsedFilters.view === "hot";
  const userSportLevels = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
  const [{ candidates }, seekingPlayers, hotPlayers] = await Promise.all([
    getDiscoverPageData(user.id, parsedFilters),
    getSeekingPlayers(user.id, parsedFilters),
    getHotPlayers(user.id, parsedFilters)
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
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <a href="/play/searches/new" className="block">
            <Button fullWidth variant="secondary">Создать поиск игры</Button>
          </a>
          <a href="/play/searches/new?mode=hot" className="block">
            <Button fullWidth variant="danger">
              <span className="inline-flex items-center gap-2">
                <Flame className="h-4 w-4" />
                Срочно найти
              </span>
            </Button>
          </a>
          <a href="/play/searches" className="block">
            <Button fullWidth variant="ghost">Мои поиски</Button>
          </a>
        </div>
        <DiscoverTabs />
        <FiltersBar />
        {isSeekingView || isHotView ? (
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
                    hasCourtBooked: gameSearch.hasCourtBooked,
                    sport: gameSearch.sport,
                    format: gameSearch.format,
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
        ) : (
          <SwipeDeck
            key={swipeDeckKey}
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
        )}
      </div>
    </PageShell>
  );
}
