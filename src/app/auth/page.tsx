import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { AuthFlow } from "@/components/forms/auth-flow";
import { PageShell } from "@/components/layout/page-shell";

export default async function AuthPage() {
  const user = await getSessionUser();

  if (user) {
    redirect(user.onboardingCompleted ? "/discover" : "/onboarding");
  }

  const activePlayersCount = await prisma.user.count({
    where: {
      isVerified: true,
      onboardingCompleted: true,
      OR: [
        {
          isLookingForGame: true
        },
        {
          gameSearches: {
            some: {
              isActive: true
            }
          }
        }
      ]
    }
  });

  return (
    <PageShell withNav={false}>
      <div className="pt-4">
        <AuthFlow activePlayersCount={activePlayersCount} />
      </div>
    </PageShell>
  );
}
