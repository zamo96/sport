import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  userGroupBy: vi.fn(),
  gameRequestFindMany: vi.fn(),
  sendPushToUser: vi.fn(),
  getRealtimeRedis: vi.fn(),
  redisSet: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    user: { groupBy: mocks.userGroupBy },
    gameRequest: { findMany: mocks.gameRequestFindMany }
  }
}));
vi.mock("@/lib/push", () => ({ sendPushToUser: mocks.sendPushToUser }));
vi.mock("@/server/realtime", () => ({
  getRealtimeRedis: mocks.getRealtimeRedis,
  publishRealtimeEventToUsers: vi.fn()
}));

import { resolveReminderWindow, sendPendingGameRequestReminders } from "@/server/game-request-maintenance";

// 03:30Z — это 10:30 в Новосибирске (открытое утреннее окно) и 06:30 в Москве.
const now = new Date("2026-09-18T03:30:00.000Z");

function pendingRequest(timezone: string | null, overrides: Record<string, unknown> = {}) {
  return {
    id: "game-1",
    matchedUserId: "rival-1",
    proposedDatetime: new Date("2026-09-18T16:00:00.000Z"),
    proposedCourt: { name: "Корт на Лесной" },
    matchedUser: { id: "rival-1", notificationSound: true, timezone },
    ...overrides
  };
}

beforeEach(() => {
  vi.resetAllMocks();
  mocks.userGroupBy.mockResolvedValue([{ timezone: "Asia/Novosibirsk" }]);
  mocks.gameRequestFindMany.mockResolvedValue([]);
  mocks.redisSet.mockResolvedValue("OK");
  mocks.getRealtimeRedis.mockReturnValue({ set: mocks.redisSet });
});

describe("reminder windows", () => {
  it("never opens at night, which the shared Moscow slot used to do", () => {
    // Старый слот «час < 15 → утро» открывался первым же прогоном после
    // полуночи и будил игрока в 00:00.
    for (const hour of [0, 3, 6, 8, 9, 13, 16, 22, 23]) {
      const instant = new Date(Date.UTC(2026, 8, 18, hour - 3, 0, 0));
      expect(resolveReminderWindow(instant, "Europe/Moscow")).toBeNull();
    }
  });

  it("opens in the morning and in the evening", () => {
    const morning = resolveReminderWindow(new Date("2026-09-18T07:30:00.000Z"), "Europe/Moscow");
    expect(morning).toEqual({ dateKey: "2026-09-18", slot: "morning" });

    const evening = resolveReminderWindow(new Date("2026-09-18T17:30:00.000Z"), "Europe/Moscow");
    expect(evening).toEqual({ dateKey: "2026-09-18", slot: "evening" });
  });

  it("gives every player their own morning", () => {
    expect(resolveReminderWindow(now, "Asia/Novosibirsk")?.slot).toBe("morning");
    expect(resolveReminderWindow(now, "Europe/Moscow")).toBeNull();
    expect(resolveReminderWindow(now, "Europe/London")).toBeNull();
  });

  it("keys the slot by the player's own calendar day", () => {
    // 13:30Z — 16:30 в Москве (окна закрыты) и 20:30 в Новосибирске.
    const evening = new Date("2026-09-18T13:30:00.000Z");
    expect(resolveReminderWindow(evening, "Europe/Moscow")).toBeNull();
    expect(resolveReminderWindow(evening, "Asia/Novosibirsk")).toEqual({
      dateKey: "2026-09-18",
      slot: "evening"
    });

    // 22:30Z — по серверному календарю ещё 18-е, а в Окленде уже утро 19-го:
    // ключ дедупа обязан быть от даты игрока, иначе слоты соседних суток
    // схлопнутся в один.
    expect(resolveReminderWindow(new Date("2026-09-18T22:30:00.000Z"), "Pacific/Auckland")).toEqual({
      dateKey: "2026-09-19",
      slot: "morning"
    });
  });

  it("falls back to Moscow when the player has no timezone", () => {
    expect(resolveReminderWindow(new Date("2026-09-18T07:30:00.000Z"), null)?.slot).toBe("morning");
    expect(resolveReminderWindow(now, null)).toBeNull();
  });
});

