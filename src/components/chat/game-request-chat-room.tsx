"use client";

import { useCallback, useEffect, useState } from "react";

import { ChatMessageReceipt, useChatReceipts } from "@/components/chat/chat-receipts";
import { mergeChatMessages } from "@/lib/chat-receipts-client";

import { apiFetch } from "@/lib/client-api";
import { Avatar } from "@/components/ui/avatar";
import { Panel } from "@/components/ui/panel";
import { ChatComposer, ChatMessageAttachments, type ChatMessage as Message } from "@/components/chat/chat-media";

export function GameRequestChatRoom(props: Parameters<typeof GameRequestChatRoomContent>[0]) {
  return <GameRequestChatRoomContent key={`${props.gameRequestId}:${props.currentUserId}`} {...props} />;
}

function GameRequestChatRoomContent({
  gameRequestId,
  currentUserId,
  otherUser,
  initialMessages
}: {
  gameRequestId: string;
  currentUserId: string;
  otherUser: {
    name: string | null;
    avatarUrl: string | null;
  };
  initialMessages: Message[];
}) {
  const [messages, setMessages] = useState(initialMessages);
  const { containerRef, receivedMessages } = useChatReceipts({ gameRequestId }, currentUserId, messages);

  const loadMessages = useCallback(async () => {
    try {
      const data = await apiFetch<{ messages: Message[] }>(`/game-requests/${gameRequestId}/messages`);
      receivedMessages(data.messages);
      setMessages((current) => mergeChatMessages(current, data.messages, { currentUserId }));
    } catch {
      return;
    }
  }, [gameRequestId, receivedMessages, currentUserId]);

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
        const payload = JSON.parse(event.data) as { gameRequestId?: string; href?: string };
        if (payload.gameRequestId === gameRequestId || payload.href === `/play/games/${gameRequestId}`) {
          void loadMessages();
        }
      } catch {
        return;
      }
    };

    source.addEventListener("chat_message_created", refreshIfRelevant);
    source.addEventListener("chat_receipts_updated", refreshIfRelevant);
    source.addEventListener("game_request_updated", refreshIfRelevant);

    return () => {
      source.close();
    };
  }, [gameRequestId, loadMessages]);

  async function sendMessage(text: string, attachmentIds: string[]) {
    const data = await apiFetch<{ message: Message }>(`/game-requests/${gameRequestId}/messages`, {
      method: "POST",
      body: JSON.stringify({ text, attachmentIds })
    });
    setMessages((current) => mergeChatMessages(current, [data.message]));
  }

  return (
    <Panel className="space-y-4">
      <div className="flex items-center gap-3">
        <Avatar src={otherUser.avatarUrl} alt={otherUser.name ?? "Партнер"} />
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.22em] text-court">Чат игры</div>
          <div className="mt-1 text-lg font-bold text-ink">{otherUser.name ?? "Партнер"}</div>
          <div className="text-sm text-ink/60">Здесь обсуждается только эта конкретная договоренность.</div>
        </div>
      </div>

      <div ref={containerRef} className="space-y-3">
        {messages.length === 0 ? (
          <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-ink/72">
            Уточните детали этой игры: кто приносит мячи, где встретиться и что делать, если планы изменятся.
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

      <ChatComposer placeholder="Напиши по этой игре..." onSend={sendMessage} />
    </Panel>
  );
}
