import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";

export default async function HomePage() {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref("/discover"));
  }

  if (!user.onboardingCompleted) {
    redirect("/onboarding");
  }

  redirect("/discover");
}
