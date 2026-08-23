import { AccountStatus } from "@prisma/client";
import { describe, expect, it } from "vitest";

import {
  adminPlayerProfilePatchSchema,
  adminPlayersQuerySchema,
  adminPlayerStatusPatchSchema
} from "@/lib/validators";

describe("admin player validators", () => {
  it("requires a reason when deactivating an account", () => {
    const result = adminPlayerStatusPatchSchema.safeParse({
      status: AccountStatus.deactivated,
      expectedUpdatedAt: "2026-08-23T10:00:00.000Z"
    });

    expect(result.success).toBe(false);
  });

  it("requires a reason for reactivation too", () => {
    expect(
      adminPlayerStatusPatchSchema.safeParse({
        status: AccountStatus.active,
        expectedUpdatedAt: "2026-08-23T10:00:00.000Z"
      }).success
    ).toBe(false);
    expect(
      adminPlayerStatusPatchSchema.safeParse({
        status: AccountStatus.active,
        reason: "Апелляция одобрена",
        expectedUpdatedAt: "2026-08-23T10:00:00.000Z"
      }).success
    ).toBe(true);
  });

  it("rejects protected fields in profile edits", () => {
    expect(
      adminPlayerProfilePatchSchema.safeParse({
        expectedUpdatedAt: "2026-08-23T10:00:00.000Z",
        profile: { email: "hijack@example.com" }
      }).success
    ).toBe(false);
  });

  it("normalizes pagination query parameters", () => {
    const result = adminPlayersQuerySchema.parse({ page: "2", limit: "50", status: "all" });
    expect(result).toMatchObject({ page: 2, limit: 50, status: "all" });
  });
});
