-- Additive: clients that don't know the column keep the photos-then-videos order.
ALTER TABLE "User"
ADD COLUMN IF NOT EXISTS "profileMediaOrder" JSONB;
