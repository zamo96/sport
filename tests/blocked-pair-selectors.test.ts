import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  matchFindMany: vi.fn(),
  matchFindFirst: vi.fn(),
  regularPairFindMany: vi.fn(),
  gameRequestFindMany: vi.fn(),
  occurrenceFindMany: vi.fn()
}));

vi.mock("@/lib/prisma", () => ({
  prisma: {
    match: { findMany: mocks.matchFindMany, findFirst: mocks.matchFindFirst },
    regularPair: { findMany: mocks.regularPairFindMany },
    gameRequest: { findMany: mocks.gameRequestFindMany },
    regularPairOccurrence: { findMany: mocks.occurrenceFindMany },
    gameSearch: { findFirst: vi.fn() }
  }
}));
vi.mock("@/server/game-request-maintenance", () => ({ runGameRequestMaintenance: vi.fn() }));
vi.mock("@/server/regular-occurrences", () => ({ syncRegularPairOccurrences: vi.fn() }));

import { getMatchDetail, getMatchesForUser, getUpcomingGamesForUser } from "@/server/app-data";

const pairFilter = {
  blockedUsers: { none: { blockedUserId: "viewer-1" } },
  blockingUsers: { none: { blockerUserId: "viewer-1" } }
};

describe("blocked-pair server selectors", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.matchFindMany.mockResolvedValue([]);
    mocks.matchFindFirst.mockResolvedValue(null);
    mocks.regularPairFindMany.mockResolvedValue([]);
    mocks.gameRequestFindMany.mockResolvedValue([]);
    mocks.occurrenceFindMany.mockResolvedValue([]);
  });

  it("excludes blocked pairs from match lists and detail", async () => {
    await getMatchesForUser("viewer-1");
    expect(mocks.matchFindMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ user1: pairFilter, user2: pairFilter })
    }));

    await getMatchDetail("match-1", "viewer-1");
    expect(mocks.matchFindFirst).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ user1: pairFilter, user2: pairFilter })
    }));
  });

  it("excludes blocked pairs from accepted upcoming games and regular occurrences", async () => {
    await getUpcomingGamesForUser("viewer-1");
    expect(mocks.gameRequestFindMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ createdByUser: pairFilter, matchedUser: pairFilter })
    }));
    expect(mocks.occurrenceFindMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({
        regularPair: expect.objectContaining({ createdByUser: pairFilter, partnerUser: pairFilter })
      })
    }));
  });
});
