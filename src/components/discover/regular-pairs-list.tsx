"use client";

import Link from "next/link";
import type { Sport } from "@prisma/client";

import { DAY_LABELS, SPORT_LABELS, getTimePreferenceLabel } from "@/lib/constants";
import { getSportPlayFormatLabelRu } from "@/components/sport-semantics";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";

type RegularPairCard = {
  id: string;
  sport: Sport;
  format: "singles" | "doubles" | "both";
  preferredDays: unknown;
  preferredTimeRanges: unknown;
  preferredCourt?: {
    name: string;
  } | null;
  partner: {
    name: string | null;
    avatarUrl: string | null;
  };
  nextOccurrence?: {
    id: string;
    scheduledAt: string;
    status: "pending" | "confirmed" | "declined" | "canceled" | "expired";
    gameRequest?: {
      id: string;
    } | null;
  } | null;
};

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function buildScheduleLabel(preferredDays: unknown, preferredTimeRanges: unknown) {
  const days = normalizeStringArray(preferredDays)
    .slice(0, 3)
    .map((day) => DAY_LABELS[day as keyof typeof DAY_LABELS]);
  const timeRanges = normalizeStringArray(preferredTimeRanges)
    .slice(0, 2)
    .map(getTimePreferenceLabel);

  return [days.join(", "), timeRanges.join(", ")].filter(Boolean).join(" · ");
}

function resolveOccurrenceLabel(pair: RegularPairCard) {
  if (!pair.nextOccurrence) {
    return "Ближайший слот появится автоматически";
  }

  const time = new Date(pair.nextOccurrence.scheduledAt).toLocaleString("ru-RU", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });

  if (pair.nextOccurrence.gameRequest) {
    return `Ближайшая игра создана · ${time}`;
  }

  if (pair.nextOccurrence.status === "confirmed") {
    return `Слот подтверждён · ${time}`;
  }

  if (pair.nextOccurrence.status === "declined") {
    return `Этот слот не подошёл · ${time}`;
  }

  return `Нужен ответ по слоту · ${time}`;
}

export function RegularPairsList({ pairs }: { pairs: RegularPairCard[] }) {
  if (pairs.length === 0) {
    return null;
  }

  return (
    <div className="space-y-3">
      <div className="px-1">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Уже играете регулярно</div>
        <div className="mt-1 text-sm text-ink/62">
          Сначала текущие регулярные пары, ниже новые игроки, которые ищут партнёра.
        </div>
      </div>

      {pairs.map((pair) => (
        <Panel key={pair.id} className="space-y-3 bg-white/88">
          <div className="flex items-center gap-3">
            <Avatar src={pair.partner.avatarUrl} alt={pair.partner.name ?? "Игрок"} />
            <div className="min-w-0">
              <div className="text-base font-bold text-ink">{pair.partner.name ?? "Игрок"}</div>
              <div className="mt-1 flex flex-wrap items-center gap-2">
                <SportBadge sport={pair.sport} />
                <span className="rounded-full bg-cream px-3 py-2 text-xs font-semibold text-ink">
                  {getSportPlayFormatLabelRu(pair.sport, pair.format)}
                </span>
              </div>
            </div>
          </div>

          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/72">
            <div className="font-semibold text-ink">{resolveOccurrenceLabel(pair)}</div>
            <div className="mt-1">
              {SPORT_LABELS[pair.sport]} · {buildScheduleLabel(pair.preferredDays, pair.preferredTimeRanges) || "Расписание уточняется"}
              {pair.preferredCourt?.name ? ` · ${pair.preferredCourt.name}` : ""}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Link href={`/play/regular/${pair.id}`}>
              <Button fullWidth>Открыть регулярку</Button>
            </Link>
            <Link href={pair.nextOccurrence?.gameRequest ? `/play/games/${pair.nextOccurrence.gameRequest.id}` : `/play/regular/${pair.id}`}>
              <Button fullWidth variant="secondary">
                {pair.nextOccurrence?.gameRequest ? "Открыть игру" : "Проверить слот"}
              </Button>
            </Link>
          </div>
        </Panel>
      ))}
    </div>
  );
}
