import { redirect } from "next/navigation";
import { type Sport } from "@prisma/client";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { GameRequestForm } from "@/components/forms/game-request-form";
import { SectionTitle } from "@/components/ui/section-title";
import { getCourtsForUser, getMatchesForUser } from "@/server/app-data";

export default async function NewProposalPage({
  searchParams
}: {
  searchParams: { matchId?: string; courtId?: string };
}) {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  const [matches, courts] = await Promise.all([getMatchesForUser(user.id), getCourtsForUser(user.id)]);
  const availableSports = Array.isArray(user.preferredSports)
    ? user.preferredSports.filter((sport): sport is string => typeof sport === "string")
    : ["tennis"];

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Предложение"
        title="Отправь готовое предложение на игру."
        subtitle="Один экран: вид спорта, игрок, корт, время и формат. Комментарий оставляй коротким."
      />
      <GameRequestForm
        availableSports={availableSports as Sport[]}
        matches={matches.map((match) => ({
          id: match.id,
          otherUserName: match.user1Id === user.id ? match.user2.name ?? "Игрок" : match.user1.name ?? "Игрок"
        }))}
        courts={courts.map((court) => ({
          id: court.id,
          name: court.name,
          address: court.address
        }))}
        defaultMatchId={searchParams.matchId}
        defaultCourtId={searchParams.courtId}
      />
    </PageShell>
  );
}
