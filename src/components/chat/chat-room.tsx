"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Clock3 } from "lucide-react";
import type { Sport } from "@prisma/client";

import { ChatMessageReceipt, useChatReceipts } from "@/components/chat/chat-receipts";
import { mergeChatMessages } from "@/lib/chat-receipts-client";

import { apiFetch } from "@/lib/client-api";
import { isPastGameRequest } from "@/lib/game-requests";
import { getPrimarySport, getSportLevel } from "@/lib/sport-levels";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { GameRequestCard } from "@/components/chat/game-request-card";
import { SportLevelBadge } from "@/components/ui/sport-level-badge";
import { ChatComposer, ChatMessageAttachments, type ChatMessage as Message } from "@/components/chat/chat-media";

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
    } | null;
  }>;
  showLatestRequest?: boolean;
};

export function ChatRoom(props: ChatRoomProps) {
  return <ChatRoomContent key={`${props.matchId}:${props.currentUserId}`} {...props} />;
}

function ChatRoomContent({
  matchId,
  currentUserId,
  otherUser,
  initialMessages,
  gameRequests,
  showLatestRequest = true
}: ChatRoomProps) {
  const router = useRouter();
  const [messages, setMessages] = useState(initialMessages);
  const { containerRef, receivedMessages } = useChatReceipts({ matchId }, currentUserId, messages);
  const latestRequest = gameRequests[0];
  const upcomingBookedGames = gameRequests.filter(
    (request) => request.status === "accepted" && !isPastGameRequest(request.proposedDatetime)
  );
  const shouldShowLatestRequest = showLatestRequest && latestRequest && !upcomingBookedGames.some((request) => request.id === latestRequest.id);
  const primarySport = getPrimarySport(otherUser.preferredSports);
  const primarySportLevel = getSportLevel(otherUser.sportLevels, primarySport, otherUser.tennisLevel ?? 5);

  const loadMessages = useCallback(async () => {
    try {
      const data = await apiFetch<{ messages: Message[] }>(`/matches/${matchId}/messages`);
      receivedMessages(data.messages);
      setMessages((current) => mergeChatMessages(current, data.messages, { currentUserId }));
    } catch {
      return;
    }
  }, [matchId, receivedMessages, currentUserId]);

  useEffect(() => {
    void loadMessages();
    const interval = window.setInterval(loadMessages, 5000);
    return () => {
      window.clearInterval(interval);
    };
  }, [loadMessages]);

  useEffect(() => {
    const source = new EventSource("/realtime");
    const refreshIfRelevant = (event: MessageEvent) => {
      try {
        const payload = JSON.parse(event.data) as { matchId?: string; href?: string };
        if (payload.matchId === matchId || payload.href === `/inbox/${matchId}`) {
          void loadMessages();
          if (event.type !== "chat_receipts_updated") router.refresh();
        }
      } catch {
        return;
      }
    };

    source.addEventListener("chat_message_created", refreshIfRelevant);
    source.addEventListener("chat_receipts_updated", refreshIfRelevant);
    source.addEventListener("game_request_created", refreshIfRelevant);
    source.addEventListener("game_request_updated", refreshIfRelevant);
    source.addEventListener("match_created", refreshIfRelevant);

    return () => {
      source.close();
    };
  }, [loadMessages, matchId, router]);

  async function sendMessage(text: string, attachmentIds: string[]) {
    const data = await apiFetch<{ message: Message }>(`/matches/${matchId}/messages`, {
      method: "POST",
      body: JSON.stringify({ text, attachmentIds })
    });
    setMessages((current) => mergeChatMessages(current, [data.message]));
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
        <div ref={containerRef} className="space-y-3">
          {messages.length === 0 ? (
            <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-ink/72">
              Напиши короткое сообщение или сразу отправь предложение на игру.
            </div>
          ) : null}
          {messages.map((message) => {
            const mine = message.senderUserId === currentUserId;
            return (
              <div key={message.id} data-chat-message-id={message.id} className={`flex ${mine ? "justify-end" : "justify-start"}`}>
                <div className={`max-w-[80%] rounded-[24px] p-2 text-sm leading-6 ${mine ? "bg-ink text-white" : "bg-cream text-ink"}`}>
                  {!mine ? (
                    <div className="mb-1 px-2 pt-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
                      {message.senderUser.name}
                    </div>
                  ) : null}
                  <ChatMessageAttachments attachments={message.attachments} />
                  {message.text ? <div className="px-2 py-1">{message.text}</div> : null}
                  {mine ? <ChatMessageReceipt receipt={message.receipt} /> : null}
                </div>
              </div>
            );
          })}
        </div>
        <ChatComposer placeholder="Напиши сообщение..." onSend={sendMessage} />
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
