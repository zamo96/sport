-- Apply after 20260906-player-map-visibility.sql, before deploying default-on clients.
-- This one-time product rollout includes all existing accounts. Later opt-outs survive reapplication.
BEGIN;

SELECT pg_advisory_xact_lock(20260906, 1);

CREATE TABLE IF NOT EXISTS "DeploymentMigration" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "appliedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "showOnMap" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "User" ALTER COLUMN "showOnMap" SET DEFAULT true;

WITH first_application AS (
  INSERT INTO "DeploymentMigration" ("id")
  VALUES ('20260906-player-map-default-on-v1')
  ON CONFLICT ("id") DO NOTHING
  RETURNING "id"
)
UPDATE "User" SET "showOnMap" = true
WHERE EXISTS (SELECT 1 FROM first_application);

COMMIT;
