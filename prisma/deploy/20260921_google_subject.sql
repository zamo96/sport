-- Apply before deploying the server with /auth/google. Adds the column the
-- Google sign-in links accounts by; existing users keep NULL until they first
-- sign in with Google. Safe to rerun after a Prisma db push.
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "googleSubject" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "User_googleSubject_key" ON "User"("googleSubject");
