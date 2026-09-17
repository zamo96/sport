import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({
  session: vi.fn(), transaction: vi.fn(), swipe: vi.fn(), push: vi.fn(), record: vi.fn(), once: vi.fn(), lock: vi.fn(), realtime: vi.fn(),
  user: vi.fn(), block: vi.fn(), match: vi.fn()
}));
vi.mock("@/lib/auth", () => ({ requireSessionUser: mocks.session }));
vi.mock("@/lib/prisma", () => ({ prisma: { $transaction: mocks.transaction } }));
vi.mock("@/lib/apns", () => ({ sendPushToUser: mocks.push }));
vi.mock("@/server/user-events", () => ({ recordUserEvent: mocks.record, recordUserEventsOnce: mocks.once }));
vi.mock("@/server/matching", () => ({ createSwipeAndMaybeMatch: mocks.swipe }));
vi.mock("@/server/account-status", () => ({ lockActiveUsersForMutation: mocks.lock }));
vi.mock("@/server/realtime", () => ({ publishRealtimeEventToUsers: mocks.realtime }));
import { POST } from "@/app/swipes/route";
const request = () => new NextRequest("http://localhost/swipes", { method: "POST", body: JSON.stringify({ toUserId: "target", action: "like" }) });
describe("successful swipe instrumentation", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.session.mockResolvedValue({ id: "actor", onboardingCompleted: true, preferredSports: ["tennis"], city: "Санкт-Петербург" });
    mocks.lock.mockResolvedValue(new Set(["actor", "target"]));
    mocks.user.mockResolvedValue({ id: "target", notificationMatches: true });
    mocks.match.mockResolvedValue(null);
    mocks.block.mockResolvedValue(null);
    mocks.swipe.mockResolvedValue({ swipe: { id: "swipe" }, match: null });
    mocks.transaction.mockImplementation(async (callback) => callback({
      user: { findUniqueOrThrow: mocks.user }, block: { findFirst: mocks.block }, match: { findUnique: mocks.match }
    }));
  });
  it("records committed action before a later push failure, without notification text", async () => {
    mocks.push.mockRejectedValue(new Error("APNS unavailable"));
    await POST(request());
    expect(mocks.record).toHaveBeenCalledWith({ userId: "actor", type: "swipe", entityType: "user", entityId: "target", context: { action: "like" } });
    expect(mocks.record.mock.invocationCallOrder[0]).toBeLessThan(mocks.push.mock.invocationCallOrder[0]);
  });
  it("does not record a failed or rolled-back action", async () => {
    mocks.transaction.mockRejectedValue(new Error("transaction rolled back"));
    expect((await POST(request())).status).toBe(400);
    expect(mocks.record).not.toHaveBeenCalled();
    expect(mocks.once).not.toHaveBeenCalled();
  });
  it("records a newly created mutual match for both players", async () => {
    mocks.swipe.mockResolvedValue({ swipe: { id: "swipe" }, match: { id: "match" } });
    expect((await POST(request())).status).toBe(200);
    expect(mocks.once).toHaveBeenCalledWith([
      { userId: "actor", type: "match_created", entityType: "match", entityId: "match" },
      { userId: "target", type: "match_created", entityType: "match", entityId: "match" }
    ]);
  });
  it("does not describe an existing match as newly created", async () => {
    mocks.match.mockResolvedValue({ id: "existing" });
    mocks.swipe.mockResolvedValue({ swipe: { id: "swipe" }, match: { id: "existing" } });
    expect((await POST(request())).status).toBe(200);
    expect(mocks.once).not.toHaveBeenCalled();
  });
});

describe("incomplete profiles cannot send interest", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.lock.mockResolvedValue(new Set(["actor", "target"]));
    mocks.swipe.mockResolvedValue({ swipe: { id: "swipe" }, match: null });
  });

  it("rejects a like while onboarding is unfinished", async () => {
    mocks.session.mockResolvedValue({ id: "actor", onboardingCompleted: false, preferredSports: ["tennis"], city: "Санкт-Петербург" });
    const response = await POST(request());
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({ errorCode: "PROFILE_INCOMPLETE" });
    expect(mocks.swipe).not.toHaveBeenCalled();
    expect(mocks.push).not.toHaveBeenCalled();
  });

  it("rejects a like when no sport is chosen", async () => {
    mocks.session.mockResolvedValue({ id: "actor", onboardingCompleted: true, preferredSports: [], city: "Санкт-Петербург" });
    expect((await POST(request())).status).toBe(403);
    expect(mocks.swipe).not.toHaveBeenCalled();
  });

  it("rejects a like when no city or place is set", async () => {
    mocks.session.mockResolvedValue({ id: "actor", onboardingCompleted: true, preferredSports: ["tennis"], city: null });
    expect((await POST(request())).status).toBe(403);
    expect(mocks.swipe).not.toHaveBeenCalled();
  });

  it("still allows a dislike, which creates no notification", async () => {
    mocks.session.mockResolvedValue({ id: "actor", onboardingCompleted: false, preferredSports: [], city: null });
    mocks.user.mockResolvedValue({ id: "target", notificationMatches: true });
    mocks.match.mockResolvedValue(null);
    mocks.block.mockResolvedValue(null);
    mocks.transaction.mockImplementation(async (callback) => callback({
      user: { findUniqueOrThrow: mocks.user }, block: { findFirst: mocks.block }, match: { findUnique: mocks.match }
    }));
    const dislike = new NextRequest("http://localhost/swipes", { method: "POST", body: JSON.stringify({ toUserId: "target", action: "dislike" }) });
    expect((await POST(dislike)).status).toBe(200);
  });
});
