"use client";

import { FormEvent, useState } from "react";
import { SendHorizonal } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { Avatar } from "@/components/ui/avatar";
import { Panel } from "@/components/ui/panel";

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

export function GameRequestChatRoom({
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
  const [text, setText] = useState("");
  const [loading, setLoading] = useState(false);

  async function sendMessage(event: FormEvent) {
    event.preventDefault();
    if (!text.trim()) return;

    setLoading(true);
    try {
      const data = await apiFetch<{ message: Message }>(`/game-requests/${gameRequestId}/messages`, {
        method: "POST",
        body: JSON.stringify({ text })
      });
      setMessages((current) => [...current, data.message]);
      setText("");
    } finally {
      setLoading(false);
    }
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

      <div className="space-y-3">
        {messages.length === 0 ? (
          <div className="rounded-2xl bg-mint px-4 py-3 text-sm text-ink/72">
            Уточните детали этой игры: кто приносит мячи, где встретиться и что делать, если планы изменятся.
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
          className="input min-h-[52px] flex-1 resize-none py-3"
          placeholder="Напиши по этой игре..."
        />
        <button
          type="submit"
          disabled={loading || !text.trim()}
          className="flex h-12 w-12 items-center justify-center rounded-2xl bg-clay text-white disabled:opacity-50"
        >
          <SendHorizonal className="h-5 w-5" />
        </button>
      </form>
    </Panel>
  );
}
