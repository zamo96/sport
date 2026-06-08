"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { Clock3, SendHorizonal } from "lucide-react";
import type { Sport } from "@prisma/client";

import { apiFetch } from "@/lib/client-api";
import { isPastGameRequest } from "@/lib/game-requests";
import { getPrimarySport, getSportLevel } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { GameRequestCard } from "@/components/chat/game-request-card";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";

type Message = {
  id: string;
  senderUserId: string;
  text: string;
  createdAt: string;
  senderUser: {
    name: string | null;
    avatarUrl: string | null;
  };
};

type ChatRoomProps = {
  matchId: string;
  currentUserId: string;
  otherUser: {
    name: string | null;
    avatarUrl: string | null;
    lastActiveAt?: string | null;
    tennisLevel: number | null;
    preferredSports?: unknown;
    sportLevels?: unknown;
  };
  initialMessages: Message[];
  gameRequests: Array<{
    id: string;
    status: "pending" | "accepted" | "declined" | "canceled";
    outcome?: "played" | "not_played" | null;
    outcomeUpdatedAt?: string | null;
    proposedDatetime: string;
    durationMinutes?: number | null;
    comment: string | null;
    sport: Sport;
    format: string;
    createdByUserId: string;
    matchedUserId: string;
    proposedCourt: {
      name: string;
      address: string;
    };
  }>;
  showLatestRequest?: boolean;
};

export function ChatRoom({
  matchId,
  currentUserId,
  otherUser,
  initialMessages,
  gameRequests,
  showLatestRequest = true
}: ChatRoomProps) {
  const [messages, setMessages] = useState(initialMessages);
  const [text, setText] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const latestRequest = gameRequests[0];
  const upcomingBookedGames = gameRequests.filter(
    (request) => request.status === "accepted" && !isPastGameRequest(request.proposedDatetime)
  );
  const shouldShowLatestRequest = showLatestRequest && latestRequest && !upcomingBookedGames.some((request) => request.id === latestRequest.id);
  const primarySport = getPrimarySport(otherUser.preferredSports);
  const primarySportLevel = getSportLevel(otherUser.sportLevels, primarySport, otherUser.tennisLevel ?? 5);

  useEffect(() => {
    let active = true;

    async function loadMessages() {
      try {
        const data = await apiFetch<{ messages: Message[] }>(`/matches/${matchId}/messages`);
        if (active) {
          setMessages(data.messages);
        }
      } catch {
        return;
      }
    }

    const interval = window.setInterval(loadMessages, 5000);
    return () => {
      active = false;
      window.clearInterval(interval);
    };
  }, [matchId]);

  async function sendMessage(event: FormEvent) {
    event.preventDefault();
    if (!text.trim()) return;

    setLoading(true);
    setError(null);
    try {
      const data = await apiFetch<{ message: Message }>(`/matches/${matchId}/messages`, {
        method: "POST",
        body: JSON.stringify({ text })
      });
      setMessages((current) => [...current, data.message]);
      setText("");
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Не удалось отправить сообщение");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-4">
      <Panel className="space-y-3">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <div className="flex min-w-0 items-center gap-3">
            <Avatar src={otherUser.avatarUrl} alt={otherUser.name ?? "Партнер"} />
            <div className="min-w-0 flex-1">
              <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Партнер</div>
              <div className="mt-1 truncate text-xl font-bold text-ink">{otherUser.name}</div>
              <div className="mt-1 inline-flex items-center gap-1.5 text-xs font-medium text-ink/55">
                <Clock3 className="h-3.5 w-3.5 text-court/80" />
                {formatPresence(otherUser.lastActiveAt)}
              </div>
            </div>
          </div>
          <Link href={`/play/proposals/new?matchId=${matchId}`} className="sm:ml-auto">
            <Button variant="secondary" className="w-full sm:w-auto">Предложить игру</Button>
          </Link>
        </div>
        <div className="rounded-[18px] bg-cream/80 px-3 py-2.5">
          <div className="flex flex-wrap gap-2">
            <SportLevelBadge
              sport={primarySport}
              level={primarySportLevel}
              badgeClassName="bg-white text-ink"
              levelClassName="bg-white text-ink"
            />
          </div>
        </div>
      </Panel>

      {upcomingBookedGames.length > 0 ? (
        <div className="space-y-3">
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Уже забронировано</div>
          {upcomingBookedGames.map((request) => (
            <GameRequestCard
              key={request.id}
              gameRequest={request}
              currentUserId={currentUserId}
              detailsHref={`/play/games/${request.id}`}
            />
          ))}
        </div>
      ) : null}

      {shouldShowLatestRequest && latestRequest ? (
        <GameRequestCard
          gameRequest={latestRequest}
          currentUserId={currentUserId}
          detailsHref={`/play/games/${latestRequest.id}`}
        />
      ) : null}

      <Panel className="space-y-3">
        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Чат</div>
        <div className="space-y-3">
          {messages.length === 0 ? (
            <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-ink/72">
              Напиши короткое сообщение или сразу отправь предложение на игру.
            </div>
          ) : null}
          {messages.map((message) => {
            const mine = message.senderUserId === currentUserId;
            return (
              <div key={message.id} className={`flex ${mine ? "justify-end" : "justify-start"}`}>
                <div className={`max-w-[80%] rounded-[24px] px-4 py-3 text-sm leading-6 ${mine ? "bg-ink text-white" : "bg-cream text-ink"}`}>
                  {!mine ? (
                    <div className="mb-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
                      {message.senderUser.name}
                    </div>
                  ) : null}
                  {message.text}
                </div>
              </div>
            );
          })}
        </div>
        <form onSubmit={sendMessage} className="flex items-end gap-2">
          <textarea
            rows={2}
            value={text}
            onChange={(event) => setText(event.target.value)}
            className="input min-h-[52px] min-w-0 flex-1 resize-none py-3 text-sm placeholder:text-sm"
            placeholder="Напиши сообщение..."
          />
          <button
            type="submit"
            disabled={loading || !text.trim()}
            className="flex h-12 w-12 items-center justify-center rounded-2xl bg-clay text-white disabled:opacity-50"
          >
            <SendHorizonal className="h-5 w-5" />
          </button>
        </form>
        {error ? <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div> : null}
      </Panel>
    </div>
  );
}

function formatPresence(lastActiveAt?: string | null) {
  if (!lastActiveAt) {
    return "Редко заходит";
  }

  const date = new Date(lastActiveAt);
  const diffMinutes = Math.max(0, Math.round((Date.now() - date.getTime()) / 60000));

  if (diffMinutes <= 5) {
    return "Сейчас онлайн";
  }

  if (diffMinutes < 60) {
    return `Был ${diffMinutes} мин назад`;
  }

  const diffHours = Math.round(diffMinutes / 60);
  if (diffHours < 24) {
    return `Был ${diffHours} ч назад`;
  }

  return `Был ${date.toLocaleDateString("ru-RU")}`;
}
