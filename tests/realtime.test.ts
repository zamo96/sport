import { describe, expect, it } from "vitest";

import { resolveRealtimeRedisUrl } from "@/server/realtime";

describe("realtime Redis configuration", () => {
  it("uses the local Redis service by default in development", () => {
    expect(resolveRealtimeRedisUrl(undefined, "development")).toBe("redis://127.0.0.1:6379");
  });

  it("keeps an explicitly configured Redis URL", () => {
    expect(resolveRealtimeRedisUrl(" redis://redis.internal:6380 ", "development")).toBe(
      "redis://redis.internal:6380"
    );
  });

  it("does not introduce a production fallback", () => {
    expect(resolveRealtimeRedisUrl(undefined, "production")).toBeNull();
  });
});
