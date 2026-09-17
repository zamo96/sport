"use client";

import { useEffect, useState } from "react";
import { CalendarDays, MessageCircleMore, Users2 } from "lucide-react";
import type { Sport } from "@prisma/client";

import { ChatMessageReceipt, useChatReceipts } from "@/components/chat/chat-receipts";
import { mergeChatMessages } from "@/lib/chat-receipts-client";

import { apiFetch } from "@/lib/client-api";
import { DAY_LABELS, SPORT_LABELS, getTimePreferenceLabel } from "@/lib/constants";
import { resolveSearchNextStep } from "@/lib/game-search";
import { CourtSmartPicker } from "@/components/forms/court-smart-picker";
import { getSportPlayFormatLabelRu } from "@/components/sport-semantics";
import { Avatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Panel } from "@/components/ui/panel";
import { SportBadge } from "@/components/ui/sport-badge";
import { ChatComposer, ChatMessageAttachments, type ChatMessage as LobbyMessage } from "@/components/chat/chat-media";

type LobbyResponse = {
  id: string;
  status: "pending" | "approved" | "rejected" | "withdrawn";
  responderUserId: string;
  responderUser: {
    id: string;
    name: string | null;
    avatarUrl: string | null;
  };
};

type CourtOption = {
  id: string;
  name: string;
  address: string;
  district?: string | null;
  nearestMetroName?: string | null;
  metroNames?: string[];
};

type GameSearchLobbyProps = {
  search: {
    id: string;
    createdByUserId: string;
    searchType: "regular" | "hot";
    status: "active" | "in_review" | "matched" | "closed";
    isActive: boolean;
    sport: Sport;
    format: "singles" | "doubles" | "both";
    preferredDays: unknown;
    preferredTimeRanges: unknown;
    hotStartsAt?: string | null;
    durationMinutes?: number | null;
    playersNeeded: number;
    comment: string | null;
    scheduledAt?: string | null;
    scheduledDurationMinutes?: number | null;
    scheduledCourt?: { id: string; name: string } | null;
    regularPairMatchId?: string | null;
    preferredCourt?: { id: string; name: string } | null;
    responses: LobbyResponse[];
    messages: LobbyMessage[];
  };
  currentUserId: string;
  courts: CourtOption[];
};

function normalizeStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

export function GameSearchLobby(props: GameSearchLobbyProps) {
  return <GameSearchLobbyContent key={`${props.search.id}:${props.currentUserId}`} {...props} />;
}

