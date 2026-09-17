import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ requireAdminUser: vi.fn(), getAdminAnalyticsExport: vi.fn() }));
vi.mock("@/lib/admin", () => ({ requireAdminUser: mocks.requireAdminUser }));
vi.mock("@/server/admin-analytics", () => ({ getAdminAnalyticsExport: mocks.getAdminAnalyticsExport }));
import { GET } from "@/app/api/admin/analytics/export/route";

beforeEach(() => { vi.clearAllMocks(); });
describe("admin analytics CSV access", () => {
  it.each([["UNAUTHORIZED", 401], ["FORBIDDEN", 403], ["ADMIN_UNCONFIGURED", 503]])("rejects %s before reading analytics", async (message, status) => {
    mocks.requireAdminUser.mockRejectedValueOnce(new Error(String(message)));
    const response = await GET(new Request("http://localhost/api/admin/analytics/export"));
    expect(response.status).toBe(status);
    expect(mocks.getAdminAnalyticsExport).not.toHaveBeenCalled();
  });
  it("preserves authorized filters and marks a truncated export", async () => {
    mocks.requireAdminUser.mockResolvedValueOnce({ id: "admin" });
    mocks.getAdminAnalyticsExport.mockResolvedValueOnce({ items: [], truncated: true });
    const response = await GET(new Request("http://localhost/api/admin/analytics/export?days=7&userId=u1&eventType=swipe"));
    expect(response.status).toBe(200);
    expect(mocks.getAdminAnalyticsExport).toHaveBeenCalledWith({ days: 7, userId: "u1", eventType: "swipe" });
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(response.headers.get("x-export-truncated")).toBe("true");
    expect(response.headers.get("content-disposition")).toContain("-truncated.csv");
    expect(await response.text()).toContain("EXPORT_TRUNCATED");
  });
});
