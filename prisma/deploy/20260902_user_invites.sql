BEGIN;

-- Личные ссылки-приглашения: код на игроке, отметка «кто привёл» и счётчик
-- переходов. Без счётчика переходов конверсию приглашения не посчитать —
-- регистрация без знаменателя ничего не говорит.
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "inviteCode" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "invitedByUserId" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "invitedAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "inviteVisits" INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS "User_inviteCode_key" ON "User"("inviteCode");
CREATE INDEX IF NOT EXISTS "User_invitedByUserId_idx" ON "User"("invitedByUserId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'User_invitedByUserId_fkey' AND table_name = 'User'
  ) THEN
    ALTER TABLE "User"
      ADD CONSTRAINT "User_invitedByUserId_fkey"
      FOREIGN KEY ("invitedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END
$$;

COMMIT;
