import { describe, expect, it } from "vitest";
import { otherUserFromMatch, serializeMe, serializeUserPreview } from "@/server/serializers";

const privateUser = (id: string) => ({ id, name: id, city: "Санкт-Петербург", showOnMap: true, preferredDistricts: ["primorsky"],
  preferredSports: ["tennis"], sportLevels: { tennis: 6 }, homeLat: 61.23456, homeLng: 31.98765,
  email: `${id}@private.test`, appleSubject: "private-apple", notificationSound: true, invitedByUserId: "private-inviter", accountStatus: "active" });

describe("public map response privacy", () => {
  it("maps stored null districts across the known city without exposing profile coordinates", () => {
    const result = serializeUserPreview({ ...privateUser("city-player"), preferredDistricts: null } as Parameters<typeof serializeUserPreview>[0]);
    expect(result.mapAreas).toHaveLength(18);
    expect(result.mapAreas.every((area) => area.cityName === "Санкт-Петербург")).toBe(true);
    expect(JSON.stringify(result)).not.toContain("61.23456");
    expect(JSON.stringify(result)).not.toContain("31.98765");
  });
  it("redacts all nested raw users and terminates relation graphs", () => {
    const owner = privateUser("owner");
    const nested = { ...privateUser("partner"), gameSearches: [] as unknown[] };
    const search = { id: "search", sport: "tennis", isActive: true, createdByUserId: "owner", createdByUser: owner,
      regularPair: { id: "pair", matchId: "match", partnerUserId: "partner", partnerUser: nested, createdByUser: owner },
      responses: [{ id: "response", gameSearchId: "search", responderUserId: "responder", status: "approved", responderUser: privateUser("responder") }] };
    nested.gameSearches.push(search);
    const serialized = serializeUserPreview({ ...owner, gameSearches: [search] } as Parameters<typeof serializeUserPreview>[0]);
    const text = JSON.stringify(serialized);
    for (const secret of ["homeLat", "homeLng", "61.23456", "31.98765", "@private.test", "appleSubject", "notificationSound", "invitedByUserId", "accountStatus"]) {
      expect(text).not.toContain(secret);
    }
    expect(serialized.mapAreas).toHaveLength(1);
    expect(serialized.gameSearches?.[0]).toMatchObject({ id: "search", sport: "tennis", regularPair: { id: "pair", matchId: "match",
      partnerUser: { id: "partner", preferredSports: ["tennis"], mapAreas: expect.any(Array) } },
      responses: [{ id: "response", responderUserId: "responder", status: "approved", responderUser: { id: "responder" } }] });
  });
  it("projects match counterparts instead of returning raw User", () => {
    const match = { user1Id: "viewer", user1: privateUser("viewer"), user2: privateUser("other") };
    const other = otherUserFromMatch(match as Parameters<typeof otherUserFromMatch>[0], "viewer");
    expect(other).toMatchObject({ id: "other", preferredSports: ["tennis"], showOnMap: true });
    expect(other).not.toHaveProperty("homeLat");
    expect(other).not.toHaveProperty("email");
  });
  it("defaults old me records to off and immediately removes revoked map memberships", () => {
    expect(serializeMe({ id: "legacy", showOnMap: undefined })).toMatchObject({ showOnMap: false });
    expect(serializeUserPreview({ ...privateUser("owner"), showOnMap: false } as Parameters<typeof serializeUserPreview>[0]).mapAreas).toEqual([]);
  });
});
