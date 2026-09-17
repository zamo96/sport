-- Apply before deploying the server that registers Android devices. Adds the
-- enum value the FCM route writes; existing iOS rows are untouched. Safe to
-- rerun and safe to apply ahead of the deploy - nothing writes "android" until
-- the new route ships.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'PushPlatform' AND e.enumlabel = 'android'
  ) THEN
    ALTER TYPE "PushPlatform" ADD VALUE 'android';
  END IF;
END $$;
