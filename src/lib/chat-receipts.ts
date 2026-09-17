export type ChatReceiptSummary = {
  status: "sent" | "delivered" | "read";
  deliveredCount: number;
  readCount: number;
};

// Receipt rows are unique per message and recipient. A read row always also
// confirms delivery; group counts describe confirmed people, never "everyone".
export function summarizeChatReceipts(receipts: ReadonlyArray<{ readAt: Date | string | null }>): ChatReceiptSummary {
  const deliveredCount = receipts.length;
  const readCount = receipts.filter((receipt) => receipt.readAt !== null).length;
  return {
    status: readCount > 0 ? "read" : deliveredCount > 0 ? "delivered" : "sent",
    deliveredCount,
    readCount
  };
}
