import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  gameSearchResponseFindMany: vi.fn(),
  gameRequestFindMany: vi.fn(),
  occurrenceConfirmationFindMany: vi.fn(),
  blockFindMany: vi.fn(),
  sendCampaignPush: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    gameSearchResponse: { findMany: mocks.gameSearchResponseFindMany },
    gameRequest: { findMany: mocks.gameRequestFindMany },
    regularPairOccurrenceConfirmation: { findMany: mocks.occurrenceConfirmationFindMany },
    block: { findMany: mocks.blockFindMany }
  }
}));

vi.mock("@/server/notification-campaigns", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/notification-campaigns")>();
  return { ...actual, sendCampaignPush: mocks.sendCampaignPush };
});

import {
  runGameOutcomePending,
  runPendingActionReminders,
  runRegularSlotConfirmationWaiting,
  runSearchResponseWaiting
} from "@/server/pending-action-reminders";

// 19:30Z — это уже 18 сентября в Новосибирске: удобный способ проверить, что
// ключ дедупа считается по календарю игрока, а не сервера.
const now = new Date("2026-09-17T19:30:00.000Z");

function searchResponse(overrides: Record<string, unknown> = {}) {
  return {
    id: "response-1",
    gameSearchId: "search-1",
    responderUserId: "responder-1",
    responderUser: { name: "Аня" },
    gameSearch: {
      createdByUserId: "owner-1",
      createdByUser: { timezone: "Europe/Moscow" }
    },
    ...overrides
  };
}

function player(id: string, name: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    name,
    timezone: "Europe/Moscow",
    notificationGames: true,
    pushDevices: [{ id: `device-${id}` }],
    ...overrides
  };
}

function gameRequest(overrides: Record<string, unknown> = {}) {
  return {
    id: "game-1",
    sharedRootId: null,
    proposedDatetime: new Date("2026-09-17T09:00:00.000Z"),
    createdByUser: player("creator-1", "Иван"),
    matchedUser: player("rival-1", "Пётр"),
    ...overrides
  };
}

/**
 * Слот ждёт ответа партнёра: организатор уже подтвердил, поэтому долг висит на
 * `partner-1` — именно ему и адресовано напоминание.
 */
function slotConfirmation(overrides: Record<string, unknown> = {}) {
  const { occurrence, ...rest } = overrides;

  return {
    id: "confirmation-1",
    userId: "partner-1",
    user: { timezone: "Europe/Moscow" },
    ...rest,
    occurrence: {
      id: "occurrence-1",
      scheduledAt: new Date("2026-09-19T16:00:00.000Z"),
      proposedCourt: { name: "Лужники" },
      regularPair: {
        id: "pair-1",
        gameSearchId: "search-1",
        createdByUserId: "organizer-1",
        partnerUserId: "partner-1",
        createdByUser: { name: "Иван" },
        partnerUser: { name: "Аня" },
        preferredCourt: { name: "ЦСКА" }
      },
      ...(occurrence as Record<string, unknown> | undefined)
    }
  };
}

beforeEach(() => {
  vi.resetAllMocks();
  mocks.gameSearchResponseFindMany.mockResolvedValue([]);
  mocks.gameRequestFindMany.mockResolvedValue([]);
  mocks.occurrenceConfirmationFindMany.mockResolvedValue([]);
  mocks.blockFindMany.mockResolvedValue([]);
  mocks.sendCampaignPush.mockResolvedValue({ status: "sent", reason: "ok", deliveryId: "delivery-1" });
  delete process.env.PENDING_ACTION_REMINDERS_ENABLED;
});

