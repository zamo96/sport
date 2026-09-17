import { NextRequest } from "next/server";
import { getSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { buildInviteUrl, getInviteSummary } from "@/lib/invites";
import { getEmptyDeckClubSections } from "@/server/app-data";
import { serializeCourt } from "@/server/serializers";
import { courtsQuerySchema } from "@/lib/validators";

export const dynamic = "force-dynamic";

/** Всё, что показывает экран без карточек игроков: клубы по видам спорта и приглашение. */
export async function GET(request: NextRequest) {
  try {
    const user = await getSessionUser();
    const query = Object.fromEntries(request.nextUrl.searchParams);
    const sports = query.sport ? query.sport.split(",").map((sport) => courtsQuerySchema.shape.sport.parse(sport.trim())!) : undefined;
    const filters = { ...courtsQuerySchema.parse({ ...query, sport: undefined }), sport: sports };
    const [sections, invite] = await Promise.all([
      getEmptyDeckClubSections(user?.id, filters),
      user ? getInviteSummary(user.id) : null
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
            city: court.city,
            nearby: serialized.nearby,
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
      invite: invite ? {
        url: buildInviteUrl(invite.code, origin),
        visits: invite.visits,
        joined: invite.joined
      } : null
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
