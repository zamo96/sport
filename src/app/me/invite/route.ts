import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { buildInviteUrl, getInviteSummary } from "@/lib/invites";

export async function GET() {
  try {
    const user = await requireSessionUser();
    const summary = await getInviteSummary(user.id);
    const origin = process.env.NEXT_PUBLIC_APP_URL?.replace(/\/$/, "") || "https://sportsearch.shop";

    return ok({
      invite: {
        ...summary,
        url: buildInviteUrl(summary.code, origin)
      }
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