describe("search response waiting", () => {
  it("nudges the search owner and links straight to that search", async () => {
    mocks.gameSearchResponseFindMany.mockResolvedValue([searchResponse()]);

    const stats = await runSearchResponseWaiting(now);

    expect(stats.sent).toBe(1);
    const input = mocks.sendCampaignPush.mock.calls[0][0];
    expect(input.userId).toBe("owner-1");
    expect(input.href).toBe("/play/searches/search-1");
    expect(input.dedupeKey).toBe("search_response_waiting:owner-1:2026-09-17");
    expect(input.content("ru")).toEqual({
      title: "Аня ждёт вашего ответа",
      body: "Отклик на ваш поиск — подтвердите или отклоните"
    });
  });

  it("collapses several waiting responses into one push to the list", async () => {
    mocks.gameSearchResponseFindMany.mockResolvedValue([
      searchResponse(),
      searchResponse({ id: "response-2", gameSearchId: "search-2", responderUserId: "responder-2" })
    ]);

    await runSearchResponseWaiting(now);

    expect(mocks.sendCampaignPush).toHaveBeenCalledTimes(1);
    const input = mocks.sendCampaignPush.mock.calls[0][0];
    expect(input.href).toBe("/play/searches");
    expect(input.content("ru").title).toBe("2 отклика ждут ответа");
    expect(input.context).toEqual({
      responseIds: ["response-1", "response-2"],
      searchIds: ["search-1", "search-2"]
    });
  });

  it("stays silent when the pair is blocked", async () => {
    mocks.gameSearchResponseFindMany.mockResolvedValue([searchResponse()]);
    mocks.blockFindMany.mockResolvedValue([{ blockerUserId: "responder-1", blockedUserId: "owner-1" }]);

    const stats = await runSearchResponseWaiting(now);

    expect(mocks.sendCampaignPush).not.toHaveBeenCalled();
    expect(stats.scanned).toBe(0);
  });

  it("uses the owner's own calendar day for the dedupe key", async () => {
    mocks.gameSearchResponseFindMany.mockResolvedValue([
      searchResponse({
        gameSearch: {
          createdByUserId: "owner-1",
          createdByUser: { timezone: "Asia/Novosibirsk" }
        }
      })
    ]);

    await runSearchResponseWaiting(now);

    expect(mocks.sendCampaignPush.mock.calls[0][0].dedupeKey).toBe("search_response_waiting:owner-1:2026-09-18");
  });

  it("names the player when the profile has no name", async () => {
    mocks.gameSearchResponseFindMany.mockResolvedValue([searchResponse({ responderUser: { name: null } })]);

    await runSearchResponseWaiting(now);

    const content = mocks.sendCampaignPush.mock.calls[0][0].content;
    expect(content("ru").title).toBe("Игрок ждёт вашего ответа");
    expect(content("en").title).toBe("A player is waiting for your answer");
  });
});

