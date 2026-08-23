-- Additive production rollout for player and club moderation.
-- Safe to run more than once. Take a database backup before applying.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'AccountStatus') THEN
    CREATE TYPE "AccountStatus" AS ENUM ('active', 'deactivated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'AdminAuditAction') THEN
    CREATE TYPE "AdminAuditAction" AS ENUM ('PROFILE_UPDATED', 'ACCOUNT_DEACTIVATED', 'ACCOUNT_REACTIVATED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'AdminCourtAuditAction') THEN
    CREATE TYPE "AdminCourtAuditAction" AS ENUM ('PROFILE_UPDATED', 'STATUS_CHANGED');
  END IF;
END $$;

ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS "accountStatus" "AccountStatus" NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS "deactivatedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "deactivationReason" TEXT;

ALTER TABLE "Court"
  ADD COLUMN IF NOT EXISTS "manualOverrideFields" JSONB,
  ADD COLUMN IF NOT EXISTS "manualStatusOverride" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "moderatedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "moderatedByEmail" TEXT;

CREATE TABLE IF NOT EXISTS "AdminAuditLog" (
  "id" TEXT NOT NULL,
  "actorUserId" TEXT NOT NULL,
  "actorEmail" TEXT NOT NULL,
  "targetUserId" TEXT NOT NULL,
  "targetEmail" TEXT NOT NULL,
  "action" "AdminAuditAction" NOT NULL,
  "reason" TEXT,
  "before" JSONB,
  "after" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminAuditLog_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "AdminCourtAuditLog" (
  "id" TEXT NOT NULL,
  "actorUserId" TEXT NOT NULL,
  "actorEmail" TEXT NOT NULL,
  "courtId" TEXT NOT NULL,
  "courtName" TEXT NOT NULL,
  "action" "AdminCourtAuditAction" NOT NULL,
  "reason" TEXT,
  "before" JSONB,
  "after" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminCourtAuditLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "User_accountStatus_createdAt_idx" ON "User"("accountStatus", "createdAt");
CREATE INDEX IF NOT EXISTS "AdminAuditLog_targetUserId_createdAt_idx" ON "AdminAuditLog"("targetUserId", "createdAt");
CREATE INDEX IF NOT EXISTS "AdminAuditLog_actorUserId_createdAt_idx" ON "AdminAuditLog"("actorUserId", "createdAt");
CREATE INDEX IF NOT EXISTS "AdminCourtAuditLog_courtId_createdAt_idx" ON "AdminCourtAuditLog"("courtId", "createdAt");
CREATE INDEX IF NOT EXISTS "AdminCourtAuditLog_actorUserId_createdAt_idx" ON "AdminCourtAuditLog"("actorUserId", "createdAt");
CREATE INDEX IF NOT EXISTS "AdminCourtAuditLog_action_createdAt_idx" ON "AdminCourtAuditLog"("action", "createdAt");

COMMIT;
