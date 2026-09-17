"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { PlayFormat, type Sport } from "@prisma/client";
import { CalendarDays, Flame } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

import { apiFetch } from "@/lib/client-api";
import {
  buildGuestAuthHref,
  guestDraftCanCompleteOnboarding,
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
import { useLocale } from "@/components/i18n/locale-provider";
import { getDiscoverFormatLabel, translateDiscover } from "@/lib/i18n/web/discover";

import type { NearbyContext } from "@/components/discover/nearby-notice";
import type { EmptyDeckSection } from "@/components/discover/empty-deck";
import { getAuthSportLabel } from "@/lib/i18n/web/auth";

type GuestDiscoverUser = {
  nearby?: NearbyContext | null;
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
  const [clubSections, setClubSections] = useState<EmptyDeckSection[]>([]);
  const [clubRequestUrl, setClubRequestUrl] = useState<string | null>(null);
  const [clubLoadFailed, setClubLoadFailed] = useState(false);
  const [clubRetry, setClubRetry] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { locale } = useLocale();
  const t = (key: Parameters<typeof translateDiscover>[1]) => translateDiscover(locale, key);

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

    if (!savedDraft || !guestDraftCanCompleteOnboarding(savedDraft)) {
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
      setClubRequestUrl(null);

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
          setClubSections([]);
          setLoading(false);
          if (currentView === "swipe" && (data.users.length === 0 || data.users.some((user) => user.nearby))) {
            const selectedCity = searchParams.get("city") || draft!.city || "";
            const nearbyQuery = new URLSearchParams({ city: selectedCity });
            const selectedPlaceId = searchParams.get("locationPlaceId") || (selectedCity === draft!.city ? draft!.locationPlaceId : null);
            if (selectedPlaceId) nearbyQuery.set("locationPlaceId", selectedPlaceId);
            const selectedSports = searchParams.get("sport") || normalizeSports(draft!.preferredSports).join(",");
            if (selectedSports) nearbyQuery.set("sport", selectedSports);
            const selectedRadius = searchParams.get("distanceKm");
            if (selectedRadius) nearbyQuery.set("maxDistanceKm", selectedRadius);
            setClubRequestUrl(`/discover/empty-state?${nearbyQuery}`);
          }
        }
      } catch (requestError) {
        if (!cancelled) {
          setError(requestError instanceof Error ? requestError.message : translateDiscover(locale, "discover.guest.error"));
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
  }, [currentView, draft, locale, searchParams]);

  useEffect(() => {
    let cancelled = false;
    setClubSections([]);
    setClubLoadFailed(false);
    if (!clubRequestUrl) return;

    async function loadClubs() {
      try {
        const empty = await apiFetch<{ sections: EmptyDeckSection[] }>(clubRequestUrl!);
        if (!cancelled) setClubSections(empty.sections.map((section) => ({
          ...section, sportLabel: getAuthSportLabel(locale, section.sport as Sport)
        })));
      } catch {
        if (!cancelled) setClubLoadFailed(true);
      }
    }
    void loadClubs();
    return () => { cancelled = true; };
  }, [clubRequestUrl, clubRetry, locale]);

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
            <div className="text-xs font-semibold uppercase tracking-[0.24em] text-court">{t("discover.guest.eyebrow")}</div>
            <h1 className="mt-1 text-[1.65rem] font-bold leading-none text-ink">{t("discover.page.title")}</h1>
            <div className="mt-1 text-sm text-ink/62">
              {draft?.name || t("discover.guest.profile")} · {draft ? getDiscoverFormatLabel(locale, draft.preferredPlayFormat) : t("discover.guest.defaultFormat")}
            </div>
          </div>
        </div>

        {quickSummary.length > 0 ? (
          <Panel className="bg-cream/75 py-3 text-sm leading-6 text-ink/68">
            {t("discover.guest.draft")}
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
              {currentView === "hot" ? t("discover.guest.createHot") : t("discover.page.createRegular")}
            </div>
          </Link>
        ) : null}

        {loading ? (
          <Panel className="py-10 text-center text-sm text-ink/60">{t("discover.guest.loading")}</Panel>
        ) : error ? (
          <Panel className="bg-red-50 py-6 text-center text-sm text-red-700">{error}</Panel>
        ) : currentView === "seeking" || currentView === "hot" ? (
          <>
            <SeekingPlayersList users={users} variant={currentView} authRequiredHref={authHref} />
            <FiltersBar profileSports={profileSports} />
          </>
        ) : (
          <>
            <SwipeDeck initialUsers={users} profileSports={profileSports as Sport[]} authRequiredHref={authHref} city={searchParams.get("city") || draft?.city} clubSections={clubSections} />
            {clubLoadFailed ? <Panel className="space-y-2 text-sm">
              <p role="status">{t("discover.nearby.clubsError")}</p>
              <button type="button" className="font-semibold text-court underline" onClick={() => setClubRetry((value) => value + 1)}>{t("discover.nearby.retry")}</button>
            </Panel> : null}
            <FiltersBar profileSports={profileSports} />
          </>
        )}
      </div>
    </PageShell>
  );
}
