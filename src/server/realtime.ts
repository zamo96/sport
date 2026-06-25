import Redis from "ioredis";

export type RealtimeEventType =
  | "notification"
  | "chat_message_created"
  | "game_request_created"
  | "game_request_updated"
  | "match_created";

export type RealtimeEventPayload = {
  type: RealtimeEventType;
  createdAt?: string;
  title?: string;
  body?: string;
  href?: string;
  matchId?: string | null;
  messageId?: string | null;
  gameRequestId?: string | null;
  status?: string | null;
};

declare global {
  // eslint-disable-next-line no-var
  var realtimeRedis: Redis | undefined;
}

const STREAM_PREFIX = "tennis:realtime:user";
const STREAM_MAXLEN = Number(process.env.REALTIME_STREAM_MAXLEN ?? 1000);

export function getRealtimeStreamKey(userId: string) {
  return `${STREAM_PREFIX}:${userId}`;
}

export function getRealtimeRedis() {
  const redisUrl = process.env.REDIS_URL?.trim();

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
