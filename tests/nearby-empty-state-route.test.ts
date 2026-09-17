import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ session: vi.fn(), sections: vi.fn(), invite: vi.fn() }));
vi.mock("@/lib/auth", () => ({ getSessionUser: mocks.session }));
vi.mock("@/server/app-data", () => ({ getEmptyDeckClubSections: mocks.sections }));
vi.mock("@/lib/invites", () => ({ getInviteSummary: mocks.invite, buildInviteUrl: (code: string) => `https://example.test/i/${code}` }));
vi.mock("@/server/serializers", () => ({ serializeCourt: (court: unknown) => court }));

import { GET } from "@/app/discover/empty-state/route";

beforeEach(() => {
  vi.clearAllMocks();
  mocks.session.mockResolvedValue(null);
  mocks.sections.mockResolvedValue([]);
  mocks.invite.mockResolvedValue({ code: "invite-code", visits: 1, joined: 1 });
});

describe("nearby empty-state public contract", () => {
  it("accepts guest profile sports and canonical city without exposing invitation data", async () => {
    const nearby = { originCity: "Small Town", radiusKm: 50, distanceKm: 31 };
    mocks.sections.mockResolvedValue([{ sport: "tennis", total: 1, courts: [{
      id: "court", name: "Nearby club", city: "Next Town", nearby,
      distanceLabel: "31 км", activeSearchesCount: 0, memberCount: 0, activeSearchPreviewUsers: []
    }] }]);
    const response = await GET(new NextRequest("http://localhost/discover/empty-state?city=Small%20Town&locationPlaceId=place:small&sport=tennis,padel"));
    expect(response.status).toBe(200);
    expect(mocks.sections).toHaveBeenCalledWith(undefined, {
      city: "Small Town", locationPlaceId: "place:small", sport: ["tennis", "padel"]
    });
    expect(mocks.invite).not.toHaveBeenCalled();
    const body = await response.json();
    expect(body.invite).toBeNull();
    expect(body.sections[0].courts[0]).toMatchObject({ city: "Next Town", nearby });
  });

  it("retains the signed-in invitation for requests without new query fields", async () => {
    mocks.session.mockResolvedValue({ id: "viewer" });
    const response = await GET(new NextRequest("http://localhost/discover/empty-state"));
    expect(response.status).toBe(200);
    expect(mocks.invite).toHaveBeenCalledWith("viewer");
    expect((await response.json()).invite).toMatchObject({ url: "https://example.test/i/invite-code", visits: 1, joined: 1 });
  });

  it("rejects an invalid sport instead of silently widening guest suggestions", async () => {
    const response = await GET(new NextRequest("http://localhost/discover/empty-state?city=Small%20Town&sport=tennis,invalid"));
    expect(response.status).toBe(400);
    expect(mocks.sections).not.toHaveBeenCalled();
    expect(mocks.invite).not.toHaveBeenCalled();
  });
});
