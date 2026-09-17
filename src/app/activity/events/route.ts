import { requireSessionUser } from "@/lib/auth";
import { fail, getErrorMessage, ok } from "@/lib/http";
import { userEventsSchema } from "@/lib/validators";
import { markNotificationOpened } from "@/server/notification-campaigns";
import { touchUserActivity } from "@/server/user-activity";
import { recordUserEvents } from "@/server/user-events";

export async function POST(request: Request) {
  try {
    const user = await requireSessionUser();
    const maxBytes = 16 * 1024;
    if (Number(request.headers.get("content-length")) > maxBytes) return fail("Слишком большой пакет событий", 413);
    const reader = request.body?.getReader();
    if (!reader) return fail("Пустой пакет событий");
    const chunks: Uint8Array[] = [];
    let bytes = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) {
        await reader.cancel();
        return fail("Слишком большой пакет событий", 413);
      }
      chunks.push(value);
    }
    const payload = userEventsSchema.parse(JSON.parse(Buffer.concat(chunks).toString("utf8")));
    const now = new Date();

    await recordUserEvents(
      payload.events.map((event) => ({
        userId: user.id,
        type: event.type,
        entityType: event.entityType ?? (event.deliveryId ? "notification_delivery" : null),
        entityId: event.entityId ?? event.deliveryId ?? null,
        context: event.context
      }))
    );

    const openedDeliveryIds = Array.from(
      new Set(
        payload.events
          .filter((event) => event.type === "push_opened")
          .map((event) => event.deliveryId)
          .filter((deliveryId): deliveryId is string => Boolean(deliveryId))
      )
    );

    await Promise.all(
      openedDeliveryIds.map((deliveryId) => markNotificationOpened(user.id, deliveryId, now))
    );

    await touchUserActivity(user.id);

    return ok({ success: true, accepted: payload.events.length });
  } catch (error) {
    if (getErrorMessage(error) === "UNAUTHORIZED") {
      return fail("Требуется авторизация", 401);
    }

    return fail(getErrorMessage(error));
  }
}
