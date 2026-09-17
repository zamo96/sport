import { createHash } from "node:crypto";
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

/** First milestone per participant/entity; deterministic primary keys also dedupe concurrent retries. */
export async function recordUserEventsOnce(events: UserEventInput[]) {
  if (!events.length) return;
  try {
    await prisma.userEvent.createMany({
      data: events.map((event) => ({
        ...toCreateInput(event),
        id: `evt_${createHash("sha256").update(JSON.stringify([event.userId, event.type, event.entityType, event.entityId])).digest("hex")}`
      })),
      skipDuplicates: true
    });
  } catch (error) {
    console.warn("Failed to record user milestones", { count: events.length, error });
  }
}

/** Call only after a committed transition. Reads never include declined/pending invitees. */
export async function recordGameRequestMilestones(
  requestIds: string[],
  type: "request_accepted" | "game_played",
  source: "proposal" | "search" | "regular" | "outcome" | "report"
) {
  if (!requestIds.length) return;
  try {
    const requests = await prisma.gameRequest.findMany({
      where: { id: { in: requestIds }, status: "accepted", ...(type === "game_played" ? { outcome: "played", NOT: { report: { status: "disputed" } } } : {}) },
      select: { id: true, sharedRootId: true, createdByUserId: true, matchedUserId: true }
    });
    const events: UserEventInput[] = [];
    for (const request of requests) {
      const rootId = request.sharedRootId ?? request.id;
      // A report/outcome on a group game describes its accepted roster only.
      const participants = type === "game_played" && request.id === rootId
        ? await prisma.gameRequest.findMany({
            where: {
              OR: [{ id: rootId }, { sharedRootId: rootId }],
              status: "accepted",
              AND: [{ OR: [{ outcome: null }, { outcome: "played" }] }, { NOT: { report: { status: "disputed" } } }]
            },
            select: { createdByUserId: true, matchedUserId: true }
          })
        : [request];
      for (const userId of new Set(participants.flatMap((item) => [item.createdByUserId, item.matchedUserId]))) {
        events.push({ userId, type, entityType: "game_request", entityId: rootId, context: { source } });
      }
    }
    await recordUserEventsOnce(events);
  } catch (error) {
    console.warn("Failed to record game milestones", { type, error });
  }
}
