import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getSessionUser: vi.fn(),
  getCourtsForUser: vi.fn()
}));

vi.mock("@/lib/auth", () => ({
  getSessionUser: mocks.getSessionUser
}));

vi.mock("@/server/app-data", () => ({
  getCourtsForUser: mocks.getCourtsForUser
}));

vi.mock("@/server/serializers", () => ({
  serializeCourt: vi.fn((court) => court)
}));

import { GET } from "@/app/courts/route";
import { DEFAULT_CITY } from "@/lib/constants";

describe("GET /courts city fallback", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getCourtsForUser.mockResolvedValue([]);
  });

  it("prefers an explicit query city over the authenticated user's city", async () => {
    mocks.getSessionUser.mockResolvedValue({ id: "user-1", city: "Казань" });

    const response = await GET(new NextRequest("http://localhost/courts?city=Москва"));

    expect(response.status).toBe(200);
    expect(mocks.getCourtsForUser).toHaveBeenCalledWith("user-1", { city: "Москва" });
  });

  it("uses the authenticated user's city when the query omits it", async () => {
    mocks.getSessionUser.mockResolvedValue({ id: "user-1", city: "Казань" });

    const response = await GET(new NextRequest("http://localhost/courts"));

    expect(response.status).toBe(200);
    expect(mocks.getCourtsForUser).toHaveBeenCalledWith("user-1", { city: "Казань" });
  });

  it("uses the default city for an unauthenticated request without a city", async () => {
    mocks.getSessionUser.mockResolvedValue(null);

    const response = await GET(new NextRequest("http://localhost/courts"));

    expect(response.status).toBe(200);
    expect(mocks.getCourtsForUser).toHaveBeenCalledWith(undefined, { city: DEFAULT_CITY });
  });
});
