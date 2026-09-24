import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ session: vi.fn(), token: vi.fn(), lockUsers: vi.fn(), query: vi.fn(), upsert: vi.fn() }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.session, getRequestSessionToken: mocks.token }));
vi.mock("@/server/account-status", () => ({ lockActiveUsersForMutation: mocks.lockUsers }));
vi.mock("@/lib/prisma", () => ({ prisma: { $transaction: async (callback: (tx: unknown) => unknown) => callback({ $queryRaw: mocks.query, pushDevice: { upsert: mocks.upsert } }) } }));
import { POST } from "@/app/devices/apns/route";
const request = () => new Request("https://example.com/devices/apns", { method: "POST", body: JSON.stringify({ token: "ab".repeat(32), environment: "production", bundleId: "shop.sportsearch.app" }) });
beforeEach(() => {
  vi.resetAllMocks();
  mocks.session.mockResolvedValue({ id: "owner" });
  mocks.token.mockReturnValue("session-token");
  mocks.lockUsers.mockResolvedValue(new Set(["owner"]));
});
describe("push registration session races", () => {
  it("rejects a registration if logout revoked its session after initial authentication", async () => {
    mocks.query.mockResolvedValue([]);
    expect((await POST(request())).status).toBe(401);
    expect(mocks.upsert).not.toHaveBeenCalled();
  });
  it("registers while holding the still-valid session row lock", async () => {
    mocks.query.mockResolvedValue([{ id: "session" }]);
    mocks.upsert.mockResolvedValue({ id: "device", token: "ab".repeat(32), isActive: true });
    expect((await POST(request())).status).toBe(200);
    const sql = mocks.query.mock.calls[0][0];
    expect(sql.sql).toContain("FOR UPDATE");
    expect(sql.sql).toContain('"expiresAt" > NOW()');
    expect(sql.values).toEqual(["session-token", "owner"]);
  });
});
