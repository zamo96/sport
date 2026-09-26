-- Sign-in for users in Russia by phone (SMS code) or VK ID (149-FZ art. 8 part 10).
-- Apply before deploying the server that reads these columns. Safe to rerun.
-- Email becomes optional: accounts created by phone or VK ID have none.
BEGIN;

ALTER TABLE "User" ALTER COLUMN "email" DROP NOT NULL;

ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS "phone" TEXT,
  ADD COLUMN IF NOT EXISTS "phoneVerifiedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "vkSubject" TEXT,
  ADD COLUMN IF NOT EXISTS "signupCountry" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "User_phone_key" ON "User"("phone");
CREATE UNIQUE INDEX IF NOT EXISTS "User_vkSubject_key" ON "User"("vkSubject");

CREATE TABLE IF NOT EXISTS "PhoneAuthCode" (
  "id" TEXT NOT NULL,
  "phone" TEXT NOT NULL,
  "codeHash" TEXT NOT NULL,
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "consumedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PhoneAuthCode_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "PhoneAuthCode_phone_createdAt_idx" ON "PhoneAuthCode"("phone", "createdAt");

COMMIT;
