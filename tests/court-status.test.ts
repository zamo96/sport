import { describe, expect, it, vi } from "vitest";

import { assertActiveCourtIds } from "@/server/court-status";

describe("court status mutation guard", () => {
  it("accepts empty or duplicated active references", async () => {
    const count = vi.fn().mockResolvedValue(1);
    const client = { court: { count }, $queryRaw: vi.fn().mockResolvedValue([]) } as never;

    await expect(assertActiveCourtIds(client, [null, "court-1", "court-1"])).resolves.toBeUndefined();
    expect(count).toHaveBeenCalledWith({ where: { id: { in: ["court-1"] }, status: "active" } });
  });

  it("rejects a reference when any court is not active", async () => {
    const client = { court: { count: vi.fn().mockResolvedValue(1) }, $queryRaw: vi.fn().mockResolvedValue([]) } as never;
    await expect(assertActiveCourtIds(client, ["court-1", "court-2"])).rejects.toThrow("COURT_UNAVAILABLE");
  });
});
