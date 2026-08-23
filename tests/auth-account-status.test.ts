import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  cookieGet: vi.fn(),
  cookieSet: vi.fn(),
  cookieDelete: vi.fn(),
  headerGet: vi.fn(),
  userFindUnique: vi.fn(),
  sessionFindUnique: vi.fn(),
  sessionCreate: vi.fn(),
  transaction: vi.fn(),
  queryRaw: vi.fn()
}));

vi.mock("next/headers", () => ({
  cookies: () => ({ get: mocks.cookieGet, set: mocks.cookieSet, delete: mocks.cookieDelete }),
  headers: () => ({ get: mocks.headerGet })
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    user: { findUnique: mocks.userFindUnique },
    session: { findUnique: mocks.sessionFindUnique },
    $transaction: mocks.transaction
  }
}));

import { createSession, getSessionUser } from "@/lib/auth";

describe("account status auth guards", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.cookieGet.mockReturnValue({ value: "session-token" });
    mocks.transaction.mockImplementation(async (callback: (tx: unknown) => unknown) =>
      callback({ $queryRaw: mocks.queryRaw, session: { create: mocks.sessionCreate } })
    );
  });

  it("does not accept an existing session for a deactivated account", async () => {
    mocks.sessionFindUnique.mockResolvedValue({
      expiresAt: new Date("2099-01-01T00:00:00.000Z"),
      user: { id: "player-1", accountStatus: "deactivated" }
    });

    await expect(getSessionUser()).resolves.toBeNull();
  });

  it("does not create a new session for a deactivated account", async () => {
    mocks.queryRaw.mockResolvedValue([]);

    await expect(createSession("player-1")).rejects.toThrow("ACCOUNT_DEACTIVATED");
    expect(mocks.sessionCreate).not.toHaveBeenCalled();
    expect(mocks.cookieSet).not.toHaveBeenCalled();
  });
});
