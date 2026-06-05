import { redirect } from "next/navigation";
import type { Sport } from "@prisma/client";

import { getSessionUser } from "@/lib/auth";
import { buildGuestAuthHref } from "@/lib/guest-draft";
import { prisma } from "@/lib/prisma";
import { PageShell } from "@/components/layout/page-shell";
import { SectionTitle } from "@/components/ui/section-title";
import { GameSearchLobby } from "@/components/chat/game-search-lobby";
import { getCourtsForUser } from "@/server/app-data";

export default async function SearchLobbyPage({ params }: { params: { id: string } }) {
  const user = await getSessionUser();

  if (!user) {
    redirect(buildGuestAuthHref(`/play/searches/${params.id}`));
  }

  const [gameSearch, courts] = await Promise.all([
    prisma.gameSearch.findFirst({
      where: {
        id: params.id,
        OR: [
          { createdByUserId: user.id },
          {
            responses: {
              some: {
                responderUserId: user.id,
                status: "approved"
              }
            }
          }
        ]
      },
      include: {
        preferredCourt: true,
        scheduledCourt: true,
        regularPair: true,
        responses: {
          include: {
            responderUser: true
          },
          orderBy: [{ status: "asc" }, { createdAt: "asc" }]
        },
        messages: {
          include: {
            senderUser: true
          },
          orderBy: {
            createdAt: "asc"
          }
        }
      }
    }),
    getCourtsForUser(user.id)
  ]);

  if (!gameSearch) {
    redirect("/play/searches");
  }

  return (
    <PageShell>
      <SectionTitle
        eyebrow="Поиск игры"
        title="Состав и общий чат"
        subtitle="Здесь видны все откликнувшиеся, обсуждение по набору и действие организатора: закрыть поиск и назначить игру."
      />
      <GameSearchLobby
        currentUserId={user.id}
        search={{
          id: gameSearch.id,
          createdByUserId: gameSearch.createdByUserId,
          searchType: gameSearch.searchType,
          status: gameSearch.status,
          isActive: gameSearch.isActive,
          sport: gameSearch.sport,
          format: gameSearch.format,
          preferredDays: gameSearch.preferredDays,
          preferredTimeRanges: gameSearch.preferredTimeRanges,
          hotStartsAt: gameSearch.hotStartsAt?.toISOString() ?? null,
          durationMinutes: gameSearch.durationMinutes ?? null,
          playersNeeded: gameSearch.playersNeeded,
          comment: gameSearch.comment,
          scheduledAt: gameSearch.scheduledAt?.toISOString() ?? null,
          scheduledDurationMinutes: gameSearch.scheduledDurationMinutes ?? null,
          scheduledCourt: gameSearch.scheduledCourt
            ? { id: gameSearch.scheduledCourt.id, name: gameSearch.scheduledCourt.name }
            : null,
          regularPairMatchId: gameSearch.regularPair?.matchId ?? null,
          preferredCourt: gameSearch.preferredCourt
            ? { id: gameSearch.preferredCourt.id, name: gameSearch.preferredCourt.name }
            : null,
          responses: gameSearch.responses.map((response) => ({
            id: response.id,
            status: response.status,
            responderUserId: response.responderUserId,
            responderUser: {
              id: response.responderUser.id,
              name: response.responderUser.name,
              avatarUrl: response.responderUser.avatarUrl
            }
          })),
          messages: gameSearch.messages.map((message) => ({
            id: message.id,
            senderUserId: message.senderUserId,
            text: message.text,
            createdAt: message.createdAt.toISOString(),
            senderUser: {
              name: message.senderUser.name,
              avatarUrl: message.senderUser.avatarUrl
            }
          }))
        }}
        courts={courts
          .filter((court) => {
            const sports = Array.isArray(court.supportedSports)
              ? court.supportedSports.filter((sport): sport is Sport => typeof sport === "string")
              : [];
            return sports.length === 0 || sports.includes(gameSearch.sport);
          })
          .map((court) => ({
            id: court.id,
            name: court.name,
            address: court.address,
            district: court.district,
            nearestMetroName: court.nearestMetro?.name ?? null
          }))}
      />
    </PageShell>
  );
}
