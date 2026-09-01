import type { Prisma } from "@prisma/client";

import { prisma } from "@/lib/prisma";

export const USER_EVENT_TYPES = [
  "app_open",
  "onboarding_step",
  "discover_view",
  "swipe",
  "search_created",
  "search_response",
  "match_created",
  "push_sent",
  "push_opened",
  "push_converted"
] as const;

export type UserEventType = (typeof USER_EVENT_TYPES)[number];

/**
 * Типы, которые клиент имеет право прислать сам. Всё остальное (push_sent,
 * push_converted, swipe, match_created) пишется только сервером, иначе метрики
 * можно подделать с устройства.
 */
export const CLIENT_REPORTABLE_EVENT_TYPES = [
  "app_open",
  "onboarding_step",
  "discover_view",
  "push_opened"
] as const satisfies readonly UserEventType[];

export type ClientReportableEventType = (typeof CLIENT_REPORTABLE_EVENT_TYPES)[number];

export type UserEventInput = {
  userId: string;
  type: UserEventType;
  entityType?: string | null;
  entityId?: string | null;
  context?: Prisma.InputJsonValue | null;
};

export function isClientReportableEventType(value: string): value is ClientReportableEventType {
  return (CLIENT_REPORTABLE_EVENT_TYPES as readonly string[]).includes(value);
}

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
