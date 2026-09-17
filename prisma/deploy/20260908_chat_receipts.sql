-- Apply before deploying the server with message receipts. No historical
-- deliveries or reads are inferred. Safe to rerun after a Prisma db push.
CREATE TABLE IF NOT EXISTS "MessageReceipt" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "chatMessageId" TEXT,
  "gameSearchMessageId" TEXT,
  "deliveredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "readAt" TIMESTAMP(3),
  CONSTRAINT "MessageReceipt_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "MessageReceipt_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "MessageReceipt_chatMessageId_fkey" FOREIGN KEY ("chatMessageId") REFERENCES "ChatMessage"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "MessageReceipt_gameSearchMessageId_fkey" FOREIGN KEY ("gameSearchMessageId") REFERENCES "GameSearchMessage"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "MessageReceipt_chatMessageId_userId_key" ON "MessageReceipt"("chatMessageId", "userId");
CREATE UNIQUE INDEX IF NOT EXISTS "MessageReceipt_gameSearchMessageId_userId_key" ON "MessageReceipt"("gameSearchMessageId", "userId");
CREATE INDEX IF NOT EXISTS "MessageReceipt_userId_idx" ON "MessageReceipt"("userId");
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'MessageReceipt_one_message_check') THEN
    ALTER TABLE "MessageReceipt" ADD CONSTRAINT "MessageReceipt_one_message_check"
      CHECK (("chatMessageId" IS NOT NULL) <> ("gameSearchMessageId" IS NOT NULL));
  END IF;
END $$;
