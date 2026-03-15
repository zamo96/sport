import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";

export default async function HomePage() {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  if (!user.onboardingCompleted) {
    redirect("/onboarding");
  }

  redirect("/discover");
}

