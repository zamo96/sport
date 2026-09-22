import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  session: vi.fn(),
  count: vi.fn(),
  getCandidates: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({ prisma: {} }));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.session }));
vi.mock("@/server/discover", () => ({
  countDiscoverCandidates: mocks.count,
  getDiscoverCandidates: mocks.getCandidates
}));

import { GET } from "@/app/users/discover/count/route";

const request = (query = "") => ({ nextUrl: new URL(`http://localhost/users/discover/count${query}`) }) as never;

beforeEach(() => {
  vi.resetAllMocks();
  mocks.session.mockResolvedValue({ id: "viewer-1" });
  mocks.count.mockResolvedValue(3);
});

describe("players tab badge count", () => {
  it("counts with the feed's own filters", async () => {
    const response = await GET(request("?sport=padel"));

    expect(await response.json()).toMatchObject({ count: 3 });
    expect(mocks.count).toHaveBeenCalledWith("viewer-1", expect.objectContaining({ sport: ["padel"] }));
  });

  it("never builds the ranked feed, so no impressions are recorded", async () => {
    await GET(request());

    expect(mocks.getCandidates).not.toHaveBeenCalled();
  });

  it("rejects anonymous requests", async () => {
    mocks.session.mockRejectedValue(new Error("UNAUTHORIZED"));

    expect((await GET(request())).status).toBe(401);
    expect(mocks.count).not.toHaveBeenCalled();
  });
});
