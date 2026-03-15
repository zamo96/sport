import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { ChatRoom } from "@/components/chat/chat-room";
import { SectionTitle } from "@/components/ui/section-title";
import { getMatchDetail } from "@/server/app-data";

export default async function MatchPage({ params }: { params: { id: string } }) {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  const match = await getMatchDetail(params.id, user.id);

  if (!match) {
    redirect("/inbox");
  }

  const otherUser = match.user1Id === user.id ? match.user2 : match.user1;

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Чат"
        title={otherUser.name ?? "Чат с игроком"}
        subtitle="Пиши коротко. Главное действие здесь — предложить игру с кортом и временем."
      />
      <ChatRoom
        matchId={match.id}
        currentUserId={user.id}
        otherUser={{
          name: otherUser.name,
          avatarUrl: otherUser.avatarUrl,
          tennisLevel: otherUser.tennisLevel,
          preferredSports: otherUser.preferredSports,
          sportLevels: otherUser.sportLevels
        }}
        initialMessages={match.messages.map((message) => ({
          ...message,
          createdAt: message.createdAt.toISOString()
        }))}
        gameRequests={match.gameRequests.map((request) => ({
          id: request.id,
          status: request.status,
          proposedDatetime: request.proposedDatetime.toISOString(),
          comment: request.comment,
          sport: request.sport,
          format: request.format,
          createdByUserId: request.createdByUserId,
          matchedUserId: request.matchedUserId,
          proposedCourt: {
            name: request.proposedCourt.name,
            address: request.proposedCourt.address
          }
        }))}
      />
    </PageShell>
  );
}