describe("pending game request reminders", () => {
  it("prints the game time in the player's zone", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([pendingRequest("Asia/Novosibirsk")]);

    await sendPendingGameRequestReminders(now);

    expect(mocks.sendPushToUser).toHaveBeenCalledTimes(1);
    const push = mocks.sendPushToUser.mock.calls[0][0];
    // 16:00Z — это 23:00 в Новосибирске, а не 19:00, как печатал сервер.
    expect(push.body).toBe("Корт на Лесной · 18.09.2026, 23:00");
    expect(push.href).toBe("/play/games/game-1");
  });

  it("dedupes on the player's local day and slot", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([pendingRequest("Asia/Novosibirsk")]);

    await sendPendingGameRequestReminders(now);

    expect(mocks.redisSet).toHaveBeenCalledWith(
      "tennis:game-request-reminder:game-1:2026-09-18:morning",
      "1",
      "EX",
      129600,
      "NX"
    );
  });

  it("stays quiet outside the player's own window and does not touch redis", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([pendingRequest("Europe/Moscow")]);

    await sendPendingGameRequestReminders(now);

    expect(mocks.redisSet).not.toHaveBeenCalled();
    expect(mocks.sendPushToUser).not.toHaveBeenCalled();
  });

  it("sends once per slot", async () => {
    mocks.gameRequestFindMany.mockResolvedValue([pendingRequest("Asia/Novosibirsk")]);
    mocks.redisSet.mockResolvedValue(null);

    await sendPendingGameRequestReminders(now);

    expect(mocks.sendPushToUser).not.toHaveBeenCalled();
  });

  it("does not even look at the requests while every zone sleeps", async () => {
    mocks.userGroupBy.mockResolvedValue([{ timezone: "Europe/Moscow" }, { timezone: "Europe/London" }]);

    await sendPendingGameRequestReminders(now);

    expect(mocks.gameRequestFindMany).not.toHaveBeenCalled();
  });

  it("asks only for the players whose window is open", async () => {
    mocks.userGroupBy.mockResolvedValue([
      { timezone: "Asia/Novosibirsk" },
      { timezone: "Europe/Moscow" },
      { timezone: null }
    ]);

    await sendPendingGameRequestReminders(now);

    expect(mocks.gameRequestFindMany.mock.calls[0][0].where.matchedUser).toEqual({
      notificationGames: true,
      timezone: { in: ["Asia/Novosibirsk"] }
    });
  });

  it("keeps players without a timezone together with the Moscow fallback", async () => {
    mocks.userGroupBy.mockResolvedValue([{ timezone: "Europe/Moscow" }, { timezone: null }]);

    // 07:30Z — 10:30 в Москве, окно открыто и для тех, у кого зоны нет.
    await sendPendingGameRequestReminders(new Date("2026-09-18T07:30:00.000Z"));

    expect(mocks.gameRequestFindMany.mock.calls[0][0].where.matchedUser).toEqual({
      notificationGames: true,
      OR: [{ timezone: { in: ["Europe/Moscow"] } }, { timezone: null }]
    });
  });

  it("sends nothing at all without redis", async () => {
    mocks.getRealtimeRedis.mockReturnValue(null);
    mocks.gameRequestFindMany.mockResolvedValue([pendingRequest("Asia/Novosibirsk")]);

    await sendPendingGameRequestReminders(now);

    expect(mocks.userGroupBy).not.toHaveBeenCalled();
    expect(mocks.gameRequestFindMany).not.toHaveBeenCalled();
    expect(mocks.sendPushToUser).not.toHaveBeenCalled();
  });
});