describe("game outcome pending", () => {
  it("asks both players, because either of them can close the question", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([gameRequest()]);

    const stats = await runGameOutcomePending(now);

    expect(stats.sent).toBe(2);
    const [creator, rival] = mocks.sendCampaignPush.mock.calls.map((call) => call[0]);
    expect(creator.userId).toBe("creator-1");
    expect(creator.href).toBe("/play/games/game-1");
    expect(creator.content("ru").body).toBe("17.09, 12:00 · Пётр — отметьте, сыграли вы или нет");
    expect(rival.userId).toBe("rival-1");
    expect(rival.content("ru").body).toBe("17.09, 12:00 · Иван — отметьте, сыграли вы или нет");
  });

  it("skips a player with no device to reach", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([
      gameRequest({ matchedUser: player("rival-1", "Пётр", { pushDevices: [] }) })
    ]);

    await runGameOutcomePending(now);

    expect(mocks.sendCampaignPush).toHaveBeenCalledTimes(1);
    expect(mocks.sendCampaignPush.mock.calls[0][0].userId).toBe("creator-1");
  });

  it("skips a player who turned game notifications off", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([
      gameRequest({ matchedUser: player("rival-1", "Пётр", { notificationGames: false }) })
    ]);

    await runGameOutcomePending(now);

    expect(mocks.sendCampaignPush).toHaveBeenCalledTimes(1);
    expect(mocks.sendCampaignPush.mock.calls[0][0].userId).toBe("creator-1");
  });

  it("sends one push per player and opens the longest waiting game", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([
      gameRequest(),
      gameRequest({ id: "game-2", proposedDatetime: new Date("2026-09-17T13:00:00.000Z") })
    ]);

    await runGameOutcomePending(now);

    expect(mocks.sendCampaignPush).toHaveBeenCalledTimes(2);
    const creator = mocks.sendCampaignPush.mock.calls[0][0];
    expect(creator.href).toBe("/play/games/game-1");
    expect(creator.content("ru").title).toBe("2 игры ждут отметки");
    expect(creator.context).toEqual({ requestIds: ["game-1", "game-2"] });
  });

  it("stays silent when the pair is blocked", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([gameRequest()]);
    mocks.blockFindMany.mockResolvedValue([{ blockerUserId: "creator-1", blockedUserId: "rival-1" }]);

    await runGameOutcomePending(now);

    expect(mocks.sendCampaignPush).not.toHaveBeenCalled();
  });

  it("counts a group game as one game, not as one per invite", async () => {
    // Одна игра на троих — это три строки-приглашения с общим корнем.
    mocks.gameRequestFindMany.mockResolvedValue([
      gameRequest(),
      gameRequest({
        id: "game-1-invite-2",
        sharedRootId: "game-1",
        matchedUser: player("rival-2", "Олег")
      })
    ]);

    await runGameOutcomePending(now);

    const creator = mocks.sendCampaignPush.mock.calls.find((call) => call[0].userId === "creator-1")?.[0];
    expect(creator.content("ru").title).toBe("Как прошла игра?");
    expect(creator.context).toEqual({ requestIds: ["game-1", "game-1-invite-2"] });
  });
});

describe("reminder switch", () => {
  it("sends nothing until the switch is on", async () => {
    mocks.gameSearchResponseFindMany.mockResolvedValue([searchResponse()]);
    mocks.gameRequestFindMany.mockResolvedValue([gameRequest()]);

    const result = await runPendingActionReminders(now);

    expect(result.enabled).toBe(false);
    expect(mocks.gameSearchResponseFindMany).not.toHaveBeenCalled();
    expect(mocks.sendCampaignPush).not.toHaveBeenCalled();
  });

  it("runs the audience check on dry-run even with the switch off", async () => {
    mocks.gameSearchResponseFindMany.mockResolvedValue([searchResponse()]);
    mocks.sendCampaignPush.mockResolvedValue({
      status: "sent",
      reason: "ok",
      preview: { title: "Аня ждёт вашего ответа", body: "Отклик на ваш поиск", href: "/play/searches/search-1", locale: "ru" }
    });

    const result = await runPendingActionReminders(now, { dryRun: true });

    expect(result.enabled).toBe(true);
    expect(mocks.sendCampaignPush.mock.calls[0][0].dryRun).toBe(true);
    expect(result.searchResponseWaiting.samples).toHaveLength(1);
  });

  it("runs every campaign once the switch is on", async () => {
    process.env.PENDING_ACTION_REMINDERS_ENABLED = "1";
    mocks.gameSearchResponseFindMany.mockResolvedValue([searchResponse()]);
    mocks.gameRequestFindMany.mockResolvedValue([gameRequest()]);
    mocks.occurrenceConfirmationFindMany.mockResolvedValue([slotConfirmation()]);

    const result = await runPendingActionReminders(now);

    expect(result.enabled).toBe(true);
    expect(result.searchResponseWaiting.sent).toBe(1);
    expect(result.gameOutcomePending.sent).toBe(2);
    expect(result.regularSlotConfirmationWaiting.sent).toBe(1);
  });
});

