"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { MapPin, MessageCircleQuestion, Star, X } from "lucide-react";
import type { Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { useLocale } from "@/components/i18n/locale-provider";
import { savePendingGuestAction } from "@/lib/pending-guest-action";
import { cn } from "@/lib/utils";
import { AuthRequiredSheet } from "@/components/auth/auth-required-sheet";
import {
  EmptyDeck,
  ThinDeckInvite,
  type EmptyDeckCourt,
  type EmptyDeckInvite
} from "@/components/discover/empty-deck";
import {
  getDiscoverDayLabel,
  getDiscoverFormatLabel,
  getDiscoverSurfaceLabel,
  getDiscoverTimeLabel,
  translateDiscover,
  translateDiscoverDistanceLabel,
  translateDiscoverReason
} from "@/lib/i18n/web/discover";
import { getSportLevelEntries } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";

type DiscoverUser = {
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
  preferredPlayFormat: "singles" | "doubles" | "both";
  preferredSurface: "hard" | "clay" | "grass" | "any";
  availableDays?: unknown;
  availableTimeRanges?: unknown;
  distanceLabel: string;
  score: number | null;
  explainabilityReasons?: string[] | null;
};

export function SwipeDeck({
  initialUsers,
  profileSports,
  authRequiredHref,
  city = null,
  nearbyCourts = [],
  invite = null
}: {
  initialUsers: DiscoverUser[];
  profileSports: Sport[];
  authRequiredHref?: string;
  city?: string | null;
  nearbyCourts?: EmptyDeckCourt[];
  invite?: EmptyDeckInvite | null;
}) {
  const { locale, t } = useLocale();
  const router = useRouter();
  const [users, setUsers] = useState(initialUsers);
  const [busy, setBusy] = useState(false);
  const [matchId, setMatchId] = useState<string | null>(null);
  const [matchName, setMatchName] = useState<string | null>(null);
  const [authPromptOpen, setAuthPromptOpen] = useState(false);
  const [swipeDecision, setSwipeDecision] = useState<"like" | "dislike" | null>(null);

  useEffect(() => {
    setUsers(initialUsers);
    setSwipeDecision(null);
  }, [initialUsers]);

  const activeUser = users[0];
  const remaining = users.length - 1;

  async function submitSwipe(action: "like" | "dislike") {
    if (!activeUser || busy || swipeDecision) return;

    if (authRequiredHref && action === "like") {
      setAuthPromptOpen(true);
      return;
    }

    if (authRequiredHref && action === "dislike") {
      setSwipeDecision("dislike");
      window.setTimeout(() => {
        setUsers((current) => current.slice(1));
        setSwipeDecision(null);
      }, 240);
      return;
    }

    const currentUser = activeUser;
    setSwipeDecision(action);
    setBusy(true);
    window.setTimeout(async () => {
      try {
        const data = await apiFetch<{ match: { id: string } | null }>("/swipes", {
          method: "POST",
          body: JSON.stringify({ toUserId: currentUser.id, action })
        });

        if (data.match) {
          setMatchId(data.match.id);
          setMatchName(currentUser.name ?? t("discover.swipe.matchFallback"));
        }

        setUsers((current) => current.slice(1));
        router.refresh();
      } catch {
        setUsers((current) => [currentUser, ...current.slice(1)]);
      } finally {
        setBusy(false);
        setSwipeDecision(null);
      }
    }, 220);
  }

  const stack = useMemo(() => users.slice(0, 2), [users]);

  if (stack.length === 0) {
    return <EmptyDeck city={city} seenCount={initialUsers.length} courts={nearbyCourts} invite={invite} />;
  }

  const isThin = initialUsers.length > 0 && initialUsers.length < 3;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-3 px-1">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">{t("discover.swipe.title")}</div>
          <div className="mt-1 text-sm text-ink/70">
            {t("discover.swipe.profileSports", { count: profileSports.length > 0 ? profileSports.length : 0 })}
          </div>
        </div>
        <div className="rounded-[22px] bg-white/80 px-3 py-2 text-right shadow-card">
          <div className="text-[11px] uppercase tracking-[0.18em] text-court">{t("discover.swipe.remaining")}</div>
          <div className="mt-1 font-bold text-ink">{Math.max(remaining, 0)}</div>
        </div>
      </div>

      <div className="relative min-h-[54vh]">
        {stack
          .map((user, index) => (
            (() => {
              const sports = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
              const day = Array.isArray(user.availableDays) ? user.availableDays[0] : null;
              const timeRange = Array.isArray(user.availableTimeRanges) ? user.availableTimeRanges[0] : null;
              const explainabilityReasons = normalizeExplainabilityReasons(user.explainabilityReasons, {
                hasSports: sports.length > 0,
                distanceLabel: user.distanceLabel,
                day,
                timeRange,
                locale
              });

              const baseTransform = index === 0 ? "translate3d(0px, 0px, 0px) scale(1)" : "translate3d(0px, 14px, 0px) scale(0.97)";
              const animatedTransform =
                index === 0 && swipeDecision === "like"
                  ? "translate3d(86px, -6px, 0px) rotate(-9deg) scale(1.01)"
                  : index === 0 && swipeDecision === "dislike"
                    ? "translate3d(-86px, -6px, 0px) rotate(9deg) scale(1.01)"
                    : index === 1 && swipeDecision
                      ? "translate3d(0px, 4px, 0px) scale(0.985)"
                      : baseTransform;

              return (
                <div
                  key={user.id}
                  className={cn(
                    "absolute inset-0 rounded-[34px] border border-white/70 bg-white/88 p-3 shadow-card transition-all duration-300 ease-out",
                    index === 0 && swipeDecision && "opacity-0",
                    index === 1 && swipeDecision && "opacity-100"
                  )}
                  style={{
                    transform: animatedTransform,
                    zIndex: stack.length - index
                  }}
                >
                  <div className="relative flex h-full flex-col overflow-hidden rounded-[28px] bg-gradient-to-b from-court via-court to-ink p-4 text-white">
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.18),transparent_40%)]" />
                {index === 0 ? (
                  <>
                    <div
                      className={cn(
                        "absolute left-4 top-4 rounded-full border border-white/20 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] text-white/90 transition-all duration-200",
                        swipeDecision === "dislike" ? "translate-y-0 rotate-[-8deg] bg-white/18 opacity-100" : "-translate-y-2 opacity-0"
                      )}
                    >
                      {t("discover.swipe.skipStamp")}
                    </div>
                    <div
                      className={cn(
                        "absolute right-4 top-4 rounded-full border border-white/20 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] text-white/90 transition-all duration-200",
                        swipeDecision === "like" ? "translate-y-0 rotate-[8deg] bg-white/18 opacity-100" : "-translate-y-2 opacity-0"
                      )}
                    >
                      {t("discover.swipe.playStamp")}
                    </div>
                  </>
                ) : null}
                    <div className="relative flex items-start justify-between gap-3">
                  <div className="space-y-3">
                    <div className="rounded-full bg-white/16 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em]">
                      {t("discover.swipe.score", { score: user.score ?? 0 })}
                    </div>
                    <Avatar src={user.avatarUrl} alt={user.name ?? t("discover.common.player")} size="lg" className="ring-4 ring-white/15" />
                  </div>
                  <div className="rounded-[24px] bg-white/14 px-3 py-2 text-right backdrop-blur">
                    <div className="text-xs uppercase tracking-[0.2em] text-white/65">{t("discover.swipe.nearby")}</div>
                    <div className="mt-1 text-sm font-bold">{user.distanceLabel ? translateDiscoverDistanceLabel(locale, user.distanceLabel) : "—"}</div>
                    <div className="mt-1 text-xs text-white/70">{user.districtLabel ?? t("discover.swipe.districtUnknown")}</div>
                  </div>
                </div>

                <div className="relative mt-auto">
                  <h3 className="font-[var(--font-heading)] text-[2rem] font-bold leading-none">
                    {user.name ?? t("discover.common.player")} {user.age ? `, ${user.age}` : ""}
                  </h3>
                  <div className="mt-2 flex items-center gap-2 text-sm text-white/72">
                    <MapPin className="h-4 w-4" />
                    {user.city ?? t("discover.common.unspecifiedCity")}
                    {user.districtLabel ? ` · ${user.districtLabel}` : ""}
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2">
                    {sports.slice(0, 2).map(({ sport, level }) => (
                      <SportLevelBadge
                        key={sport}
                        sport={sport}
                        level={level}
                        badgeClassName="bg-white/12 text-white"
                        levelClassName="bg-white/12 text-white"
                        iconClassName="h-3.5 w-3.5 text-white"
                      />
                    ))}
                    <Tag label={getDiscoverFormatLabel(locale, user.preferredPlayFormat)} />
                    <Tag label={getDiscoverSurfaceLabel(locale, user.preferredSurface)} />
                    {day ? <Tag label={getDiscoverDayLabel(locale, String(day))} /> : null}
                    {timeRange ? <Tag label={getDiscoverTimeLabel(locale, String(timeRange))} /> : null}
                  </div>

                  <div className="mt-4 space-y-2 rounded-[24px] bg-white/10 p-3 backdrop-blur">
                    <div className="text-[11px] font-semibold uppercase tracking-[0.24em] text-white/70">{t("discover.swipe.nextStep")}</div>
                    <div className="text-sm font-semibold text-white/90">
                      {t("discover.swipe.nextStepText")}
                    </div>
                    <div className="pt-2 text-[11px] font-semibold uppercase tracking-[0.24em] text-white/70">
                      {t("discover.swipe.why")}
                    </div>
                    {explainabilityReasons.length > 0 ? (
                      <ul className="space-y-1 text-sm leading-6 text-white/82">
                        {explainabilityReasons.slice(0, 3).map((reason) => (
                          <li key={reason} className="flex items-start gap-2">
                            <span className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-white/70" />
                            <span>{reason}</span>
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <div className="text-sm leading-6 text-white/72">
                        {t("discover.swipe.reasonsSoon")}
                      </div>
                    )}
                  </div>

                  <p className="mt-3 line-clamp-3 text-sm leading-6 text-white/82">
                    {user.bio ?? t("discover.swipe.bioFallback")}
                  </p>
                    </div>
                  </div>
                </div>
              );
            })()
          ))
          .reverse()}
      </div>

      <div className="grid grid-cols-[1fr,1.2fr] gap-3">
        <Button
          variant="ghost"
          className={cn("rounded-[24px] transition-all", swipeDecision === "dislike" && "bg-white text-ink shadow-card")}
          onClick={() => submitSwipe("dislike")}
          disabled={busy}
        >
          <X className="mr-2 h-5 w-5" />
          {busy ? "..." : t("discover.common.skip")}
        </Button>
        <Button
          variant="secondary"
          className={cn("rounded-[24px] transition-all", swipeDecision === "like" && "scale-[1.01]")}
          onClick={() => submitSwipe("like")}
          disabled={busy}
        >
          <MessageCircleQuestion className="mr-2 h-5 w-5" />
          {busy ? t("discover.respond.sending") : t("discover.swipe.play")}
        </Button>
      </div>

      {matchId && matchName ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/45 px-4 pb-6">
          <Panel className="w-full max-w-md space-y-3 rounded-[32px] bg-cream">
            <div className="text-xs font-semibold uppercase tracking-[0.24em] text-court">{t("discover.swipe.matchEyebrow")}</div>
            <div className="text-2xl font-bold text-ink">{t("discover.swipe.matchTitle", { name: matchName })}</div>
            <div className="text-sm leading-6 text-ink/65">
              {t("discover.swipe.matchText")}
            </div>
            <div className="grid grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => {
                  setMatchId(null);
                  setMatchName(null);
                }}
                className="rounded-2xl bg-white px-4 py-3 text-sm font-semibold text-ink"
              >
                {t("discover.swipe.continue")}
              </button>
              <Link href={`/inbox/${matchId}`} className="block">
                <div className="rounded-2xl bg-ink px-4 py-3 text-center text-sm font-semibold text-white">{t("discover.swipe.openChat")}</div>
              </Link>
            </div>
          </Panel>
        </div>
      ) : null}

      <AuthRequiredSheet
        open={authPromptOpen}
        onClose={() => setAuthPromptOpen(false)}
        href={authRequiredHref ?? "/auth"}
        title={t("discover.swipe.authTitle")}
        description={t("discover.swipe.authText")}
        onContinue={() => {
          if (!activeUser) {
            return;
          }
          savePendingGuestAction({
            type: "discover_like",
            userId: activeUser.id,
            userName: activeUser.name
          });
        }}
      />
      {isThin ? <ThinDeckInvite invite={invite} city={city} /> : null}
    </div>
  );
}

