import { describe, expect, it, vi } from "vitest";

import { ChatReceiptQueue, mergeChatMessages, receiptLabel, type MessageReceipt } from "@/lib/chat-receipts-client";

const sent: MessageReceipt = { status: "sent", deliveredCount: 0, readCount: 0 };
const read: MessageReceipt = { status: "read", deliveredCount: 3, readCount: 2 };

describe("chat receipt client", () => {
  it("does not regress receipts or lose a just-sent message when an old fetch arrives", () => {
    const first = { id: "1", createdAt: "2026-09-08T00:00:00Z", receipt: read };
    const second = { id: "2", createdAt: "2026-09-08T01:00:00Z", receipt: sent };
    expect(mergeChatMessages([first, second], [{ ...first, receipt: sent }])).toEqual([first, second]);
    expect(mergeChatMessages([first], [{ id: first.id, createdAt: first.createdAt }])[0].receipt).toEqual(read);
  });

  it("removes incoming IDs omitted by an authoritative access-filtered snapshot but preserves a just-sent outgoing message", () => {
    const blocked = { id: "blocked", senderUserId: "blocked-sender", createdAt: "1", receipt: sent };
    const visible = { id: "visible", senderUserId: "peer", createdAt: "2", receipt: sent };
    const outgoing = { id: "new-send", senderUserId: "me", createdAt: "3", receipt: sent };
    expect(mergeChatMessages([blocked, visible, outgoing], [visible], { currentUserId: "me" })).toEqual([visible, outgoing]);
    expect(mergeChatMessages([visible], [outgoing])).toEqual([visible, outgoing]);
  });

  it("drops removed recipient IDs from retries so a newly blocked sender cannot poison valid batches", async () => {
    const queue = new ChatReceiptQueue();
    queue.receive(["blocked", "valid"]);
    queue.observe(["blocked", "valid"], true);
    const send = vi.fn().mockRejectedValueOnce(new Error("forbidden")).mockResolvedValue({ success: true });
    await expect(queue.flush(send)).rejects.toThrow("forbidden");
    queue.receive(["valid"]);
    await queue.flush(send);
    expect(send.mock.calls).toEqual([[["blocked", "valid"], "read"], [["valid"], "read"]]);
  });

  it("deduplicates a message returned both by POST and polling", () => {
    const message = { id: "1", createdAt: "2026-09-08T00:00:00Z", receipt: sent };
    expect(mergeChatMessages([message], [message])).toEqual([message]);
  });

  it("distinguishes group counts and hides unconfirmed legacy status", () => {
    expect(receiptLabel(undefined)).toBe("");
    expect(receiptLabel(sent)).toBe("Отправлено");
    expect(receiptLabel(read)).toBe("Прочитано");
    expect(receiptLabel(read, true)).toBe("Прочитали: 2 · Доставлено: 3");
  });

  it("acknowledges only fetched IDs and never marks a background observation as read", async () => {
    const queue = new ChatReceiptQueue();
    const send = vi.fn().mockResolvedValue({ success: true });
    queue.receive(["incoming"]);
    queue.observe(["incoming"], false);
    queue.observe(["not-fetched"], true);
    await queue.flush(send);
    expect(send.mock.calls).toEqual([[["incoming"], "delivered"]]);
  });

  it("read implies delivery and successful acknowledgements do not loop after refetch", async () => {
    const queue = new ChatReceiptQueue();
    const send = vi.fn().mockResolvedValue({ success: true });
    queue.receive(["incoming"]);
    queue.observe(["incoming"], true);
    await queue.flush(send);
    queue.receive(["incoming"]);
    queue.observe(["incoming"], true);
    await queue.flush(send);
    expect(send.mock.calls).toEqual([[["incoming"], "read"]]);
  });

  it("retries failed requests without dropping pending reads", async () => {
    const queue = new ChatReceiptQueue();
    const send = vi.fn().mockRejectedValueOnce(new Error("offline")).mockResolvedValue({ success: true });
    queue.receive(["incoming"]);
    queue.observe(["incoming"], true);
    await expect(queue.flush(send)).rejects.toThrow("offline");
    await queue.flush(send);
    await queue.flush(send);
    expect(send.mock.calls).toEqual([[["incoming"], "read"], [["incoming"], "read"]]);
  });

  it("sends bounded batches and does not re-send successful batches after a later failure", async () => {
    const queue = new ChatReceiptQueue();
    queue.receive(Array.from({ length: 401 }, (_, index) => `m${index}`));
    const send = vi.fn().mockResolvedValueOnce({ success: true }).mockRejectedValueOnce(new Error("offline")).mockResolvedValue({ success: true });
    await expect(queue.flush(send)).rejects.toThrow("offline");
    await queue.flush(send);
    expect(send.mock.calls.map(([ids]) => ids.length)).toEqual([200, 200, 200, 1]);
    expect(send.mock.calls[2][0][0]).toBe("m200");
  });

  it("serializes concurrent flushing and upgrades delivered to read", async () => {
    const queue = new ChatReceiptQueue();
    let finish!: () => void;
    const send = vi.fn().mockImplementationOnce(() => new Promise<void>((resolve) => { finish = resolve; })).mockResolvedValue({ success: true });
    queue.receive(["incoming"]);
    const first = queue.flush(send);
    await queue.flush(send);
    expect(send).toHaveBeenCalledTimes(1);
    queue.observe(["incoming"], true);
    finish();
    await first;
    await queue.flush(send);
    expect(send.mock.calls).toEqual([[["incoming"], "delivered"], [["incoming"], "read"]]);
  });
});
