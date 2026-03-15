import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { AuthFlow } from "@/components/forms/auth-flow";
import { PageShell } from "@/components/layout/page-shell";

export default async function AuthPage() {
  const user = await getSessionUser();

  if (user) {
    redirect(user.onboardingCompleted ? "/discover" : "/onboarding");
  }

  return (
    <PageShell withNav={false}>
      <div className="pt-4">
        <AuthFlow />
      </div>
    </PageShell>
  );
}

