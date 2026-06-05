"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { MapPin, MessageCircleQuestion, Star, X } from "lucide-react";
import type { Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { savePendingGuestAction } from "@/lib/pending-guest-action";
import { cn } from "@/lib/utils";
import { AuthRequiredSheet } from "@/components/auth/auth-required-sheet";
import { DAY_LABELS, SURFACE_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { getSportLevelEntries } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";
import { getSportPlayFormatLabelRu } from "@/components/sport-semantics";

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
  authRequiredHref
}: {
  initialUsers: DiscoverUser[];
  profileSports: Sport[];
  authRequiredHref?: string;
}) {
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
          setMatchName(currentUser.name ?? "игрок");
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
    return (
      <Panel className="flex min-h-[58vh] flex-col items-center justify-center text-center">
        <div className="rounded-full bg-mint p-4">
          <Star className="h-7 w-7 text-court" />
        </div>
        <h3 className="mt-4 text-2xl font-bold">Карточки закончились</h3>
        <p className="mt-2 max-w-xs text-sm leading-6 text-ink/65">
          Измени спорт в фильтрах или вернись позже, когда появятся новые игроки.
        </p>
        <div className="mt-5 flex gap-3">
          <Link href="/inbox">
            <Button>Открыть мэтчи</Button>
          </Link>
          <Link href="/play/courts">
            <Button variant="ghost">Спортивные центры</Button>
          </Link>
        </div>
      </Panel>
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-3 px-1">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Быстрый подбор</div>
          <div className="mt-1 text-sm text-ink/70">
            По видам спорта из профиля: {profileSports.length > 0 ? profileSports.length : 0}
          </div>
        </div>
        <div className="rounded-[22px] bg-white/80 px-3 py-2 text-right shadow-card">
          <div className="text-[11px] uppercase tracking-[0.18em] text-court">Осталось</div>
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
                timeRange
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
                      Пропуск
                    </div>
                    <div
                      className={cn(
                        "absolute right-4 top-4 rounded-full border border-white/20 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] text-white/90 transition-all duration-200",
                        swipeDecision === "like" ? "translate-y-0 rotate-[8deg] bg-white/18 opacity-100" : "-translate-y-2 opacity-0"
                      )}
                    >
                      Можно играть
                    </div>
                  </>
                ) : null}
                    <div className="relative flex items-start justify-between gap-3">
                  <div className="space-y-3">
                    <div className="rounded-full bg-white/16 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em]">
                      Скор {user.score ?? 0}
                    </div>
                    <Avatar src={user.avatarUrl} alt={user.name ?? "Игрок"} size="lg" className="ring-4 ring-white/15" />
                  </div>
                  <div className="rounded-[24px] bg-white/14 px-3 py-2 text-right backdrop-blur">
                    <div className="text-xs uppercase tracking-[0.2em] text-white/65">Рядом</div>
                    <div className="mt-1 text-sm font-bold">{user.distanceLabel || "—"}</div>
                    <div className="mt-1 text-xs text-white/70">{user.districtLabel ?? "Район не указан"}</div>
                  </div>
                </div>

                <div className="relative mt-auto">
                  <h3 className="font-[var(--font-heading)] text-[2rem] font-bold leading-none">
                    {user.name ?? "Игрок"} {user.age ? `, ${user.age}` : ""}
                  </h3>
                  <div className="mt-2 flex items-center gap-2 text-sm text-white/72">
                    <MapPin className="h-4 w-4" />
                    {user.city ?? "Город не указан"}
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
                    <Tag label={getSportPlayFormatLabelRu(sports[0]?.sport ?? profileSports[0] ?? null, user.preferredPlayFormat)} />
                    <Tag label={SURFACE_LABELS[user.preferredSurface]} />
                    {day ? <Tag label={DAY_LABELS[day as keyof typeof DAY_LABELS]} /> : null}
                    {timeRange ? <Tag label={TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]} /> : null}
                  </div>

                  <div className="mt-4 space-y-2 rounded-[24px] bg-white/10 p-3 backdrop-blur">
                    <div className="text-[11px] font-semibold uppercase tracking-[0.24em] text-white/70">Следующий шаг</div>
                    <div className="text-sm font-semibold text-white/90">
                      Нажми «Можно поиграть», чтобы отправить интерес. Если интерес взаимный — откроется чат.
                    </div>
                    <div className="pt-2 text-[11px] font-semibold uppercase tracking-[0.24em] text-white/70">
                      Почему в подборе
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
                        Скоро здесь появятся причины: спорт, уровень, расстояние и доступность.
                      </div>
                    )}
                  </div>

                  <p className="mt-3 line-clamp-3 text-sm leading-6 text-white/82">
                    {user.bio ?? "Готов(а) быстро договориться, выбрать центр и выйти на игру без длинной переписки."}
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
          {busy ? "..." : "Пропустить"}
        </Button>
        <Button
          variant="secondary"
          className={cn("rounded-[24px] transition-all", swipeDecision === "like" && "scale-[1.01]")}
          onClick={() => submitSwipe("like")}
          disabled={busy}
        >
          <MessageCircleQuestion className="mr-2 h-5 w-5" />
          {busy ? "Отправляем..." : "Можно поиграть"}
        </Button>
      </div>

      {matchId && matchName ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/45 px-4 pb-6">
          <Panel className="w-full max-w-md space-y-3 rounded-[32px] bg-cream">
            <div className="text-xs font-semibold uppercase tracking-[0.24em] text-court">Это мэтч</div>
            <div className="text-2xl font-bold text-ink">У тебя взаимный интерес с {matchName}</div>
            <div className="text-sm leading-6 text-ink/65">
              Теперь можно перейти в общий чат и договориться о деталях или сразу выбрать спортивный центр.
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
                Продолжить поиск
              </button>
              <Link href={`/inbox/${matchId}`} className="block">
                <div className="rounded-2xl bg-ink px-4 py-3 text-center text-sm font-semibold text-white">Открыть чат</div>
              </Link>
            </div>
          </Panel>
        </div>
      ) : null}

      <AuthRequiredSheet
        open={authPromptOpen}
        onClose={() => setAuthPromptOpen(false)}
        href={authRequiredHref ?? "/auth"}
        title="Подтверди email, чтобы отправить интерес"
        description="Профиль уже собран. После подтверждения почты ты сможешь лайкать, открывать чат и получать ответ от игрока."
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
  }
) {
  const normalized = Array.isArray(reasons) ? reasons.filter((reason): reason is string => typeof reason === "string" && reason.trim().length > 0) : [];
  if (normalized.length > 0) {
    return normalized;
  }

  const synthetic: string[] = [];
  if (fallback.hasSports) {
    synthetic.push("Совпадают спорт и уровень");
  }
  if ((fallback.distanceLabel ?? "").trim().length > 0) {
    synthetic.push(`По расстоянию: ${fallback.distanceLabel}`);
  }

  const dayKey = typeof fallback.day === "string" ? fallback.day : null;
  const timeKey = typeof fallback.timeRange === "string" ? fallback.timeRange : null;
  const dayLabel = dayKey && dayKey in DAY_LABELS ? DAY_LABELS[dayKey as keyof typeof DAY_LABELS] : null;
  const timeLabel = timeKey && timeKey in TIME_RANGE_LABELS ? TIME_RANGE_LABELS[timeKey as keyof typeof TIME_RANGE_LABELS] : null;
  if (dayLabel && timeLabel) {
    synthetic.push(`По доступности: ${dayLabel} · ${timeLabel}`);
  } else if (dayLabel) {
    synthetic.push(`По доступности: ${dayLabel}`);
  } else if (timeLabel) {
    synthetic.push(`По доступности: ${timeLabel}`);
  }

  return synthetic;
}
