-- Additive: old photo-only clients continue to read/write photos unchanged.
ALTER TABLE "PersonalActivity"
ADD COLUMN IF NOT EXISTS "videoUrls" JSONB NOT NULL DEFAULT '[]'::jsonb;
