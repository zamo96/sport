import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ user: vi.fn(), record: vi.fn(), opened: vi.fn(), activity: vi.fn() }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.user }));
vi.mock("@/server/user-events", () => ({ recordUserEvents: mocks.record }));
vi.mock("@/server/notification-campaigns", () => ({ markNotificationOpened: mocks.opened }));
vi.mock("@/server/user-activity", () => ({ touchUserActivity: mocks.activity }));
import { POST } from "@/app/activity/events/route";

function request(body: unknown, headers?: Record<string, string>) {
  return new Request("http://localhost/activity/events", { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
}
beforeEach(() => { vi.clearAllMocks(); mocks.user.mockResolvedValue({ id: "signed-in-user" }); mocks.record.mockResolvedValue(undefined); });
describe("independent QA: event ingestion boundaries", () => {
  it("denies an anonymous request before telemetry processing", async () => {
    mocks.user.mockRejectedValueOnce(new Error("UNAUTHORIZED"));
    expect((await POST(request({ events: [{ type: "app_open" }] }))).status).toBe(401);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it.each(["registration_completed", "profile_completed", "request_created", "request_accepted", "game_played", "message_sent", "search_created", "search_response"])("rejects forged milestone %s", async (type) => {
    expect((await POST(request({ events: [{ type }] }))).status).toBe(400);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it("binds events to the authenticated user and rejects private/unbounded context", async () => {
    const accepted = await POST(request({ events: [{ type: "discover_view", context: { platform: "web", screen: "discover" } }] }));
    expect(accepted.status).toBe(200);
    expect(mocks.record.mock.calls[0][0][0].userId).toBe("signed-in-user");
    expect(await accepted.json()).toMatchObject({ accepted: 1 });
    mocks.record.mockClear();
    for (const event of [
      { type: "app_open", userId: "victim" },
      { type: "app_open", context: { email: "private@example.com" } },
      { type: "app_open", context: { count: 10001 } },
      { type: "app_open", context: { screen: "https://example.com/private" } }
    ]) expect((await POST(request({ events: [event] }))).status).toBe(400);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it("enforces actual body size even without a declared content length", async () => {
    expect((await POST(request({ events: [{ type: "app_open", entityId: "x".repeat(17000) }] }))).status).toBe(413);
    expect((await POST(request({ events: [{ type: "app_open" }] }, { "content-length": "17000" }))).status).toBe(413);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it("deduplicates delivery opens inside a client batch", async () => {
    const response = await POST(request({ events: [{ type: "push_opened", deliveryId: "d1" }, { type: "push_opened", deliveryId: "d1" }] }));
    expect(response.status).toBe(200);
    expect(mocks.opened).toHaveBeenCalledTimes(1);
    expect(mocks.opened.mock.calls[0].slice(0, 2)).toEqual(["signed-in-user", "d1"]);
  });
});