describe("regular slot confirmation waiting", () => {
  it("nudges the player whose confirmation is missing, not the one who answered", async () => {
    mocks.occurrenceConfirmationFindMany.mockResolvedValue([slotConfirmation()]);

    const stats = await runRegularSlotConfirmationWaiting(now);

    expect(stats.sent).toBe(1);
    expect(mocks.sendCampaignPush).toHaveBeenCalledTimes(1);
    const input = mocks.sendCampaignPush.mock.calls[0][0];
    expect(input.userId).toBe("partner-1");
    expect(input.href).toBe("/play/searches/search-1");
    expect(input.dedupeKey).toBe("regular_slot_confirmation_waiting:partner-1:2026-09-17");
    expect(input.content("ru")).toEqual({
      title: "Иван ждёт вашего подтверждения",
      body: "19.09, 19:00 · Лужники — подтвердите, если время подходит"
    });
  });

  it("asks the organizer when the partner is the one who answered", async () => {
    mocks.occurrenceConfirmationFindMany.mockResolvedValue([
      slotConfirmation({ id: "confirmation-2", userId: "organizer-1" })
    ]);

    await runRegularSlotConfirmationWaiting(now);

    const input = mocks.sendCampaignPush.mock.calls[0][0];
    expect(input.userId).toBe("organizer-1");
    expect(input.content("ru").title).toBe("Аня ждёт вашего подтверждения");
  });

  it("falls back to the pair court when the slot has none", async () => {
    mocks.occurrenceConfirmationFindMany.mockResolvedValue([
      slotConfirmation({ occurrence: { proposedCourt: null } })
    ]);

    await runRegularSlotConfirmationWaiting(now);

    const content = mocks.sendCampaignPush.mock.calls[0][0].content;
    expect(content("ru").body).toBe("19.09, 19:00 · ЦСКА — подтвердите, если время подходит");
  });

  it("collapses several waiting slots of one pair into a single push", async () => {
    mocks.occurrenceConfirmationFindMany.mockResolvedValue([
      slotConfirmation(),
      slotConfirmation({
        id: "confirmation-2",
        occurrence: { id: "occurrence-2", scheduledAt: new Date("2026-09-26T16:00:00.000Z") }
      })
    ]);

    await runRegularSlotConfirmationWaiting(now);

    expect(mocks.sendCampaignPush).toHaveBeenCalledTimes(1);
    const input = mocks.sendCampaignPush.mock.calls[0][0];
    // Ведём в ближайший слот, а не в последний добавленный.
    expect(input.href).toBe("/play/searches/search-1");
    expect(input.content("ru").title).toBe("2 слота регулярной пары ждут вас");
    expect(input.context).toEqual({
      occurrenceIds: ["occurrence-1", "occurrence-2"],
      searchIds: ["search-1"]
    });
  });

  it("stays silent when the pair is blocked", async () => {
    mocks.occurrenceConfirmationFindMany.mockResolvedValue([slotConfirmation()]);
    mocks.blockFindMany.mockResolvedValue([{ blockerUserId: "organizer-1", blockedUserId: "partner-1" }]);

    const stats = await runRegularSlotConfirmationWaiting(now);

    expect(mocks.sendCampaignPush).not.toHaveBeenCalled();
    expect(stats.scanned).toBe(0);
  });

  it("waits three hours after the partner answered and only for the coming week", async () => {
    mocks.occurrenceConfirmationFindMany.mockResolvedValue([slotConfirmation()]);

    await runRegularSlotConfirmationWaiting(now);

    const where = mocks.occurrenceConfirmationFindMany.mock.calls[0][0].where;
    expect(where.occurrence.scheduledAt).toEqual({
      gt: now,
      lte: new Date("2026-09-24T19:30:00.000Z")
    });
    expect(where.occurrence.confirmations.some.respondedAt).toEqual({
      lte: new Date("2026-09-17T16:30:00.000Z"),
      gte: new Date("2026-09-15T19:30:00.000Z")
    });
  });
});
