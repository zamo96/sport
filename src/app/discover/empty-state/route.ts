import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { buildInviteUrl, getInviteSummary } from "@/lib/invites";
import { getEmptyDeckClubSections } from "@/server/app-data";
import { serializeCourt } from "@/server/serializers";

export const dynamic = "force-dynamic";

/** Всё, что показывает экран без карточек игроков: клубы по видам спорта и приглашение. */
export async function GET() {
  try {
    const user = await requireSessionUser();
    const [sections, invite] = await Promise.all([
      getEmptyDeckClubSections(user.id),
      getInviteSummary(user.id)
    ]);
    const origin = process.env.NEXT_PUBLIC_APP_URL?.replace(/\/$/, "") || "https://sportsearch.shop";

    return ok({
      sections: sections.map((section) => ({
        sport: section.sport,
        total: section.total,
        courts: section.courts.map((court) => {
          const serialized = serializeCourt(court);
          return {
            id: court.id,
            name: court.name,
            distanceLabel: serialized.distanceLabel,
            activeSearchesCount: serialized.activeSearchesCount,
            memberCount: serialized.memberCount,
            // Лица тех, кто ищет игру именно здесь: убедительнее любой цифры.
            searchers: serialized.activeSearchPreviewUsers.slice(0, 3).map((player) => ({
              id: player.id,
              name: player.name,
              avatarUrl: player.avatarUrl
            }))
          };
        })
      })),
      invite: {
        url: buildInviteUrl(invite.code, origin),
        visits: invite.visits,
        joined: invite.joined
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
