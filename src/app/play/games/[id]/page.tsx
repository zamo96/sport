import Link from "next/link";
import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { ChatRoom } from "@/components/chat/chat-room";
import { GameRequestCard } from "@/components/chat/game-request-card";
import { Button } from "@/components/ui/button";
import { SectionTitle } from "@/components/ui/section-title";
import { getGameRequestDetail } from "@/server/app-data";

export default async function GameRequestDetailPage({ params }: { params: { id: string } }) {
  const user = await getSessionUser();

  if (!user) {
    redirect("/auth");
  }

  const gameRequest = await getGameRequestDetail(params.id, user.id);

  if (!gameRequest) {
    redirect("/inbox");
  }

  const match = gameRequest.match;
  const otherUser = match.user1Id === user.id ? match.user2 : match.user1;

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Игра"
        title="Просмотр договоренности"
        subtitle="Здесь собраны детали игры, итоговый статус и весь чат по этому мэтчу."
      />
      <div className="space-y-4">
        <GameRequestCard
          gameRequest={{
            id: gameRequest.id,
            status: gameRequest.status,
            outcome: gameRequest.outcome,
            outcomeUpdatedAt: gameRequest.outcomeUpdatedAt?.toISOString() ?? null,
            proposedDatetime: gameRequest.proposedDatetime.toISOString(),
            comment: gameRequest.comment,
            sport: gameRequest.sport,
            format: gameRequest.format,
            createdByUserId: gameRequest.createdByUserId,
            matchedUserId: gameRequest.matchedUserId,
            proposedCourt: {
              name: gameRequest.proposedCourt.name,
              address: gameRequest.proposedCourt.address
            }
          }}
          currentUserId={user.id}
        />
        <Link href={`/inbox/${match.id}`} className="block">
          <Button fullWidth variant="ghost">Открыть чат мэтча отдельно</Button>
        </Link>
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
            outcome: request.outcome,
            outcomeUpdatedAt: request.outcomeUpdatedAt?.toISOString() ?? null,
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
          showLatestRequest={false}
        />
      </div>
    </PageShell>
  );
}
