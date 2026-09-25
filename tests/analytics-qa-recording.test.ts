import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ create: vi.fn(), createMany: vi.fn(), requests: vi.fn(), users: vi.fn() }));
vi.mock("@/lib/prisma", () => ({ prisma: { userEvent: { create: mocks.create, createMany: mocks.createMany }, gameRequest: { findMany: mocks.requests }, user: { findMany: mocks.users } } }));
import { recordGameRequestMilestones, recordUserEvent, recordUserEventsOnce } from "@/server/user-events";

beforeEach(() => {
  vi.clearAllMocks();
  mocks.createMany.mockResolvedValue({ count: 1 });
  // Everyone in these cases has opted in to analytics.
  mocks.users.mockImplementation(async ({ where }: { where: { id: { in: string[] } } }) => where.id.in.map((id) => ({ id })));
});
describe("independent QA: best-effort milestone recording", () => {
  it("absorbs storage and roster lookup failures", async () => {
    const warning = vi.spyOn(console, "warn").mockImplementation(() => {});
    mocks.create.mockRejectedValueOnce(new Error("database unavailable"));
    await expect(recordUserEvent({ userId: "u1", type: "message_sent" })).resolves.toBeUndefined();
    mocks.createMany.mockRejectedValueOnce(new Error("database unavailable"));
    await expect(recordUserEventsOnce([{ userId: "u1", type: "profile_completed" }])).resolves.toBeUndefined();
    mocks.requests.mockRejectedValueOnce(new Error("database unavailable"));
    await expect(recordGameRequestMilestones(["g1"], "game_played", "outcome")).resolves.toBeUndefined();
    expect(warning).toHaveBeenCalledTimes(3);
    warning.mockRestore();
  });
  it("keeps milestone keys stable across retry metadata but distinct across users and games", async () => {
    await recordUserEventsOnce([{ userId: "u1", type: "request_accepted", entityType: "game_request", entityId: "g1", context: { source: "search" } }]);
    await recordUserEventsOnce([{ userId: "u1", type: "request_accepted", entityType: "game_request", entityId: "g1", context: { source: "proposal" } }]);
    await recordUserEventsOnce([{ userId: "u2", type: "request_accepted", entityType: "game_request", entityId: "g1" }, { userId: "u1", type: "request_accepted", entityType: "game_request", entityId: "g2" }]);
    const [first, second, third] = mocks.createMany.mock.calls.map(([arg]) => arg);
    expect(first.data[0].id).toBe(second.data[0].id);
    expect(new Set([first.data[0].id, ...third.data.map((event: { id: string }) => event.id)]).size).toBe(3);
    expect(first.skipDuplicates).toBe(true);
  });
  it("counts each accepted participant once when a shared root reports a played game", async () => {
    mocks.requests.mockResolvedValueOnce([{ id: "root", sharedRootId: null, createdByUserId: "creator", matchedUserId: "partner" }]);
    mocks.requests.mockResolvedValueOnce([
      { createdByUserId: "creator", matchedUserId: "partner" }, { createdByUserId: "creator", matchedUserId: "invitee" }
    ]);
    await recordGameRequestMilestones(["root"], "game_played", "report");
    const recorded = mocks.createMany.mock.calls[0][0].data;
    expect(recorded.map((event: { userId: string }) => event.userId).sort()).toEqual(["creator", "invitee", "partner"]);
    expect(recorded.every((event: { entityId: string }) => event.entityId === "root")).toBe(true);
    expect(mocks.requests.mock.calls[1][0].where).toMatchObject({ status: "accepted", AND: [{ OR: [{ outcome: null }, { outcome: "played" }] }, { NOT: { report: { status: "disputed" } } }] });
  });
  it("does not expand one child's explicit outcome to other group invitees", async () => {
    mocks.requests.mockResolvedValueOnce([{ id: "child", sharedRootId: "root", createdByUserId: "creator", matchedUserId: "invitee" }]);
    await recordGameRequestMilestones(["child"], "game_played", "outcome");
    expect(mocks.requests).toHaveBeenCalledTimes(1);
    expect(mocks.createMany.mock.calls[0][0].data.map((event: { userId: string }) => event.userId).sort()).toEqual(["creator", "invitee"]);
  });
});
