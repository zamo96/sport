import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { AuthFlow } from "@/components/forms/auth-flow";
import { PageShell } from "@/components/layout/page-shell";

export default async function AuthPage({
  searchParams
}: {
  searchParams?: { continue?: string; step?: string };
}) {
  const user = await getSessionUser();
  const continueHref = searchParams?.continue || "/discover";
  const initialStep = searchParams?.step === "email" ? "email" : "intro";

  if (user) {
    redirect(user.onboardingCompleted ? continueHref : "/onboarding");
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
      <div className="pt-1">
        <AuthFlow activePlayersCount={activePlayersCount} initialStep={initialStep} />
      </div>
    </PageShell>
  );
}
