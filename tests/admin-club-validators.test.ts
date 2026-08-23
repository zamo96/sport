import { CourtStatus } from "@prisma/client";
import { describe, expect, it } from "vitest";

import {
  adminClubProfilePatchSchema,
  adminClubsQuerySchema,
  adminClubStatusPatchSchema
} from "@/lib/validators";

const expectedUpdatedAt = "2026-08-23T10:00:00.000Z";

describe("admin club validators", () => {
  it("rejects protected synchronization fields", () => {
    expect(
      adminClubProfilePatchSchema.safeParse({
        expectedUpdatedAt,
        profile: { rating: 5, syncHash: "manual" }
      }).success
    ).toBe(false);
  });

  it("requires coordinate pairs and validates their range", () => {
    expect(adminClubProfilePatchSchema.safeParse({ expectedUpdatedAt, profile: { locationLat: 55.7 } }).success).toBe(false);
    expect(
      adminClubProfilePatchSchema.safeParse({
        expectedUpdatedAt,
        profile: { locationLat: 91, locationLng: 37.6 }
      }).success
    ).toBe(false);
    expect(
      adminClubProfilePatchSchema.safeParse({
        expectedUpdatedAt,
        profile: { locationLat: 55.7, locationLng: 37.6 }
      }).success
    ).toBe(true);
  });

  it("deduplicates bounded editable arrays", () => {
    const parsed = adminClubProfilePatchSchema.parse({
      expectedUpdatedAt,
      profile: {
        supportedSports: ["tennis", "tennis", "padel"],
        metroIds: ["metro-1", "metro-1"]
      }
    });
    expect(parsed.profile.supportedSports).toEqual(["tennis", "padel"]);
    expect(parsed.profile.metroIds).toEqual(["metro-1"]);
  });

  it("allows only http/https links", () => {
    expect(
      adminClubProfilePatchSchema.safeParse({ expectedUpdatedAt, profile: { websiteUrl: "javascript:alert(1)" } }).success
    ).toBe(false);
    expect(adminClubProfilePatchSchema.safeParse({ expectedUpdatedAt, profile: { websiteUrl: null } }).success).toBe(true);
  });

  it("requires a status reason and parses list filters", () => {
    expect(adminClubStatusPatchSchema.safeParse({ expectedUpdatedAt, status: CourtStatus.hidden }).success).toBe(false);
    expect(
      adminClubsQuerySchema.parse({ page: "2", limit: "50", city: "Москва", sport: "tennis" })
    ).toMatchObject({ page: 2, limit: 50, city: "Москва", sport: "tennis" });
  });
});
