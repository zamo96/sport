import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ destroy: vi.fn() }));
vi.mock("@/lib/auth", () => ({ destroySession: mocks.destroy }));
import { POST } from "@/app/auth/logout/route";

beforeEach(() => vi.resetAllMocks());
describe("logout request compatibility", () => {
  it("accepts an empty web request body", async () => {
    expect((await POST(new Request("https://example.com/auth/logout", { method: "POST" }))).status).toBe(200);
    expect(mocks.destroy).toHaveBeenCalledWith(undefined);
  });
  it("normalizes the optional native APNs token", async () => {
    expect((await POST(new Request("https://example.com/auth/logout", { method: "POST", body: JSON.stringify({ pushDeviceToken: "AB".repeat(32) }) }))).status).toBe(200);
    expect(mocks.destroy).toHaveBeenCalledWith("ab".repeat(32));
  });
  it("rejects malformed device tokens without changing the session", async () => {
    expect((await POST(new Request("https://example.com/auth/logout", { method: "POST", body: JSON.stringify({ pushDeviceToken: "arbitrary" }) }))).status).toBe(400);
    expect(mocks.destroy).not.toHaveBeenCalled();
  });
});
