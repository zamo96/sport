import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  occurrenceFindUnique: vi.fn(),
  sendPushToUser: vi.fn(),
  publishRealtimeEventToUsers: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    regularPairOccurrence: { findUnique: mocks.occurrenceFindUnique }
  }
}));

vi.mock("@/lib/push", () => ({ sendPushToUser: mocks.sendPushToUser }));

vi.mock("@/server/realtime", () => ({
  publishRealtimeEventToUsers: mocks.publishRealtimeEventToUsers
}));

import { notifyRegularOccurrencePartner } from "@/server/regular-occurrence-notifications";

function player(id: string, name: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    name,
    timezone: "Europe/Moscow",
    notificationGames: true,
    notificationSound: true,
    ...overrides
  };
}

function occurrence(overrides: Record<string, unknown> = {}) {
  const { regularPair, ...rest } = overrides;

  return {
    id: "occurrence-1",
    scheduledAt: new Date("2026-09-19T16:00:00.000Z"),
    durationMinutes: 90,
    status: "pending",
    proposedCourt: { name: "Лужники" },
    gameRequest: null,
    ...rest,
    regularPair: {
      id: "pair-1",
      matchId: "match-1",
      gameSearchId: "search-1",
      preferredCourt: { name: "ЦСКА" },
      createdByUser: player("organizer-1", "Иван"),
      partnerUser: player("partner-1", "Аня"),
      ...(regularPair as Record<string, unknown> | undefined)
    }
  };
}

beforeEach(() => {
  vi.resetAllMocks();
  mocks.occurrenceFindUnique.mockResolvedValue(occurrence());
});

describe("regular slot notifications", () => {
  it("asks the partner to confirm the time the organizer just moved", async () => {
    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "organizer-1",
      change: "proposal"
    });

    expect(mocks.sendPushToUser).toHaveBeenCalledTimes(1);
    expect(mocks.sendPushToUser.mock.calls[0][0]).toEqual({
      userId: "partner-1",
      title: "Новое время регулярной игры от Иван",
      body: "19.09.2026, 19:00 · Лужники — подтвердите, если время подходит.",
      href: "/play/searches/search-1",
      sound: true
    });
  });

  it("asks the organizer when the partner is the one who moved the slot", async () => {
    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "partner-1",
      change: "proposal"
    });

    const push = mocks.sendPushToUser.mock.calls[0][0];
    expect(push.userId).toBe("organizer-1");
    expect(push.title).toBe("Новое время регулярной игры от Аня");
  });

  it("says whose confirmation is still missing", async () => {
    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "organizer-1",
      change: "confirmed"
    });

    expect(mocks.sendPushToUser.mock.calls[0][0]).toMatchObject({
      userId: "partner-1",
      title: "Иван подтвердил(а) слот",
      body: "19.09.2026, 19:00 · Лужники — ждём вашего подтверждения."
    });
  });

  it("opens the created game once both players confirmed", async () => {
    mocks.occurrenceFindUnique.mockResolvedValue(
      occurrence({ status: "confirmed", gameRequest: { id: "game-1" } })
    );

    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "partner-1",
      change: "confirmed"
    });

    expect(mocks.sendPushToUser.mock.calls[0][0]).toMatchObject({
      userId: "organizer-1",
      title: "Регулярная игра подтверждена",
      href: "/play/games/game-1"
    });
  });

  it("asks for another time instead of a confirmation the partner already refused", async () => {
    mocks.occurrenceFindUnique.mockResolvedValue(occurrence({ status: "declined" }));

    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "organizer-1",
      change: "confirmed"
    });

    expect(mocks.sendPushToUser.mock.calls[0][0]).toMatchObject({
      userId: "partner-1",
      body: "19.09.2026, 19:00 · Лужники — вы отметили, что не сможете. Предложите другое время."
    });
  });

  it("tells the partner to pick another time after a decline", async () => {
    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "partner-1",
      change: "declined"
    });

    expect(mocks.sendPushToUser.mock.calls[0][0]).toMatchObject({
      userId: "organizer-1",
      title: "Аня не сможет играть"
    });
  });

  it("formats the time in the recipient's own zone", async () => {
    mocks.occurrenceFindUnique.mockResolvedValue(
      occurrence({
        regularPair: {
          id: "pair-1",
          matchId: "match-1",
          gameSearchId: "search-1",
          preferredCourt: { name: "ЦСКА" },
          createdByUser: player("organizer-1", "Иван"),
          partnerUser: player("partner-1", "Аня", { timezone: "Asia/Novosibirsk" })
        }
      })
    );

    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "organizer-1",
      change: "proposal"
    });

    expect(mocks.sendPushToUser.mock.calls[0][0].body).toContain("19.09.2026, 23:00");
  });

  it("still refreshes an open screen when the partner turned pushes off", async () => {
    mocks.occurrenceFindUnique.mockResolvedValue(
      occurrence({
        regularPair: {
          id: "pair-1",
          matchId: "match-1",
          gameSearchId: "search-1",
          preferredCourt: null,
          createdByUser: player("organizer-1", "Иван"),
          partnerUser: player("partner-1", "Аня", { notificationGames: false })
        }
      })
    );

    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "organizer-1",
      change: "proposal"
    });

    expect(mocks.sendPushToUser).not.toHaveBeenCalled();
    expect(mocks.publishRealtimeEventToUsers).toHaveBeenCalledWith(["organizer-1", "partner-1"], {
      type: "game_request_updated",
      matchId: "match-1",
      searchId: "search-1",
      gameRequestId: null,
      status: "pending",
      href: "/play/searches/search-1"
    });
  });

  it("stays silent when the actor is not in the pair", async () => {
    await notifyRegularOccurrencePartner({
      occurrenceId: "occurrence-1",
      actorUserId: "stranger-1",
      change: "confirmed"
    });

    expect(mocks.sendPushToUser).not.toHaveBeenCalled();
    expect(mocks.publishRealtimeEventToUsers).not.toHaveBeenCalled();
  });
});
