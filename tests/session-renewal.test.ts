import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  cookieGet: vi.fn(),
  cookieSet: vi.fn(),
  headerGet: vi.fn(),
  sessionFindUnique: vi.fn(),
  sessionUpdate: vi.fn()
}));

vi.mock("next/headers", () => ({
  cookies: () => ({ get: mocks.cookieGet, set: mocks.cookieSet, delete: vi.fn() }),
  headers: () => ({ get: mocks.headerGet })
}));

vi.mock("@/lib/prisma", () => ({
  prisma: { session: { findUnique: mocks.sessionFindUnique, update: mocks.sessionUpdate } }
}));

import { getSessionUser } from "@/lib/auth";

const DAY = 24 * 60 * 60 * 1000;
const now = new Date("2026-09-27T12:00:00.000Z");
const user = { id: "player-1", accountStatus: "active" };

function sessionExpiringIn(ms: number) {
  mocks.sessionFindUnique.mockResolvedValue({ id: "session-1", expiresAt: new Date(now.getTime() + ms), user });
}

describe("sliding session expiry", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(now);
    mocks.cookieGet.mockReturnValue({ value: "session-token" });
    mocks.headerGet.mockReturnValue(null);
    mocks.sessionUpdate.mockResolvedValue({});
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("extends a session to 180 days from its last use", async () => {
    sessionExpiringIn(10 * DAY);

    await expect(getSessionUser()).resolves.toEqual(user);
    expect(mocks.sessionUpdate).toHaveBeenCalledWith({
      where: { id: "session-1" },
      data: { expiresAt: new Date(now.getTime() + 180 * DAY) }
    });
    expect(mocks.cookieSet).toHaveBeenCalledWith("tennis_session", "session-token", expect.objectContaining({
      expires: new Date(now.getTime() + 400 * DAY),
      httpOnly: true
    }));
  });

  it("writes at most once a day, not on every request", async () => {
    sessionExpiringIn(180 * DAY - 60 * 60 * 1000);

    await expect(getSessionUser()).resolves.toEqual(user);
    expect(mocks.sessionUpdate).not.toHaveBeenCalled();
    expect(mocks.cookieSet).not.toHaveBeenCalled();
  });

  it("does not revive an expired session", async () => {
    sessionExpiringIn(-DAY);

    await expect(getSessionUser()).resolves.toBeNull();
    expect(mocks.sessionUpdate).not.toHaveBeenCalled();
  });

  it("leaves cookies alone for app requests with a bearer token", async () => {
    mocks.headerGet.mockImplementation((name: string) => (name === "authorization" ? "Bearer app-token" : null));
    sessionExpiringIn(10 * DAY);

    await expect(getSessionUser()).resolves.toEqual(user);
    expect(mocks.sessionFindUnique).toHaveBeenCalledWith(expect.objectContaining({ where: { token: "app-token" } }));
    expect(mocks.sessionUpdate).toHaveBeenCalledOnce();
    expect(mocks.cookieSet).not.toHaveBeenCalled();
  });

  it("still lets the request through when the renewal write or cookie fails", async () => {
    sessionExpiringIn(10 * DAY);
    mocks.cookieSet.mockImplementation(() => {
      throw new Error("Cookies can only be modified in a Server Action or Route Handler");
    });

    await expect(getSessionUser()).resolves.toEqual(user);

    mocks.sessionUpdate.mockRejectedValue(new Error("database unavailable"));
    await expect(getSessionUser()).resolves.toEqual(user);
  });
});
