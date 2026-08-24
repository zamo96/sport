BEGIN;

CREATE TYPE "ContentReportOrigin" AS ENUM ('report', 'block');
CREATE TYPE "ContentReportReason" AS ENUM ('abusive_behavior', 'harassment', 'hate_speech', 'sexual_content', 'violence', 'spam', 'impersonation', 'privacy', 'illegal_content', 'other');
CREATE TYPE "ContentReportType" AS ENUM ('profile', 'chat_message', 'game_search_message', 'game_search', 'game_search_response', 'game_request', 'game_report', 'personal_activity', 'other');
CREATE TYPE "ContentReportStatus" AS ENUM ('pending', 'actioned', 'dismissed');

CREATE TABLE "ContentReport" (
  "id" TEXT NOT NULL,
  "reporterUserId" TEXT,
  "reporterEmail" TEXT NOT NULL,
  "reporterName" TEXT,
  "reportedUserId" TEXT,
  "reportedEmail" TEXT NOT NULL,
  "reportedName" TEXT,
  "blockId" TEXT,
  "origin" "ContentReportOrigin" NOT NULL,
  "reason" "ContentReportReason" NOT NULL,
  "details" TEXT,
  "contentType" "ContentReportType" NOT NULL DEFAULT 'profile',
  "contextId" TEXT,
  "contextSnapshot" JSONB,
  "status" "ContentReportStatus" NOT NULL DEFAULT 'pending',
  "dueAt" TIMESTAMP(3) NOT NULL,
  "reviewedByUserId" TEXT,
  "reviewedByEmail" TEXT,
  "reviewedAt" TIMESTAMP(3),
  "resolutionNote" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ContentReport_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ContentReport_blockId_key" ON "ContentReport"("blockId");
CREATE INDEX "ContentReport_status_dueAt_idx" ON "ContentReport"("status", "dueAt");
CREATE INDEX "ContentReport_reportedUserId_createdAt_idx" ON "ContentReport"("reportedUserId", "createdAt");
CREATE INDEX "ContentReport_reporterUserId_createdAt_idx" ON "ContentReport"("reporterUserId", "createdAt");
CREATE INDEX "ContentReport_origin_createdAt_idx" ON "ContentReport"("origin", "createdAt");

ALTER TABLE "ContentReport" ADD CONSTRAINT "ContentReport_reporterUserId_fkey" FOREIGN KEY ("reporterUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ContentReport" ADD CONSTRAINT "ContentReport_reportedUserId_fkey" FOREIGN KEY ("reportedUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ContentReport" ADD CONSTRAINT "ContentReport_reviewedByUserId_fkey" FOREIGN KEY ("reviewedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ContentReport" ADD CONSTRAINT "ContentReport_blockId_fkey" FOREIGN KEY ("blockId") REFERENCES "Block"("id") ON DELETE SET NULL ON UPDATE CASCADE;

COMMIT;
