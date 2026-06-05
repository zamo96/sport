import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { getNotificationsForUser } from "@/server/app-data";
import { touchUserActivity } from "@/server/user-activity";

export async function GET() {
  try {
    const user = await requireSessionUser();
    await touchUserActivity(user.id);
    const notifications = await getNotificationsForUser(user.id);

    return ok({
      notifications: notifications.map((notification) => ({
        ...notification,
        createdAt: notification.createdAt.toISOString()
      }))
    });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
