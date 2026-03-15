"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Heart, MapPin, Star, X } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { DAY_LABELS, PLAY_FORMAT_LABELS, SURFACE_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { getSportLevelEntries } from "@/lib/sport-levels";
import { cn } from "@/lib/utils";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";

type DiscoverUser = {
  id: string;
  name: string | null;
  age: number | null;
  city: string | null;
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
};

export function SwipeDeck({ initialUsers }: { initialUsers: DiscoverUser[] }) {
  const router = useRouter();
  const [users, setUsers] = useState(initialUsers);
  const [dragX, setDragX] = useState(0);
  const [isSwiping, setIsSwiping] = useState(false);
  const [matchId, setMatchId] = useState<string | null>(null);
  const [matchName, setMatchName] = useState<string | null>(null);
  const startX = useRef<number | null>(null);

  useEffect(() => {
    setUsers(initialUsers);
    setDragX(0);
    setIsSwiping(false);
  }, [initialUsers]);

  const activeUser = users[0];
  const remaining = users.length - 1;
  const angle = dragX / 24;
  const overlay = dragX > 18 ? "ЛАЙК" : dragX < -18 ? "ПРОПУСК" : null;

  async function submitSwipe(action: "like" | "dislike" | "superlike") {
    if (!activeUser || isSwiping) return;

    setIsSwiping(true);
    try {
      const data = await apiFetch<{ match: { id: string } | null }>("/swipes", {
        method: "POST",
        body: JSON.stringify({ toUserId: activeUser.id, action })
      });

      if (data.match) {
        setMatchId(data.match.id);
        setMatchName(activeUser.name ?? "игрок");
      }

      setUsers((current) => current.slice(1));
      setDragX(0);
      router.refresh();
    } catch {
      setDragX(0);
    } finally {
      setIsSwiping(false);
    }
  }

  function onPointerDown(event: React.PointerEvent<HTMLDivElement>) {
    startX.current = event.clientX;
  }

  function onPointerMove(event: React.PointerEvent<HTMLDivElement>) {
    if (startX.current == null || isSwiping) return;
    setDragX(event.clientX - startX.current);
  }

  function onPointerUp() {
    if (startX.current == null || isSwiping) return;
    if (dragX > 110) {
      submitSwipe("like");
    } else if (dragX < -110) {
      submitSwipe("dislike");
    } else {
      setDragX(0);
    }
    startX.current = null;
  }

  const stack = useMemo(() => users.slice(0, 3), [users]);

  return (
    <div className="space-y-4">
      <Panel className="grid grid-cols-2 gap-3">
        <div className="rounded-[24px] bg-cream p-3">
          <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-clay">Свайп влево</div>
          <div className="mt-1 text-sm font-semibold text-ink">Не интересно</div>
          <div className="mt-1 text-xs leading-5 text-ink/60">Пропустить игрока и перейти к следующей карточке.</div>
        </div>
        <div className="rounded-[24px] bg-mint p-3">
          <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-court">Свайп вправо</div>
          <div className="mt-1 text-sm font-semibold text-ink">Лайк</div>
          <div className="mt-1 text-xs leading-5 text-ink/60">
            Игрок увидит, что ты, возможно, хочешь сыграть именно с ним.
          </div>
        </div>
      </Panel>

      <div className="relative h-[490px]">
        {stack.length === 0 ? (
          <Panel className="flex h-full flex-col items-center justify-center text-center">
            <div className="rounded-full bg-mint p-4">
              <Star className="h-7 w-7 text-court" />
            </div>
            <h3 className="mt-4 text-2xl font-bold">Карточки закончились</h3>
            <p className="mt-2 max-w-xs text-sm leading-6 text-ink/65">
              Измени фильтры, загляни позже или перейди к кортам для текущих мэтчей.
            </p>
            <div className="mt-5 flex gap-3">
              <Link href="/inbox">
                <Button>Открыть мэтчи</Button>
              </Link>
              <Link href="/play/courts">
                <Button variant="ghost">Посмотреть корты</Button>
              </Link>
            </div>
          </Panel>
        ) : null}

        {stack
          .map((user, index) => {
            const isTop = index === 0;
            const day = Array.isArray(user.availableDays) ? user.availableDays[0] : null;
            const timeRange = Array.isArray(user.availableTimeRanges) ? user.availableTimeRanges[0] : null;
            const sports = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
            return (
              <div
                key={user.id}
                className={cn(
                  "absolute inset-0 rounded-[34px] border border-white/70 bg-white/88 p-4 shadow-card transition",
                  !isTop && "scale-[0.96] opacity-85"
                )}
                style={{
                  transform: isTop
                    ? `translateX(${dragX}px) rotate(${angle}deg)`
                    : `translateY(${index * 10}px) scale(${1 - index * 0.03})`,
                  zIndex: stack.length - index
                }}
                onPointerDown={isTop ? onPointerDown : undefined}
                onPointerMove={isTop ? onPointerMove : undefined}
                onPointerUp={isTop ? onPointerUp : undefined}
                onPointerCancel={isTop ? onPointerUp : undefined}
              >
                {isTop && overlay ? (
                  <div
                    className={cn(
                      "absolute left-4 top-4 rounded-full border px-3 py-1 text-xs font-black uppercase tracking-[0.3em]",
                      dragX > 0 ? "border-court text-court" : "border-clay text-clay"
                    )}
                  >
                    {overlay}
                  </div>
                ) : null}

                <div className="relative h-full overflow-hidden rounded-[28px] bg-gradient-to-b from-court via-court to-ink p-5 text-white">
                  <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.18),transparent_40%)]" />
                  <div className="relative flex h-full flex-col">
                    <div className="flex items-start justify-between">
                      <div className="space-y-3">
                        <div className="rounded-full bg-white/16 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em]">
                          Скор {user.score ?? 0}
                        </div>
                        <Avatar src={user.avatarUrl} alt={user.name ?? "Игрок"} size="xl" className="ring-4 ring-white/15" />
                      </div>
                      <div className="rounded-[24px] bg-white/14 px-3 py-2 text-right backdrop-blur">
                        <div className="text-xs uppercase tracking-[0.2em] text-white/65">Расстояние</div>
                        <div className="mt-1 text-lg font-bold">{user.distanceLabel}</div>
                      </div>
                    </div>

                    <div className="mt-auto">
                      <h3 className="font-[var(--font-heading)] text-4xl font-bold leading-none">
                        {user.name ?? "Игрок"} {user.age ? `, ${user.age}` : ""}
                      </h3>
                      <div className="mt-2 flex items-center gap-2 text-sm text-white/72">
                        <MapPin className="h-4 w-4" />
                        {user.city ?? "Город не указан"}
                      </div>
                      <div className="mt-4 flex flex-wrap gap-2">
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
                        <Tag label={PLAY_FORMAT_LABELS[user.preferredPlayFormat]} />
                        <Tag label={SURFACE_LABELS[user.preferredSurface]} />
                        {day ? <Tag label={DAY_LABELS[day as keyof typeof DAY_LABELS]} /> : null}
                        {timeRange ? (
                          <Tag label={TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]} />
                        ) : null}
                      </div>
                      <p className="mt-4 line-clamp-4 text-sm leading-6 text-white/82">
                        {user.bio ?? "Готов(а) к игре и короткой договоренности без лишней переписки."}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            );
          })
          .reverse()}
      </div>

      {activeUser ? (
        <div className="grid grid-cols-[1fr,1.2fr,1fr] gap-3">
          <Button variant="ghost" className="rounded-[24px]" onClick={() => submitSwipe("dislike")}>
            <X className="mr-2 h-5 w-5" />
            Пропустить
          </Button>
          <Button variant="primary" className="rounded-[24px]" onClick={() => submitSwipe("superlike")}>
            <Star className="mr-2 h-5 w-5" />
            Суперлайк
          </Button>
          <Button variant="secondary" className="rounded-[24px]" onClick={() => submitSwipe("like")}>
            <Heart className="mr-2 h-5 w-5" />
            Лайк
          </Button>
        </div>
      ) : null}

      <Panel className="flex items-center justify-between">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-ink/50">Очередь</div>
          <div className="mt-1 text-xl font-bold text-ink">Осталось {Math.max(remaining, 0)} карточек</div>
        </div>
        <Link href="/play/courts" className="text-sm font-semibold text-clay">
          Сначала выбрать корт
        </Link>
      </Panel>

      {matchId && matchName ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/45 px-4 pb-6">
          <Panel className="w-full max-w-md space-y-3 rounded-[32px] bg-cream">
            <div className="text-xs font-semibold uppercase tracking-[0.24em] text-court">Это мэтч</div>
            <h3 className="text-3xl font-bold leading-none text-ink">{matchName} тоже поставил(а) лайк.</h3>
            <p className="text-sm leading-6 text-ink/68">
              Переходи в чат и сразу отправляй предложение с кортом и временем.
            </p>
            <div className="grid grid-cols-2 gap-3">
              <Button variant="ghost" fullWidth onClick={() => setMatchId(null)}>
                Продолжить свайпы
              </Button>
              <Link href={`/inbox/${matchId}`} className="block">
                <Button fullWidth>Открыть чат</Button>
              </Link>
            </div>
          </Panel>
        </div>
      ) : null}
    </div>
  );
}

function Tag({ label }: { label: string }) {
  return <span className="rounded-full bg-white/14 px-3 py-2 text-xs font-semibold">{label}</span>;
}
