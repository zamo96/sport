-- Separate consents: profile visibility (152-FZ art. 10.1) and optional analytics.
-- Apply before deploying the server that reads these columns. Safe to rerun.
-- Existing accounts get profileVisibility = 'legacy': they stay visible as before
-- until the owner answers the consent screen. Analytics consent starts as false
-- for everyone, so event logging stops until a person opts in.
BEGIN;

DO $$ BEGIN
  CREATE TYPE "ProfileVisibility" AS ENUM ('legacy', 'pending', 'visible', 'hidden');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ConsentKind" AS ENUM ('profile_visibility', 'analytics');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS "profileVisibility" "ProfileVisibility" NOT NULL DEFAULT 'legacy',
  ADD COLUMN IF NOT EXISTS "profileVisibleToGuests" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "profileShowsBio" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "profileShowsPhotos" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "profileShowsVideos" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "profileShowsSearches" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "analyticsConsent" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "consentFullName" TEXT,
  ADD COLUMN IF NOT EXISTS "agreementVersion" TEXT;

-- Latest accepted terms per user; versions are ISO dates, so text order is chronological.
UPDATE "User" u
SET "agreementVersion" = latest.version
FROM (
  SELECT "userId", MAX("agreementVersion") AS version
  FROM "UserAgreementAcceptance"
  WHERE "agreementKey" = 'user_agreement'
  GROUP BY "userId"
) latest
WHERE latest."userId" = u."id" AND u."agreementVersion" IS NULL;

CREATE TABLE IF NOT EXISTS "UserConsent" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "kind" "ConsentKind" NOT NULL,
  "version" TEXT NOT NULL,
  "granted" BOOLEAN NOT NULL,
  "scope" JSONB,
  "fullName" TEXT,
  "source" TEXT NOT NULL,
  "ipAddress" TEXT,
  "userAgent" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "UserConsent_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "UserConsent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "UserConsent_userId_kind_createdAt_idx" ON "UserConsent"("userId", "kind", "createdAt");

COMMIT;
