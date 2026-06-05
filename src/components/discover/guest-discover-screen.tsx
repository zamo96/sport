"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { PlayFormat, type Sport } from "@prisma/client";
import { CalendarDays, Flame } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import {
  buildGuestAuthHref,
  guestDraftHasProfileBasics,
  loadGuestOnboardingDraft,
  type GuestOnboardingDraft
} from "@/lib/guest-draft";
import { getSportLevelEntries, normalizeSports } from "@/lib/sport-levels";
import { DiscoverIntroSheet } from "@/components/discover/discover-intro-sheet";
import { DiscoverTabs } from "@/components/discover/discover-tabs";
import { FiltersBar } from "@/components/discover/filters-bar";
import { SeekingPlayersList } from "@/components/discover/seeking-players-list";
import { SwipeDeck } from "@/components/discover/swipe-deck";
import { PageShell } from "@/components/layout/page-shell";
import { Panel } from "@/components/ui/panel";
import { getSportPlayFormatLabelRu } from "@/components/sport-semantics";

type GuestDiscoverUser = {
  id: string;
  name: string | null;
  age: number | null;
  city: string | null;
  district?: string | null;
  districtLabel?: string | null;
  bio: string | null;
  avatarUrl: string | null;
  tennisLevel: number | null;
  preferredSports?: unknown;
  sportLevels?: unknown;
  preferredPlayFormat: PlayFormat;
  preferredSurface: "hard" | "clay" | "grass" | "any";
  distanceLabel: string;
  score: number | null;
  availableDays?: unknown;
  availableTimeRanges?: unknown;
  gameSearches?: Array<{
    id: string;
    status: "active" | "in_review" | "matched" | "closed";
    preferredDays: unknown;
    preferredTimeRanges: unknown;
    searchType: "regular" | "hot";
    hotWindow: "today" | "tomorrow" | "day_after_tomorrow" | null;
    hotStartsAt?: string | null;
    durationMinutes?: number | null;
    hasCourtBooked: boolean;
    sport: Sport;
    format: "singles" | "doubles" | "both";
    playersNeeded?: number | null;
    comment: string | null;
    responses?: Array<{
      id: string;
      status: "pending" | "approved" | "rejected" | "withdrawn";
    }>;
    preferredCourt?: {
      name: string;
    } | null;
  }>;
};

export function GuestDiscoverScreen() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [draft, setDraft] = useState<GuestOnboardingDraft | null>(null);
  const [users, setUsers] = useState<GuestDiscoverUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const currentView =
    searchParams.get("view") === "hot"
      ? "hot"
      : searchParams.get("view") === "seeking"
        ? "seeking"
        : "swipe";
  const currentPath = `${pathname}${searchParams.toString() ? `?${searchParams.toString()}` : ""}`;
  const authHref = buildGuestAuthHref(currentPath);

  useEffect(() => {
    const savedDraft = loadGuestOnboardingDraft();

    if (!savedDraft || !guestDraftHasProfileBasics(savedDraft)) {
      router.replace("/auth");
      return;
    }

    setDraft(savedDraft);
  }, [router]);

  useEffect(() => {
    if (searchParams.get("view") === "likes" || searchParams.get("view") === "upcoming") {
      const params = new URLSearchParams(searchParams.toString());
      params.delete("view");
      router.replace(params.toString() ? `${pathname}?${params.toString()}` : pathname);
    }
  }, [pathname, router, searchParams]);

  useEffect(() => {
    if (!draft) {
      return;
    }

    let cancelled = false;

    async function loadUsers() {
      setLoading(true);
      setError(null);

      try {
        const filters = Object.fromEntries(searchParams.entries());
        const data = await apiFetch<{ users: GuestDiscoverUser[] }>("/users/discover/guest", {
          method: "POST",
          body: JSON.stringify({
            draft,
            filters
          })
        });

        if (!cancelled) {
          setUsers(data.users);
        }
      } catch (requestError) {
        if (!cancelled) {
          setError(requestError instanceof Error ? requestError.message : "Не удалось загрузить подбор");
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void loadUsers();

    return () => {
      cancelled = true;
    };
  }, [draft, searchParams]);

  const profileSports = useMemo(() => normalizeSports(draft?.preferredSports ?? []), [draft]);
  const userSportLevels = useMemo(
    () => getSportLevelEntries(draft?.preferredSports ?? [], draft?.sportLevels, 5),
    [draft]
  );
  const quickSummary = userSportLevels.slice(0, 2).map(({ sport, level }) => `${sport}:${level}`);

  return (
    <PageShell>
      <div className="space-y-3">
        <div className="flex items-center justify-between gap-3 px-1">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.24em] text-court">Гостевой режим</div>
            <h1 className="mt-1 text-[1.65rem] font-bold leading-none text-ink">Игроки рядом</h1>
            <div className="mt-1 text-sm text-ink/62">
              {draft?.name || "Твой профиль"} · {draft ? getSportPlayFormatLabelRu(profileSports[0] ?? null, draft.preferredPlayFormat) : "Формат по умолчанию"}
            </div>
          </div>
        </div>

        {quickSummary.length > 0 ? (
          <Panel className="bg-cream/75 py-3 text-sm leading-6 text-ink/68">
            Уже собран черновик профиля. Смотри карточки и активные поиски, а email попросим только в момент действия.
          </Panel>
        ) : null}

        <DiscoverTabs guestMode />
        <DiscoverIntroSheet incomingLikesCount={0} />

        {currentView === "seeking" || currentView === "hot" ? (
          <Link href={currentView === "hot" ? "/play/searches/new?mode=hot" : "/play/searches/new"} className="block">
            <div
              className={`flex min-h-12 items-center justify-center gap-2 rounded-[22px] px-4 text-sm font-semibold shadow-card ${
                currentView === "hot" ? "bg-red-500 text-white" : "bg-white/85 text-ink"
              }`}
            >
              {currentView === "hot" ? <Flame className="h-4 w-4 text-orange-200" /> : <CalendarDays className="h-4 w-4 text-court" />}
              {currentView === "hot" ? "Создать быструю игру" : "Создать регулярный поиск"}
            </div>
          </Link>
        ) : null}

        {loading ? (
          <Panel className="py-10 text-center text-sm text-ink/60">Подбираем игроков под твой профиль…</Panel>
        ) : error ? (
          <Panel className="bg-red-50 py-6 text-center text-sm text-red-700">{error}</Panel>
        ) : currentView === "seeking" || currentView === "hot" ? (
          <>
            <SeekingPlayersList users={users} variant={currentView} authRequiredHref={authHref} />
            <FiltersBar profileSports={profileSports} />
          </>
        ) : (
          <>
            <SwipeDeck initialUsers={users} profileSports={profileSports as Sport[]} authRequiredHref={authHref} />
            <FiltersBar profileSports={profileSports} />
          </>
        )}
      </div>
    </PageShell>
  );
}
