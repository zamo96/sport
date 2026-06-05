import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { serializeCourt, serializeUserPreview } from "@/server/serializers";
import { getRegularPairForUser } from "@/server/app-data";

export async function GET(
  _request: Request,
  { params }: { params: { id: string } }
) {
  try {
    const user = await requireSessionUser();
    const regularPair = await getRegularPairForUser(user.id, params.id);

    if (!regularPair) {
      return fail("Регулярная пара не найдена", 404);
    }

    const partnerUser =
      regularPair.createdByUserId === user.id ? regularPair.partnerUser : regularPair.createdByUser;

    return ok({
      regularPair: {
        id: regularPair.id,
        matchId: regularPair.matchId,
        preferredDays: regularPair.preferredDays,
        preferredTimeRanges: regularPair.preferredTimeRanges,
        comment: regularPair.comment,
        preferredCourt: regularPair.preferredCourt ? serializeCourt(regularPair.preferredCourt) : null,
        partnerUser: serializeUserPreview(partnerUser),
        occurrences: regularPair.occurrences.map((occurrence) => ({
          ...occurrence,
          scheduledAt: occurrence.scheduledAt.toISOString(),
          scheduleAnchor: occurrence.scheduleAnchor?.toISOString() ?? null,
          createdAt: occurrence.createdAt.toISOString(),
          updatedAt: occurrence.updatedAt.toISOString(),
          proposedCourt: occurrence.proposedCourt ? serializeCourt(occurrence.proposedCourt) : null,
          confirmations: occurrence.confirmations.map((confirmation) => ({
            ...confirmation,
            respondedAt: confirmation.respondedAt?.toISOString() ?? null,
            createdAt: confirmation.createdAt.toISOString(),
            updatedAt: confirmation.updatedAt.toISOString(),
            user: serializeUserPreview(confirmation.user)
          }))
        }))
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
