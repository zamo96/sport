import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ getRedis: vi.fn(), eval: vi.fn() }));
vi.mock("@/server/realtime", () => ({ getRealtimeRedis: mocks.getRedis }));

let enforce: typeof import("@/server/auth-rate-limit").enforceAuthRateLimit;
const request = (ip = "192.0.2.1") => new Request("https://example.com/auth/verify", { headers: { "x-real-ip": ip } });
beforeEach(async () => {
  vi.resetModules();
  vi.resetAllMocks();
  vi.stubEnv("NODE_ENV", "test");
  mocks.getRedis.mockReturnValue(null);
  enforce = (await import("@/server/auth-rate-limit")).enforceAuthRateLimit;
});
afterEach(() => { vi.unstubAllEnvs(); vi.useRealTimers(); });

describe("shared login throttling", () => {
  it("enforces request and verify limits per email despite rotating IPs", async () => {
    for (let i = 0; i < 5; i++) await enforce("request", "owner@example.com", request(`192.0.2.${i}`));
    await expect(enforce("request", "OWNER@example.com", request("198.51.100.1"))).rejects.toThrow("AUTH_RATE_LIMITED");
    for (let i = 0; i < 10; i++) await enforce("verify", "owner@example.com", request(`192.0.2.${i}`));
    await expect(enforce("verify", "owner@example.com", request("198.51.100.1"))).rejects.toThrow("AUTH_RATE_LIMITED");
  });
  it("enforces an IP limit despite rotating email addresses", async () => {
    for (let i = 0; i < 30; i++) await enforce("request", `user${i}@example.com`, request());
    await expect(enforce("request", "new@example.com", request())).rejects.toThrow("AUTH_RATE_LIMITED");
  });
  it("expires local windows", async () => {
    vi.useFakeTimers();
    for (let i = 0; i < 5; i++) await enforce("request", "owner@example.com", request());
    vi.advanceTimersByTime(10 * 60_000);
    await expect(enforce("request", "owner@example.com", request())).resolves.toBeUndefined();
  });
  it("does not store raw email or IP in Redis keys and passes both limits atomically", async () => {
    mocks.getRedis.mockReturnValue({ eval: mocks.eval });
    mocks.eval.mockResolvedValue(1);
    await enforce("verify", "owner@example.com", request());
    const args = mocks.eval.mock.calls[0];
    expect(args[1]).toBe(2);
    expect(args.slice(4)).toEqual([600000, 10, 100]);
    expect(args.slice(2, 4).join()).not.toMatch(/owner@example|192\.0\.2/);
  });
  it("honors shared Redis rejection without falling back locally", async () => {
    mocks.getRedis.mockReturnValue({ eval: mocks.eval });
    mocks.eval.mockResolvedValue(0);
    await expect(enforce("verify", "owner@example.com", request())).rejects.toThrow("AUTH_RATE_LIMITED");
  });
  it.each(["missing", "unavailable"])("fails closed in production when Redis is %s", async (condition) => {
    vi.stubEnv("NODE_ENV", "production");
    if (condition === "unavailable") {
      mocks.getRedis.mockReturnValue({ eval: mocks.eval });
      mocks.eval.mockRejectedValue(new Error("Redis down"));
    }
    await expect(enforce("verify", "owner@example.com", request())).rejects.toThrow("AUTH_RATE_LIMIT_UNAVAILABLE");
  });
  it("uses the bounded fallback for local development when Redis fails", async () => {
    vi.stubEnv("NODE_ENV", "development");
    mocks.getRedis.mockReturnValue({ eval: mocks.eval });
    mocks.eval.mockRejectedValue(new Error("Redis down"));
    for (let i = 0; i < 10; i++) await enforce("verify", "owner@example.com", request());
    await expect(enforce("verify", "owner@example.com", request())).rejects.toThrow("AUTH_RATE_LIMITED");
  });
});
