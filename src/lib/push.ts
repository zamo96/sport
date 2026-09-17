import { deliverAPNSPush } from "@/lib/apns";
import { deliverFCMPush } from "@/lib/fcm";
import type { PushPayload } from "@/lib/push-payload";
import { prisma } from "@/lib/prisma";
import { publishRealtimeEvent } from "@/server/realtime";

export type { PushPayload };

/**
 * The single entry point for notifying a user: the realtime channel first, so
 * an open app reacts immediately, then every device transport. One failing
 * transport must not silence the other, so they are dispatched together and
 * each swallows its own errors.
 */
export async function sendPushToUser(payload: PushPayload) {
  const activeUser = await prisma.user.findFirst({
    where: {
      id: payload.userId,
      accountStatus: "active"
    },
    select: { id: true }
  });

  if (!activeUser) {
    console.warn("Push skipped: user account is not active", {
      userId: payload.userId,
      href: payload.href
    });
    return;
  }

  await publishRealtimeEvent(payload.userId, {
    type: "notification",
    title: payload.title,
    body: payload.body,
    href: payload.href,
    deliveryId: payload.deliveryId
  });

  await Promise.all([deliverAPNSPush(payload), deliverFCMPush(payload)]);
}
