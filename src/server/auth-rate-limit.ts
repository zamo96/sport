import { createHash } from "node:crypto";

import { getRealtimeRedis } from "@/server/realtime";

type AuthAction = "request" | "verify" | "phone-request" | "phone-verify" | "vk";

/** [лимит на идентификатор, лимит на IP] за окно. SMS платные, поэтому их лимит строже. */
const LIMITS: Record<AuthAction, [number, number]> = {
  request: [5, 30],
  verify: [10, 100],
  "phone-request": [3, 20],
  "phone-verify": [10, 100],
  vk: [30, 30]
};
const WINDOW_MS = 10 * 60_000;
const MAX_LOCAL_BUCKETS = 10_000;
const localBuckets = new Map<string, { count: number; resetAt: number }>();

// One atomic operation for all limits, shared across server processes.
const RATE_LIMIT_SCRIPT = `
local allowed = 1
for i, key in ipairs(KEYS) do
  local count = redis.call('INCR', key)
  if count == 1 then redis.call('PEXPIRE', key, ARGV[1]) end
  if count > tonumber(ARGV[i + 1]) then allowed = 0 end
end
return allowed
`;

function digest(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

/** `identifier` — email, номер телефона или имя способа входа, если своего идентификатора нет. */
export async function enforceAuthRateLimit(action: AuthAction, identifier: string, request: Request) {
  // The production reverse proxy must replace these headers, never append untrusted input.
  const ip = request.headers.get("x-real-ip")?.trim()
    || request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || "unknown";
  const keys = [
    `tennis:auth:${action}:id:${digest(identifier.trim().toLowerCase())}`,
    `tennis:auth:${action}:ip:${digest(ip)}`
  ];
  const limits = LIMITS[action];
  const redis = getRealtimeRedis();

  if (redis) {
    let allowed: unknown;
    try {
      allowed = await redis.eval(RATE_LIMIT_SCRIPT, keys.length, ...keys, WINDOW_MS, ...limits);
    } catch {
      // An unavailable distributed limiter must never turn into unlimited login attempts.
      if (process.env.NODE_ENV === "production") throw new Error("AUTH_RATE_LIMIT_UNAVAILABLE");
    }
    if (allowed !== undefined) {
      if (allowed !== 1) throw new Error("AUTH_RATE_LIMITED");
      return;
    }
  }

  if (process.env.NODE_ENV === "production") {
    throw new Error("AUTH_RATE_LIMIT_UNAVAILABLE");
  }

  const now = Date.now();
  for (const [key, bucket] of localBuckets) {
    if (bucket.resetAt <= now) localBuckets.delete(key);
  }
  if (localBuckets.size + keys.filter((key) => !localBuckets.has(key)).length > MAX_LOCAL_BUCKETS) {
    throw new Error("AUTH_RATE_LIMITED");
  }
  const allowed = keys.map((key, index) => {
    const bucket = localBuckets.get(key) ?? { count: 0, resetAt: now + WINDOW_MS };
    bucket.count += 1;
    localBuckets.set(key, bucket);
    return bucket.count <= limits[index];
  }).every(Boolean);
  if (!allowed) throw new Error("AUTH_RATE_LIMITED");
}
