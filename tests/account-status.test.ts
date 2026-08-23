import { describe, expect, it, vi } from "vitest";

import { lockActiveUsersForMutation } from "@/server/account-status";

describe("active account mutation locks", () => {
  it("locks unique user rows in deterministic order", async () => {
    const queryRaw = vi.fn().mockResolvedValue([{ id: "user-a" }, { id: "user-b" }]);

    const locked = await lockActiveUsersForMutation(
      { $queryRaw: queryRaw } as never,
      ["user-b", "user-a", "user-b"]
    );

    expect(Array.from(locked)).toEqual(["user-a", "user-b"]);
    const query = queryRaw.mock.calls[0][0] as { sql: string; values: unknown[] };
    expect(query.sql).toContain('ORDER BY "id"');
    expect(query.sql).toContain("FOR UPDATE");
    expect(query.values).toEqual(["user-a", "user-b"]);
  });

  it("does not query when there are no users to lock", async () => {
    const queryRaw = vi.fn();
    await expect(lockActiveUsersForMutation({ $queryRaw: queryRaw } as never, [])).resolves.toEqual(new Set());
    expect(queryRaw).not.toHaveBeenCalled();
  });
});
