export type MessageReceipt = {
  status: "sent" | "delivered" | "read";
  deliveredCount: number;
  readCount: number;
};

const receiptRank = { sent: 0, delivered: 1, read: 2 };

/** A late poll must not erase a newer send or regress a confirmed receipt. */
export function mergeChatMessages<T extends { id: string; createdAt: string; senderUserId?: string; receipt?: MessageReceipt }>(
  current: T[], incoming: T[], snapshot?: { currentUserId: string }
): T[] {
  const incomingIds = new Set(incoming.map((message) => message.id));
  // A full fetch also carries access changes (for example a newly blocked sender).
  const retained = snapshot
    ? current.filter((message) => message.senderUserId === snapshot.currentUserId || incomingIds.has(message.id))
    : current;
  const messages = new Map(retained.map((message) => [message.id, message]));
  for (const message of incoming) {
    const previous = messages.get(message.id);
    let receipt = message.receipt ?? previous?.receipt;
    if (previous?.receipt && receipt) {
      receipt = {
        status: receiptRank[previous.receipt.status] > receiptRank[receipt.status] ? previous.receipt.status : receipt.status,
        deliveredCount: Math.max(previous.receipt.deliveredCount, receipt.deliveredCount),
        readCount: Math.max(previous.receipt.readCount, receipt.readCount)
      };
    }
    messages.set(message.id, { ...message, ...(receipt ? { receipt } : {}) });
  }
  return [...messages.values()].sort((left, right) => left.createdAt.localeCompare(right.createdAt));
}

export function receiptLabel(receipt?: MessageReceipt, group = false): string {
  if (!receipt) return "";
  if (group && receipt.status !== "sent") {
    return receipt.readCount > 0
      ? `Прочитали: ${receipt.readCount} · Доставлено: ${receipt.deliveredCount}`
      : `Доставлено: ${receipt.deliveredCount}`;
  }
  return { sent: "Отправлено", delivered: "Доставлено", read: "Прочитано" }[receipt.status];
}

/** Per-conversation acknowledgements; only successful requests are deduplicated. */
export class ChatReceiptQueue {
  private received = new Set<string>();
  private seen = new Set<string>();
  private delivered = new Set<string>();
  private read = new Set<string>();
  private sending = false;

  receive(ids: string[]) {
    this.received = new Set(ids);
    this.seen = new Set([...this.seen].filter((id) => this.received.has(id)));
  }

  observe(ids: string[], active: boolean) {
    if (active) ids.filter((id) => this.received.has(id)).forEach((id) => this.seen.add(id));
  }

  async flush(send: (ids: string[], status: "delivered" | "read") => Promise<unknown>) {
    if (this.sending) return;
    this.sending = true;
    try {
      for (const status of ["read", "delivered"] as const) {
        const pending = [...(status === "read" ? this.seen : this.received)]
          .filter((id) => !(status === "read" ? this.read : this.delivered).has(id));
        for (let offset = 0; offset < pending.length; offset += 200) {
          const ids = pending.slice(offset, offset + 200).filter((id) => this.received.has(id));
          if (ids.length === 0) continue;
          await send(ids, status);
          ids.forEach((id) => {
            this.delivered.add(id);
            if (status === "read") this.read.add(id);
          });
        }
      }
    } finally {
      this.sending = false;
    }
  }
}
