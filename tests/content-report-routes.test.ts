import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  requireSessionUser: vi.fn(),
  requireAdminUser: vi.fn(),
  createReport: vi.fn(),
  blockAndReport: vi.fn(),
  listReports: vi.fn(),
  getReport: vi.fn(),
  resolveReport: vi.fn()
}));

vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.requireSessionUser }));
vi.mock("@/lib/admin", () => ({ requireAdminUser: mocks.requireAdminUser }));
vi.mock("@/server/content-reports", () => ({
  createUserContentReport: mocks.createReport,
  blockUserAndReport: mocks.blockAndReport,
  listAdminContentReports: mocks.listReports,
  getAdminContentReport: mocks.getReport,
  resolveAdminContentReport: mocks.resolveReport
}));

import { POST as reportPost } from "@/app/users/[id]/report/route";
import { POST as blockPost } from "@/app/users/[id]/block/route";
import { GET as adminList } from "@/app/api/admin/reports/route";
import { PATCH as adminResolve } from "@/app/api/admin/reports/[id]/route";

const summary = {
  id: "report-1",
  status: "pending",
  createdAt: "2026-08-24T12:00:00.000Z",
  dueAt: "2026-08-25T12:00:00.000Z"
};

describe("content report routes", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.requireSessionUser.mockResolvedValue({ id: "reporter-1" });
    mocks.requireAdminUser.mockResolvedValue({ id: "admin-1", email: "admin@example.com" });
    mocks.createReport.mockResolvedValue(summary);
    mocks.blockAndReport.mockResolvedValue(summary);
  });

  it("requires authentication for user reports", async () => {
    mocks.requireSessionUser.mockRejectedValue(new Error("UNAUTHORIZED"));
    const response = await reportPost(
      new NextRequest("https://example.com/users/target/report", {
        method: "POST",
        body: JSON.stringify({ reason: "harassment" })
      }),
      { params: { id: "target" } }
    );
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "Требуется авторизация" });
  });

  it("maps a missing reported user and returns the exact success envelope", async () => {
    mocks.createReport.mockRejectedValueOnce(new Error("REPORTED_USER_NOT_FOUND"));
    const missing = await reportPost(
      new NextRequest("https://example.com/users/missing/report", {
        method: "POST",
        body: JSON.stringify({ reason: "spam" })
      }),
      { params: { id: "missing" } }
    );
    expect(missing.status).toBe(404);

    const success = await reportPost(
      new NextRequest("https://example.com/users/target/report", {
        method: "POST",
        body: JSON.stringify({ reason: "harassment", context: { type: "profile" } })
      }),
      { params: { id: "target" } }
    );
    expect(success.status).toBe(201);
    expect(await success.json()).toEqual({ report: summary });
  });

  it("accepts a legacy empty block request and adds the report envelope", async () => {
    const response = await blockPost(
      new NextRequest("https://example.com/users/target/block", { method: "POST" }),
      { params: { id: "target" } }
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ success: true, report: summary });
    expect(mocks.blockAndReport).toHaveBeenCalledWith("reporter-1", "target", {});
  });

  it("enforces admin auth and maps stale decisions to conflict", async () => {
    mocks.requireAdminUser.mockRejectedValueOnce(new Error("FORBIDDEN"));
    const list = await adminList(new NextRequest("https://example.com/api/admin/reports"));
    expect(list.status).toBe(403);

    mocks.resolveReport.mockRejectedValue(new Error("STALE_CONTENT_REPORT"));
    const resolve = await adminResolve(
      new Request("https://example.com/api/admin/reports/report-1", {
        method: "PATCH",
        body: JSON.stringify({
          status: "dismissed",
          resolutionNote: "Нарушение не подтверждено",
          expectedUpdatedAt: "2026-08-24T12:00:00.000Z"
        })
      }),
      { params: { id: "report-1" } }
    );
    expect(resolve.status).toBe(409);
    expect(await resolve.json()).toEqual({ error: "Жалоба уже обработана или была изменена" });
  });
});
