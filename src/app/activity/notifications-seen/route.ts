import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { prisma } from "@/lib/prisma";

export async function POST() {
  try {
    const user = await requireSessionUser();

    await prisma.user.update({
      where: { id: user.id },
      data: {
        lastNotificationsSeenAt: new Date()
      }
    });

    return ok({ success: true });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