function GameSearchLobbyContent({ search, currentUserId, courts }: GameSearchLobbyProps) {
  const [messages, setMessages] = useState(search.messages);
  const { containerRef, receivedMessages } = useChatReceipts({ searchId: search.id }, currentUserId, messages);
  const [scheduledCourtId, setScheduledCourtId] = useState(search.scheduledCourt?.id ?? "");
  const [scheduledAt, setScheduledAt] = useState(() => {
    if (search.scheduledAt) {
      return new Date(search.scheduledAt).toISOString().slice(0, 16);
    }
    const date = new Date(Date.now() + 24 * 60 * 60 * 1000);
    date.setHours(19, 0, 0, 0);
    return date.toISOString().slice(0, 16);
  });
  const [scheduledDurationMinutes, setScheduledDurationMinutes] = useState(search.scheduledDurationMinutes ?? 90);
  const [loadingSchedule, setLoadingSchedule] = useState(false);
  const isCreator = search.createdByUserId === currentUserId;
  const approvedResponses = search.responses.filter((response) => response.status === "approved");
  const participantResponses = search.responses.filter(
    (response) => response.status === "approved" || response.status === "pending"
  );
  const days = normalizeStringArray(search.preferredDays);
  const timeRanges = normalizeStringArray(search.preferredTimeRanges);
  const scheduleLabel = `${days.map((day) => DAY_LABELS[day as keyof typeof DAY_LABELS]).join(", ")} · ${timeRanges
    .map(getTimePreferenceLabel)
    .join(", ")}`.trim();
  const assignedGameLabel = search.scheduledAt
    ? `${new Date(search.scheduledAt).toLocaleString("ru-RU", {
        day: "2-digit",
        month: "2-digit",
        hour: "2-digit",
        minute: "2-digit"
      })}${search.scheduledDurationMinutes ? ` · ${search.scheduledDurationMinutes} мин` : ""}`
    : null;
  const canAssignGame = isCreator && approvedResponses.length > 0;
  const usesFixedHotSettings = search.searchType === "hot" && Boolean(search.hotStartsAt) && Boolean(search.preferredCourt?.id);
  const shouldCreateRegularPairGame =
    search.searchType === "regular" &&
    Math.max(search.playersNeeded, 1) === 1 &&
    approvedResponses.length === 1 &&
    Boolean(search.regularPairMatchId);
  const nextStep = resolveSearchNextStep({
    searchType: search.searchType,
    status: search.status,
    approvedCount: approvedResponses.length,
    playersNeeded: search.playersNeeded,
    scheduledAt: search.scheduledAt,
    regularPairMatchId: search.regularPairMatchId
  });

  useEffect(() => {
    let active = true;

    async function refreshLobby() {
      try {
        const data = await apiFetch<{
          gameSearch: {
            messages: LobbyMessage[];
          };
        }>(`/game-searches/${search.id}`);
        if (active) {
          receivedMessages(data.gameSearch.messages);
          setMessages((current) => mergeChatMessages(current, data.gameSearch.messages, { currentUserId }));
        }
      } catch {
        return;
      }
    }

    void refreshLobby();
    const source = new EventSource("/realtime");
    const refreshIfRelevant = (event: MessageEvent) => {
      try {
        const payload = JSON.parse(event.data) as { searchId?: string };
        if (payload.searchId === search.id) void refreshLobby();
      } catch { /* Ignore malformed events; polling remains available. */ }
    };
    source.addEventListener("chat_message_created", refreshIfRelevant);
    source.addEventListener("chat_receipts_updated", refreshIfRelevant);
    const interval = window.setInterval(refreshLobby, 5000);
    return () => {
      active = false;
      source.close();
      window.clearInterval(interval);
    };
  }, [search.id, receivedMessages, currentUserId]);

  async function sendMessage(text: string, attachmentIds: string[]) {
    const data = await apiFetch<{ message: LobbyMessage }>(`/game-searches/${search.id}/messages`, {
      method: "POST",
      body: JSON.stringify({ text, attachmentIds })
    });
    setMessages((current) => mergeChatMessages(current, [data.message]));
  }

  async function assignGame() {
    const finalCourtId = usesFixedHotSettings ? search.preferredCourt?.id ?? "" : scheduledCourtId;
    const finalScheduledAt = usesFixedHotSettings ? search.hotStartsAt ?? "" : scheduledAt;
    const finalDurationMinutes = usesFixedHotSettings ? search.durationMinutes ?? 90 : scheduledDurationMinutes;

    if (!finalCourtId || !finalScheduledAt) {
      return;
    }

    setLoadingSchedule(true);
    try {
      const scheduledText = `${new Date(finalScheduledAt).toLocaleString("ru-RU", {
        day: "2-digit",
        month: "2-digit",
        hour: "2-digit",
        minute: "2-digit"
      })} · ${finalDurationMinutes} мин.`;

      if (shouldCreateRegularPairGame && search.regularPairMatchId) {
        await apiFetch("/game-requests", {
          method: "POST",
          body: JSON.stringify({
            matchId: search.regularPairMatchId,
            proposedCourtId: finalCourtId,
            proposedDatetime: new Date(finalScheduledAt).toISOString(),
            durationMinutes: finalDurationMinutes,
            levelRangeMin: 1,
            levelRangeMax: 10,
            sport: search.sport,
            format: search.format,
            comment: search.comment ?? "Предложение ближайшей игры по регулярной договоренности."
          })
        });

        await apiFetch(`/game-searches/${search.id}/messages`, {
          method: "POST",
          body: JSON.stringify({
            text: `Организатор создал ближайшую игру: ${scheduledText}. Детали можно обсудить в чате игры.`
          })
        });

        window.location.href = `/inbox/${search.regularPairMatchId}`;
        return;
      }

      const scheduleResult = await apiFetch<{ gameRequestId?: string | null }>(`/game-searches/${search.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          scheduledCourtId: finalCourtId,
          scheduledAt: new Date(finalScheduledAt).toISOString(),
          scheduledDurationMinutes: finalDurationMinutes
        })
      });

      await apiFetch(`/game-searches/${search.id}/messages`, {
        method: "POST",
        body: JSON.stringify({
          text: `Организатор закрыл набор и назначил игру: ${scheduledText}.`
        })
      });

      const nextGameRequestId = scheduleResult.gameRequestId ?? null;
      if (nextGameRequestId) {
        window.location.href = `/play/games/${nextGameRequestId}`;
        return;
      }

      window.location.reload();
    } finally {
      setLoadingSchedule(false);
    }
  }

  return (
    <div className="space-y-4">
      <Panel className="space-y-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Лобби поиска</div>
            <div className="mt-1 text-xl font-bold text-ink">{SPORT_LABELS[search.sport]}</div>
            <div className="mt-1 text-sm text-ink/60">
              {getSportPlayFormatLabelRu(search.sport, search.format, { playersNeeded: search.playersNeeded })}
              {scheduleLabel ? ` · ${scheduleLabel}` : ""}
            </div>
          </div>
          <SportBadge sport={search.sport} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="rounded-2xl bg-cream px-4 py-3">
            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-court">
              <Users2 className="h-4 w-4" />
              Состав
            </div>
            <div className="mt-2 text-sm font-semibold text-ink">
              Подтверждено {approvedResponses.length} из {Math.max(search.playersNeeded, 1)}
            </div>
          </div>
          <div className="rounded-2xl bg-cream px-4 py-3">
            <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.18em] text-court">
              <CalendarDays className="h-4 w-4" />
              Игра
            </div>
            <div className="mt-2 text-sm font-semibold text-ink">
              {assignedGameLabel ?? "Пока не назначена"}
            </div>
          </div>
        </div>

        {search.comment ? (
          <div className="rounded-2xl bg-mint px-4 py-3 text-sm leading-6 text-ink/75">{search.comment}</div>
        ) : null}

        {search.scheduledCourt || search.scheduledAt ? (
          <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-ink/75">
            Игра назначена{search.scheduledCourt ? ` · ${search.scheduledCourt.name}` : ""}{assignedGameLabel ? ` · ${assignedGameLabel}` : ""}.
          </div>
        ) : null}

        {nextStep.description ? (
          <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/75">
            {nextStep.description}
          </div>
        ) : null}

        {canAssignGame ? (
          <div className="rounded-[24px] border border-mint/70 bg-white/75 p-4">
            <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">
              {shouldCreateRegularPairGame
                ? "Создать игру пары"
                : usesFixedHotSettings
                  ? "Подтвердить срочное событие"
                  : "Закрыть набор и назначить игру"}
            </div>
            <div className="mt-3 grid grid-cols-1 gap-3">
              {usesFixedHotSettings ? (
                <div className="rounded-2xl bg-cream px-4 py-3 text-sm text-ink/74">
                  Срочное событие сохранит исходные настройки:
                  <div className="mt-2 font-semibold text-ink">
                    {search.preferredCourt?.name ?? "Клуб не указан"} ·{" "}
                    {new Date(search.hotStartsAt ?? "").toLocaleString("ru-RU", {
                      day: "2-digit",
                      month: "2-digit",
                      hour: "2-digit",
                      minute: "2-digit"
                    })}
                    {search.durationMinutes ? ` · ${search.durationMinutes} мин` : ""}
                  </div>
                </div>
              ) : (
                <>
                  <CourtSmartPicker
                    courts={courts}
                    selectedCourtId={scheduledCourtId}
                    onSelect={setScheduledCourtId}
                    emptyLabel="Без клуба"
                    emptyDescription="Оставить общий слот без привязки к конкретному клубу"
                    maxInitialItems={16}
                  />
                  <input
                    type="datetime-local"
                    className="input"
                    value={scheduledAt}
                    onChange={(event) => setScheduledAt(event.target.value)}
                  />
                  <select
                    className="input"
                    value={scheduledDurationMinutes}
                    onChange={(event) => setScheduledDurationMinutes(Number(event.target.value))}
                  >
                    {[60, 90, 120, 150].map((duration) => (
                      <option key={duration} value={duration}>
                        {duration} мин
                      </option>
                    ))}
                  </select>
                </>
              )}
              <Button
                fullWidth
                onClick={assignGame}
                disabled={
                  loadingSchedule ||
                  (usesFixedHotSettings
                    ? !search.preferredCourt?.id || !search.hotStartsAt
                    : !scheduledCourtId || !scheduledAt)
                }
              >
                {loadingSchedule
                  ? shouldCreateRegularPairGame
                    ? "Отправляем..."
                    : "Назначаем..."
                  : shouldCreateRegularPairGame
                    ? "Создать ближайшую игру"
                    : usesFixedHotSettings
                      ? "Подтвердить событие по этим условиям"
                      : "Закрыть набор и назначить игру"}
              </Button>
            </div>
          </div>
        ) : null}
      </Panel>

      <Panel className="space-y-3">
        <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.22em] text-court">
          <MessageCircleMore className="h-4 w-4" />
          Общий чат поиска
        </div>
        <div className="space-y-2">
          {participantResponses.map((response) => (
            <div key={response.id} className="flex items-center gap-3 rounded-2xl bg-cream px-4 py-3">
              <Avatar src={response.responderUser.avatarUrl} alt={response.responderUser.name ?? "Игрок"} />
              <div className="min-w-0 flex-1">
                <div className="text-sm font-semibold text-ink">{response.responderUser.name ?? "Игрок"}</div>
                <div className="text-xs text-ink/60">{response.status === "approved" ? "В составе" : "Откликнулся"}</div>
              </div>
            </div>
          ))}
        </div>
        <div ref={containerRef} className="space-y-3">
          {messages.map((message) => {
            const mine = message.senderUserId === currentUserId;
            return (
              <div key={message.id} data-chat-message-id={message.id} className={`flex ${mine ? "justify-end" : "justify-start"}`}>
                <div className={`max-w-[84%] rounded-[22px] p-2 text-sm leading-6 ${mine ? "bg-ink text-white" : "bg-cream text-ink"}`}>
                  {!mine ? (
                    <div className="mb-1 px-2 pt-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-court">
                      {message.senderUser.name}
                    </div>
                  ) : null}
                  <ChatMessageAttachments attachments={message.attachments} />
                  {message.text ? <div className="px-2 py-1">{message.text}</div> : null}
                  {mine ? <ChatMessageReceipt receipt={message.receipt} group /> : null}
                </div>
              </div>
            );
          })}
        </div>
        <ChatComposer placeholder="Сообщение для состава..." sendLabel="Отправить" onSend={sendMessage} />
      </Panel>
    </div>
  );
}
