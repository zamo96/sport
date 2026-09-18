import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/prisma", () => ({ prisma: {} }));

import { syncRegularPairOccurrences } from "@/server/regular-occurrences";

type Confirmation = {
  occurrenceId: string;
  userId: string;
  status: "pending" | "confirmed" | "declined";
  respondedAt: Date | null;
};
type Occurrence = {
  id: string;
  scheduledAt: Date;
  scheduleAnchor: Date;
  status: string;
  durationMinutes: number;
  proposedCourtId: string | null;
  sport: string;
  format: string;
};

// The in-memory store models unique confirmation keys and insert-on-conflict
// semantics. Actual PostgreSQL concurrency requires a separate integration run.
function createStore() {
  const occurrences = new Map<string, Occurrence>();
  const confirmations = new Map<string, Confirmation>();
  const pair = {
    id: "pair-1",
    createdByUserId: "organizer",
    partnerUserId: "partner",
    preferredDays: ["friday"],
    preferredTimeRanges: ["evening"],
    preferredCourtId: null,
    sport: "tennis",
    format: "singles"
  };
  const db = {
    regularPair: {
      findUnique: vi.fn(async () => ({
        ...pair,
        occurrences: [...occurrences.values()].map((occurrence) => ({
          ...occurrence,
          gameRequest: null,
          confirmations: [...confirmations.values()]
            .filter((confirmation) => confirmation.occurrenceId === occurrence.id)
            .map((confirmation) => ({ ...confirmation }))
        }))
      }))
    },
    regularPairOccurrence: {
      upsert: vi.fn(async ({ create }: { create: Omit<Occurrence, "id"> }) => {
        const key = create.scheduledAt.toISOString();
        let occurrence = occurrences.get(key);
        if (!occurrence) {
          occurrence = { ...create, id: `occurrence-${occurrences.size + 1}` };
          occurrences.set(key, occurrence);
        }
        return { ...occurrence };
      }),
      update: vi.fn(async ({ where, data }: { where: { id: string }; data: Partial<Occurrence> }) => {
        const occurrence = [...occurrences.values()].find((item) => item.id === where.id)!;
        Object.assign(occurrence, data);
        return { ...occurrence };
      })
    },
    regularPairOccurrenceConfirmation: {
      createMany: vi.fn(async ({ data, skipDuplicates }: {
        data: Array<Pick<Confirmation, "occurrenceId" | "userId">>;
        skipDuplicates?: boolean;
      }) => {
        let count = 0;
        for (const row of data) {
          const key = `${row.occurrenceId}:${row.userId}`;
          if (confirmations.has(key)) {
            if (!skipDuplicates) throw new Error("Duplicate confirmation");
            continue;
          }
          confirmations.set(key, { ...row, status: "pending", respondedAt: null });
          count += 1;
        }
        return { count };
      })
    }
  };
  const sync = () => syncRegularPairOccurrences(
    db as unknown as Parameters<typeof syncRegularPairOccurrences>[0], pair.id
  );
  return { db, occurrences, confirmations, sync };
}

describe("regular pair occurrence confirmation synchronization", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    // A Thursday: the pair plays on Friday, so two slots fall in the next
    // fortnight. Slot times live in tests/regular-schedule-timezone.test.ts.
    vi.setSystemTime(new Date(2026, 8, 10, 12));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("allows concurrent syncs and creates one confirmation per player and slot", async () => {
    const store = createStore();

    const results = await Promise.all([store.sync(), store.sync(), store.sync()]);

    expect(store.occurrences.size).toBe(2);
    expect(store.confirmations.size).toBe(4);
    for (const result of results) {
      expect(result?.occurrences).toHaveLength(2);
      for (const occurrence of result!.occurrences) {
        expect(occurrence.confirmations.map((item) => item.userId).sort())
          .toEqual(["organizer", "partner"]);
        expect(occurrence.confirmations.every((item) => item.status === "pending")).toBe(true);
      }
    }
  });

  it("preserves both confirmed and declined responses when sync repeats", async () => {
    const store = createStore();
    await store.sync();
    const respondedAt = new Date(2026, 8, 10, 11);
    for (const confirmation of store.confirmations.values()) {
      confirmation.status = confirmation.userId === "organizer" ? "confirmed" : "declined";
      confirmation.respondedAt = respondedAt;
    }
    const previous = structuredClone([...store.confirmations.values()]);

    await Promise.all([store.sync(), store.sync()]);

    expect([...store.confirmations.values()]).toEqual(previous);
  });

  it("fills a missing player's confirmation without changing an existing answer", async () => {
    const store = createStore();
    await store.sync();
    const occurrence = [...store.occurrences.values()][0];
    const existing = store.confirmations.get(`${occurrence.id}:organizer`)!;
    existing.status = "confirmed";
    existing.respondedAt = new Date(2026, 8, 10, 11);
    const previous = { ...existing };
    store.confirmations.delete(`${occurrence.id}:partner`);

    await store.sync();

    expect(store.confirmations.size).toBe(4);
    expect(store.confirmations.get(`${occurrence.id}:organizer`)).toEqual(previous);
    expect(store.confirmations.get(`${occurrence.id}:partner`)).toEqual({
      occurrenceId: occurrence.id,
      userId: "partner",
      status: "pending",
      respondedAt: null
    });
  });

  it("propagates unrelated database failures", async () => {
    const store = createStore();
    const failure = new Error("Database unavailable");
    store.db.regularPairOccurrenceConfirmation.createMany.mockRejectedValueOnce(failure);

    await expect(store.sync()).rejects.toBe(failure);
  });
});
