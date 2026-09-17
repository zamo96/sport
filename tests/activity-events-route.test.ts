import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ session: vi.fn(), record: vi.fn(), opened: vi.fn(), touch: vi.fn() }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.session }));
vi.mock("@/server/user-events", () => ({ recordUserEvents: mocks.record }));
vi.mock("@/server/notification-campaigns", () => ({ markNotificationOpened: mocks.opened }));
vi.mock("@/server/user-activity", () => ({ touchUserActivity: mocks.touch }));
import { POST } from "@/app/activity/events/route";

describe("activity ingestion boundary", () => {
  beforeEach(() => { vi.resetAllMocks(); mocks.session.mockResolvedValue({ id: "session-user" }); });
  const request = (body: unknown) => new Request("http://localhost/activity/events", { method: "POST", body: JSON.stringify(body) });
  it("uses the session identity and accepts bounded client context", async () => {
    const response = await POST(request({ events: [{ type: "discover_view", context: { platform: "web", screen: "discover", empty: true } }] }));
    expect(response.status).toBe(200);
    expect(mocks.record.mock.calls[0][0][0]).toMatchObject({ userId: "session-user", type: "discover_view" });
  });
  it("rejects unauthorized requests", async () => {
    mocks.session.mockRejectedValue(new Error("UNAUTHORIZED"));
    expect((await POST(request({ events: [{ type: "app_open" }] }))).status).toBe(401);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it.each(["registration_completed", "profile_completed", "request_accepted", "game_played"])("rejects forged %s", async (type) => {
    expect((await POST(request({ events: [{ type }] }))).status).toBe(400);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it.each([{ email: "private@example.com" }, { path: "/inbox/private" }, { screen: "arbitrary" }, { count: -1 }])("rejects unsupported metadata %j", async (context) => {
    expect((await POST(request({ events: [{ type: "app_open", context }] }))).status).toBe(400);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it("caps actual bytes even without a declared content-length", async () => {
    const response = await POST(new Request("http://localhost/activity/events", { method: "POST", body: " ".repeat(16385) }));
    expect(response.status).toBe(413);
    expect(mocks.record).not.toHaveBeenCalled();
  });
  it("deduplicates opened deliveries and scopes ownership by session", async () => {
    expect((await POST(request({ events: [{ type: "push_opened", deliveryId: "delivery" }, { type: "push_opened", deliveryId: "delivery" }] }))).status).toBe(200);
    expect(mocks.opened).toHaveBeenCalledTimes(1);
    expect(mocks.opened).toHaveBeenCalledWith("session-user", "delivery", expect.any(Date));
  });
});
