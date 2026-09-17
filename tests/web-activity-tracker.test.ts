import { describe, expect, it, vi } from "vitest";

import { analyticsScreen, RouteEventTracker } from "@/components/analytics/route-events";

function sessionStore() {
  const entries = new Map<string, string>();
  return { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value); }, removeItem: (key: string) => { entries.delete(key); } };
}

describe("web activity telemetry", () => {
  it("only maps supported screens and never includes private route details", () => {
    expect(analyticsScreen("/admin/players/private-user")).toBeNull();
    expect(analyticsScreen("/auth")).toBeNull();
    expect(analyticsScreen("/discover?email=private@example.com")).toBeNull();
    expect(analyticsScreen("/unexpected-route")).toBeNull();
    expect(analyticsScreen("/play/games/private-game")).toBe("play");
    expect(analyticsScreen("/inbox/private-match")).toBe("inbox");
    expect(analyticsScreen("/matches/private-match")).toBeNull();
  });

  it("deduplicates StrictMode replays and throttles repeat views", async () => {
    const tracker = new RouteEventTracker();
    const send = vi.fn(async () => true);
    const storage = sessionStore();
    await Promise.all([tracker.visit("/discover", { now: 1000, storage, send }), tracker.visit("/discover", { now: 1000, storage, send })]);
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]).toEqual([[{ type: "app_open", context: { platform: "web", screen: "discover" } }, { type: "discover_view", context: { platform: "web", screen: "discover" } }]]);
    await tracker.visit("/discover", { now: 62_000, storage, send });
    expect(send.mock.calls[1]).toEqual([[{ type: "discover_view", context: { platform: "web", screen: "discover" } }]]);
  });

  it("preserves app-open deduplication after page reload within the session window", async () => {
    const storage = sessionStore();
    const send = vi.fn(async () => true);
    await new RouteEventTracker().visit("/profile", { now: 1000, storage, send });
    await new RouteEventTracker().visit("/profile", { now: 2000, storage, send });
    expect(send).toHaveBeenCalledTimes(1);
    await new RouteEventTracker().visit("/profile", { now: 1_802_000, storage, send });
    expect(send).toHaveBeenCalledTimes(2);
  });

  it("does not mark unauthorized or failed ingestion as accepted and retries after cooldown", async () => {
    const tracker = new RouteEventTracker();
    const send = vi.fn().mockResolvedValueOnce(false).mockResolvedValueOnce(true);
    await tracker.visit("/profile", { now: 1000, send });
    await tracker.visit("/profile", { now: 62_000, send });
    expect(send).toHaveBeenCalledTimes(2);
    expect(send.mock.calls[1][0][0].type).toBe("app_open");
    const failing = new RouteEventTracker();
    await expect(failing.visit("/profile", { now: 1000, send: async () => { throw new Error("offline"); } })).resolves.toBeUndefined();
  });

  it("resets the session marker at auth and only records entry into onboarding", async () => {
    const tracker = new RouteEventTracker();
    const send = vi.fn(async () => true);
    const storage = sessionStore();
    await tracker.visit("/profile", { now: 1000, storage, send });
    await tracker.visit("/auth", { now: 2000, storage, send });
    await tracker.visit("/onboarding", { now: 3000, storage, send });
    expect(send.mock.calls[1]).toEqual([[{ type: "app_open", context: { platform: "web", screen: "onboarding" } }, { type: "onboarding_step", context: { platform: "web", screen: "onboarding", step: 0 } }]]);
  });
});
