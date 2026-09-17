-- Apply to the existing database before deploying the new application.
-- Existing and new accounts remain off the player map until they opt in.
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "showOnMap" BOOLEAN NOT NULL DEFAULT false;
