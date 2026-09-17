import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ create: vi.fn(), createMany: vi.fn(), findMany: vi.fn() }));
vi.mock("@/lib/prisma", () => ({ prisma: { userEvent: { create: mocks.create, createMany: mocks.createMany }, gameRequest: { findMany: mocks.findMany } } }));
import { recordGameRequestMilestones, recordUserEvent, recordUserEventsOnce } from "@/server/user-events";

const root = { id: "root", sharedRootId: null, createdByUserId: "organizer", matchedUserId: "player" };
describe("committed user telemetry", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.create.mockResolvedValue({});
    mocks.createMany.mockResolvedValue({ count: 1 });
  });

  it("does not let failed telemetry fail the product action", async () => {
    mocks.create.mockRejectedValue(new Error("db unavailable"));
    const warning = vi.spyOn(console, "warn").mockImplementation(() => {});
    await expect(recordUserEvent({ userId: "player", type: "message_sent" })).resolves.toBeUndefined();
    expect(warning).toHaveBeenCalled();
    warning.mockRestore();
  });

  it("deduplicates concurrent milestone retries with the same primary key and keeps participants separate", async () => {
    const event = { userId: "player", type: "profile_completed" as const, entityType: "user", entityId: "player" };
    await Promise.all([recordUserEventsOnce([event]), recordUserEventsOnce([event])]);
    const [first, second] = mocks.createMany.mock.calls.map(([input]) => input);
    expect(first.data[0].id).toBe(second.data[0].id);
    expect(first.skipDuplicates).toBe(true);
    await recordUserEventsOnce([{ ...event, userId: "other" }]);
    expect(mocks.createMany.mock.calls[2][0].data[0].id).not.toBe(first.data[0].id);
  });

  it("accepted milestones cover only the changed accepted pair", async () => {
    mocks.findMany.mockResolvedValue([{ ...root, id: "child", sharedRootId: "root", matchedUserId: "joined" }]);
    await recordGameRequestMilestones(["child"], "request_accepted", "search");
    expect(mocks.findMany.mock.calls[0][0].where).toEqual({ id: { in: ["child"] }, status: "accepted" });
    expect(mocks.findMany).toHaveBeenCalledTimes(1);
    expect(mocks.createMany.mock.calls[0][0].data.map((event: { userId: string }) => event.userId)).toEqual(["organizer", "joined"]);
    expect(mocks.createMany.mock.calls[0][0].data.every((event: { entityId: string }) => event.entityId === "root")).toBe(true);
  });

  it("root played includes only accepted, non-disputed participants without a contrary outcome", async () => {
    mocks.findMany.mockResolvedValueOnce([root]).mockResolvedValueOnce([root, { createdByUserId: "organizer", matchedUserId: "joined" }]);
    await recordGameRequestMilestones(["root"], "game_played", "report");
    const rosterFilter = mocks.findMany.mock.calls[1][0].where;
    expect(rosterFilter.status).toBe("accepted");
    expect(rosterFilter.AND).toContainEqual({ OR: [{ outcome: null }, { outcome: "played" }] });
    expect(rosterFilter.AND).toContainEqual({ NOT: { report: { status: "disputed" } } });
    expect(mocks.createMany.mock.calls[0][0].data.map((event: { userId: string }) => event.userId)).toEqual(["organizer", "player", "joined"]);
    expect(mocks.createMany.mock.calls[0][0].data[0].context).toEqual({ source: "report" });
  });

  it("a child played outcome never attributes a game to unrelated group participants", async () => {
    mocks.findMany.mockResolvedValue([{ ...root, id: "child", sharedRootId: "root" }]);
    await recordGameRequestMilestones(["child"], "game_played", "outcome");
    expect(mocks.findMany).toHaveBeenCalledTimes(1);
    expect(mocks.createMany.mock.calls[0][0].data).toHaveLength(2);
  });

  it("does not fabricate a milestone when the committed state was reversed or canceled", async () => {
    mocks.findMany.mockResolvedValue([]);
    await recordGameRequestMilestones(["root"], "game_played", "outcome");
    expect(mocks.findMany.mock.calls[0][0].where).toMatchObject({ status: "accepted", outcome: "played", NOT: { report: { status: "disputed" } } });
    expect(mocks.createMany).not.toHaveBeenCalled();
  });
});
