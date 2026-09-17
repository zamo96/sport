"use client";

import { useCallback, useEffect, useMemo, useRef } from "react";
import { Check, CheckCheck } from "lucide-react";

import { apiFetch } from "@/lib/client-api";
import { ChatReceiptQueue, receiptLabel, type MessageReceipt } from "@/lib/chat-receipts-client";

type ReceiptScope = { matchId: string } | { gameRequestId: string } | { searchId: string };
type ReceivedMessage = { id: string; senderUserId: string };

export function ChatMessageReceipt({ receipt, group = false }: { receipt?: MessageReceipt; group?: boolean }) {
  if (!receipt) return null;
  const Icon = receipt.status === "sent" ? Check : CheckCheck;
  const label = receiptLabel(receipt, group);
  return (
    <div className={`flex items-center justify-end gap-1 px-2 pb-1 pt-0.5 text-[10px] leading-4 ${receipt.status === "read" ? "text-lime-200" : "text-white/65"}`} aria-label={label} title={label}>
      <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}

export function useChatReceipts(scope: ReceiptScope, currentUserId: string, messages: ReceivedMessage[]) {
  const scopeKey = JSON.stringify(scope);
  const { queue } = useMemo(() => ({ scopeKey, currentUserId, queue: new ChatReceiptQueue() }), [scopeKey, currentUserId]);
  const containerRef = useRef<HTMLDivElement>(null);
  const flush = useCallback(() => {
    void queue.flush((messageIds, status) => apiFetch("/activity/chat-receipts", {
      method: "POST",
      body: JSON.stringify({ ...JSON.parse(scopeKey), messageIds, status })
    })).catch(() => { /* Retain pending acknowledgements for the next retry. */ });
  }, [queue, scopeKey]);

  const receivedMessages = useCallback((received: ReceivedMessage[]) => {
    queue.receive(received.filter((message) => message.senderUserId !== currentUserId).map((message) => message.id));
  }, [currentUserId, queue]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const incomingIds = new Set(messages.filter((message) => message.senderUserId !== currentUserId).map((message) => message.id));
    const visibleIds = new Set<string>();
    const acknowledge = () => {
      queue.observe([...visibleIds], document.visibilityState === "visible" && document.hasFocus());
      flush();
    };
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        const id = (entry.target as HTMLElement).dataset.chatMessageId;
        if (!id) continue;
        if (entry.isIntersecting && entry.intersectionRect.height > 0 && entry.intersectionRect.width > 0) visibleIds.add(id);
        else visibleIds.delete(id);
      }
      acknowledge();
    }, { threshold: [0, 0.5, 1] });
    container.querySelectorAll<HTMLElement>("[data-chat-message-id]").forEach((element) => {
      if (incomingIds.has(element.dataset.chatMessageId ?? "")) observer.observe(element);
    });
    document.addEventListener("visibilitychange", acknowledge);
    window.addEventListener("focus", acknowledge);
    window.addEventListener("online", acknowledge);
    const retry = window.setInterval(acknowledge, 5000);
    flush();
    return () => {
      observer.disconnect();
      document.removeEventListener("visibilitychange", acknowledge);
      window.removeEventListener("focus", acknowledge);
      window.removeEventListener("online", acknowledge);
      window.clearInterval(retry);
    };
  }, [currentUserId, flush, messages, queue]);

  return { containerRef, receivedMessages };
}
