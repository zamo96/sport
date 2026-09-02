import Redis from "ioredis";

export type RealtimeEventType =
  | "notification"
  | "chat_message_created"
  | "game_request_created"
  | "game_request_updated"
  | "game_report_updated"
  | "match_created";

export type RealtimeEventPayload = {
  type: RealtimeEventType;
  createdAt?: string;
  title?: string;
  body?: string;
  href?: string;
  matchId?: string | null;
  searchId?: string | null;
  messageId?: string | null;
  gameRequestId?: string | null;
  deliveryId?: string | null;
  status?: string | null;
};

declare global {
  // eslint-disable-next-line no-var
  var realtimeRedis: Redis | undefined;
}

const STREAM_PREFIX = "tennis:realtime:user";
const ACTIVE_CHAT_PREFIX = "tennis:active-chat";
const STREAM_MAXLEN = Number(process.env.REALTIME_STREAM_MAXLEN ?? 1000);
const ACTIVE_CHAT_TTL_SECONDS = 90;

export function getRealtimeStreamKey(userId: string) {
  return `${STREAM_PREFIX}:${userId}`;
}

function getActiveChatKey(userId: string, conversationId: string) {
  return `${ACTIVE_CHAT_PREFIX}:${userId}:${conversationId}`;
}

export function getRealtimeRedis() {
  const redisUrl = resolveRealtimeRedisUrl(process.env.REDIS_URL, process.env.NODE_ENV);

  if (!redisUrl) {
    return null;
  }

  if (!global.realtimeRedis) {
    global.realtimeRedis = new Redis(redisUrl, {
      maxRetriesPerRequest: 2,
      enableReadyCheck: true,
      lazyConnect: false
    });

    global.realtimeRedis.on("error", (error) => {
      console.error("redis realtime error:", error.message);
    });
  }

  return global.realtimeRedis;
}

export function resolveRealtimeRedisUrl(configuredUrl: string | undefined, environment: string | undefined) {
  return configuredUrl?.trim() || (environment === "development" ? "redis://127.0.0.1:6379" : null);
}

export async function publishRealtimeEvent(userId: string | null | undefined, payload: RealtimeEventPayload) {
  if (!userId) {
    return;
  }

  const redis = getRealtimeRedis();
  if (!redis) {
    return;
  }

  const eventPayload: RealtimeEventPayload = {
    ...payload,
    createdAt: payload.createdAt ?? new Date().toISOString()
  };

  try {
    await redis.xadd(
      getRealtimeStreamKey(userId),
      "MAXLEN",
      "~",
      STREAM_MAXLEN,
      "*",
      "payload",
      JSON.stringify(eventPayload)
    );
  } catch (error) {
    console.error("redis realtime publish error:", error instanceof Error ? error.message : error);
  }
}

export async function publishRealtimeEventToUsers(
  userIds: Array<string | null | undefined>,
  payload: RealtimeEventPayload
) {
  const uniqueUserIds = Array.from(new Set(userIds.filter((userId): userId is string => Boolean(userId))));

  await Promise.all(uniqueUserIds.map((userId) => publishRealtimeEvent(userId, payload)));
}

export async function setActiveChatPresence(userId: string, conversationId: string) {
  const redis = getRealtimeRedis();
  if (!redis) {
    return;
  }

  try {
    await redis.set(getActiveChatKey(userId, conversationId), "1", "EX", ACTIVE_CHAT_TTL_SECONDS);
  } catch (error) {
    console.error("redis active chat set error:", error instanceof Error ? error.message : error);
  }
}

export async function clearActiveChatPresence(userId: string, conversationId: string) {
  const redis = getRealtimeRedis();
  if (!redis) {
    return;
  }

  try {
    await redis.del(getActiveChatKey(userId, conversationId));
  } catch (error) {
    console.error("redis active chat clear error:", error instanceof Error ? error.message : error);
  }
}

export async function isUserActiveInChat(userId: string, conversationIds: string[]) {
  const redis = getRealtimeRedis();
  if (!redis || conversationIds.length === 0) {
    return false;
  }

  try {
    const keys = conversationIds.map((conversationId) => getActiveChatKey(userId, conversationId));
    const values = await redis.mget(keys);
    return values.some(Boolean);
  } catch (error) {
    console.error("redis active chat read error:", error instanceof Error ? error.message : error);
    return false;
  }
}