function Tag({ label }: { label: string }) {
  return <span className="rounded-full bg-white/12 px-3 py-2 text-xs font-semibold text-white">{label}</span>;
}

function normalizeExplainabilityReasons(
  reasons: string[] | null | undefined,
  fallback: {
    hasSports: boolean;
    distanceLabel: string;
    day: unknown;
    timeRange: unknown;
    locale: "en" | "ru";
  }
) {
  const normalized = Array.isArray(reasons) ? reasons.filter((reason): reason is string => typeof reason === "string" && reason.trim().length > 0) : [];
  if (normalized.length > 0) {
    return normalized.map((reason) => translateDiscoverReason(fallback.locale, reason));
  }

  const synthetic: string[] = [];
  if (fallback.hasSports) {
    synthetic.push(translateDiscover(fallback.locale, "discover.reason.sportLevel"));
  }
  if ((fallback.distanceLabel ?? "").trim().length > 0) {
    synthetic.push(translateDiscover(fallback.locale, "discover.reason.distance", {
      distance: translateDiscoverDistanceLabel(fallback.locale, fallback.distanceLabel)
    }));
  }

  const dayKey = typeof fallback.day === "string" ? fallback.day : null;
  const timeKey = typeof fallback.timeRange === "string" ? fallback.timeRange : null;
  const dayLabel = dayKey ? getDiscoverDayLabel(fallback.locale, dayKey) : null;
  const timeLabel = timeKey ? getDiscoverTimeLabel(fallback.locale, timeKey) : null;
  if (dayLabel && timeLabel) {
    synthetic.push(translateDiscover(fallback.locale, "discover.reason.availability", { value: `${dayLabel} · ${timeLabel}` }));
  } else if (dayLabel) {
    synthetic.push(translateDiscover(fallback.locale, "discover.reason.availability", { value: dayLabel }));
  } else if (timeLabel) {
    synthetic.push(translateDiscover(fallback.locale, "discover.reason.availability", { value: timeLabel }));
  }

  return synthetic;
}
