BEGIN;

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "localeOverride" TEXT;

ALTER TABLE "User" DROP CONSTRAINT IF EXISTS "User_localeOverride_check";
ALTER TABLE "User" ADD CONSTRAINT "User_localeOverride_check"
  CHECK ("localeOverride" IS NULL OR "localeOverride" IN ('en', 'ru'));

COMMIT;
