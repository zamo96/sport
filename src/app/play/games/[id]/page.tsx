import Link from "next/link";
import { redirect } from "next/navigation";

import { getSessionUser } from "@/lib/auth";
import { PageShell } from "@/components/layout/page-shell";
import { GameRequestChatRoom } from "@/components/chat/game-request-chat-room";
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
        subtitle="Здесь собраны детали игры и отдельный чат именно по этой договоренности. Общий чат мэтча остаётся отдельным."
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
          <Button fullWidth variant="ghost">Открыть общий чат мэтча</Button>
        </Link>
        <GameRequestChatRoom
          gameRequestId={gameRequest.id}
          currentUserId={user.id}
          otherUser={{
            name: otherUser.name,
            avatarUrl: otherUser.avatarUrl
          }}
          initialMessages={gameRequest.messages.map((message) => ({
            ...message,
            createdAt: message.createdAt.toISOString()
          }))}
        />
      </div>
    </PageShell>
  );
}
