"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { MapPin } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { DAY_LABELS, PLAY_FORMAT_LABELS, SURFACE_LABELS, TIME_RANGE_LABELS } from "@/lib/constants";
import { getSportLevelEntries } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";

type IncomingLikeUser = {
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

export function IncomingLikesList({ users }: { users: IncomingLikeUser[] }) {
  const [items, setItems] = useState(users);

  if (items.length === 0) {
    return (
      <Panel className="text-center">
        <div className="text-xl font-bold text-ink">Пока никто не хочет с тобой сыграть</div>
        <div className="mt-2 text-sm leading-6 text-ink/65">
          Когда кто-то поставит тебе лайк, карточка появится здесь. Ответный лайк сразу откроет общий чат.
        </div>
      </Panel>
    );
  }

  return (
    <div className="space-y-3">
      {items.map((user) => (
        <IncomingLikeCard
          key={user.id}
          user={user}
          onResolved={() => setItems((current) => current.filter((item) => item.id !== user.id))}
        />
      ))}
    </div>
  );
}

function IncomingLikeCard({
  user,
  onResolved
}: {
  user: IncomingLikeUser;
  onResolved: () => void;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const sports = getSportLevelEntries(user.preferredSports, user.sportLevels, user.tennisLevel ?? 5);
  const day = Array.isArray(user.availableDays) ? user.availableDays[0] : null;
  const timeRange = Array.isArray(user.availableTimeRanges) ? user.availableTimeRanges[0] : null;

  async function answer(action: "like" | "dislike") {
    setBusy(true);

    try {
      const data = await apiFetch<{ match: { id: string } | null }>("/swipes", {
        method: "POST",
        body: JSON.stringify({ toUserId: user.id, action })
      });

      onResolved();

      if (action === "like" && data.match) {
        router.push(`/inbox/${data.match.id}`);
        return;
      }

      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel className="space-y-4">
      <div className="flex items-start gap-3">
        <Avatar src={user.avatarUrl} alt={user.name ?? "Игрок"} size="lg" />
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Хочет с тобой сыграть</div>
              <div className="mt-1 text-xl font-bold text-ink">
                {user.name} {user.age ? `, ${user.age}` : ""}
              </div>
              <div className="mt-1 flex items-center gap-2 text-sm text-ink/60">
                <MapPin className="h-4 w-4" />
                {user.city ?? "Город"} · {user.distanceLabel}
              </div>
            </div>
            <div className="rounded-full bg-mint px-3 py-2 text-xs font-semibold text-court">
              Совпадение {user.score ?? 0}
            </div>
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            {sports.slice(0, 2).map(({ sport, level }) => (
              <SportLevelBadge
                key={sport}
                sport={sport}
                level={level}
                badgeClassName="bg-cream text-ink"
                levelClassName="bg-cream text-ink"
              />
            ))}
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {PLAY_FORMAT_LABELS[user.preferredPlayFormat]}
            </span>
            <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
              {SURFACE_LABELS[user.preferredSurface]}
            </span>
            {day ? (
              <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                {DAY_LABELS[day as keyof typeof DAY_LABELS]}
              </span>
            ) : null}
            {timeRange ? (
              <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                {TIME_RANGE_LABELS[timeRange as keyof typeof TIME_RANGE_LABELS]}
              </span>
            ) : null}
          </div>
        </div>
      </div>

      <p className="text-sm leading-6 text-ink/68">
        {user.bio ?? "Похоже, этот игрок хочет быстро договориться и выйти на игру."}
      </p>

      <div className="grid grid-cols-2 gap-3">
        <Button variant="ghost" fullWidth onClick={() => answer("dislike")} disabled={busy}>
          Пропустить
        </Button>
        <Button variant="secondary" fullWidth onClick={() => answer("like")} disabled={busy}>
          Можно поиграть
        </Button>
      </div>
    </Panel>
  );
}
