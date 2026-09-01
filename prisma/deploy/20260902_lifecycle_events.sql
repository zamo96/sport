BEGIN;

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "timezone" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "notificationDigest" BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS "UserEvent" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "entityType" TEXT,
  "entityId" TEXT,
  "context" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "UserEvent_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "NotificationDelivery" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "campaignKey" TEXT NOT NULL,
  "dedupeKey" TEXT NOT NULL,
  "variant" TEXT NOT NULL DEFAULT 'treatment',
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "href" TEXT NOT NULL,
  "context" JSONB,
  "sentAt" TIMESTAMP(3),
  "openedAt" TIMESTAMP(3),
  "convertedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "NotificationDelivery_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "UserEvent_userId_type_createdAt_idx" ON "UserEvent"("userId", "type", "createdAt");
CREATE INDEX IF NOT EXISTS "UserEvent_type_createdAt_idx" ON "UserEvent"("type", "createdAt");
CREATE INDEX IF NOT EXISTS "UserEvent_createdAt_idx" ON "UserEvent"("createdAt");

CREATE UNIQUE INDEX IF NOT EXISTS "NotificationDelivery_dedupeKey_key" ON "NotificationDelivery"("dedupeKey");
CREATE INDEX IF NOT EXISTS "NotificationDelivery_userId_campaignKey_createdAt_idx" ON "NotificationDelivery"("userId", "campaignKey", "createdAt");
CREATE INDEX IF NOT EXISTS "NotificationDelivery_campaignKey_createdAt_idx" ON "NotificationDelivery"("campaignKey", "createdAt");
CREATE INDEX IF NOT EXISTS "NotificationDelivery_userId_createdAt_idx" ON "NotificationDelivery"("userId", "createdAt");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'UserEvent_userId_fkey') THEN
    ALTER TABLE "UserEvent" ADD CONSTRAINT "UserEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'NotificationDelivery_userId_fkey') THEN
    ALTER TABLE "NotificationDelivery" ADD CONSTRAINT "NotificationDelivery_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;

COMMIT;
