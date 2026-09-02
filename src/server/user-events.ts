import type { Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";
import type { UserEventType } from "@/lib/user-events";

export type UserEventInput = {
  userId: string;
  type: UserEventType;
  entityType?: string | null;
  entityId?: string | null;
  context?: Prisma.InputJsonValue | null;
};

function toCreateInput(event: UserEventInput) {
  return {
    userId: event.userId,
    type: event.type,
    entityType: event.entityType ?? null,
    entityId: event.entityId ?? null,
    context: event.context ?? undefined
  };
}

/**
 * Журнал событий — вспомогательная телеметрия: он никогда не должен ронять
 * пользовательский запрос, поэтому все ошибки только логируются.
 */
export async function recordUserEvent(event: UserEventInput) {
  try {
    await prisma.userEvent.create({ data: toCreateInput(event) });
  } catch (error) {
    console.warn("Failed to record user event", { type: event.type, userId: event.userId, error });
  }
}

export async function recordUserEvents(events: UserEventInput[]) {
  if (events.length === 0) {
    return;
  }

  try {
    await prisma.userEvent.createMany({ data: events.map(toCreateInput) });
  } catch (error) {
    console.warn("Failed to record user events", { count: events.length, error });
  }
}
